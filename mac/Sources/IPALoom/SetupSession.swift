import Foundation

/// An iPhone or iPad app installed from the Mac App Store: what first setup builds the
/// decryption model from.
struct InstalledApp: Identifiable, Equatable {
    var path: String
    var name: String
    var version: String
    var itemID: Int
    var id: String { path }
    var storeLink: String { "https://apps.apple.com/app/id\(itemID)" }
}

enum InstalledApps {
    /// The same rule the engine uses: a wrapped iOS bundle that carries a Store item and version.
    static func identity(of app: URL) -> InstalledApp? {
        let metadata = app.appendingPathComponent("Wrapper/iTunesMetadata.plist")
        guard let data = try? Data(contentsOf: metadata),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let item = plist["itemId"] as? Int, item > 0,
              let version = plist["bundleShortVersionString"] as? String, !version.isEmpty else { return nil }
        let fallback = app.deletingPathExtension().lastPathComponent
        let raw = (plist["itemName"] as? String) ?? fallback
        let name = String(raw.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 })
            .trimmingCharacters(in: .whitespaces)
        return InstalledApp(path: app.path, name: name.isEmpty ? fallback : name, version: version, itemID: item)
    }

    static func discover(in folder: URL = URL(fileURLWithPath: "/Applications")) -> [InstalledApp] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(identity)
    }
}

/// Turns what a terminal program prints into lines: carriage returns redraw the current line,
/// colour and cursor codes are dropped, and a character split across two reads is kept whole.
struct TerminalText {
    private(set) var lines: [String] = []
    private(set) var current = ""
    private var pending = Data()
    private var afterReturn = false
    private var escape: String?

    mutating func feed(_ data: Data) {
        pending.append(data)
        // Keep an unfinished UTF-8 character for the next read.
        var cut = pending.count
        var back = 0
        while back < 3, cut - back > 0 {
            let byte = pending[pending.startIndex + cut - back - 1]
            if byte & 0xC0 == 0x80 { back += 1; continue }
            let length = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            if length > back + 1 { cut -= back + 1 }
            break
        }
        let text = String(decoding: pending.prefix(cut), as: UTF8.self)
        pending = Data(pending.dropFirst(cut))
        for character in text.unicodeScalars {
            if let sequence = escape {
                // Skip "ESC [ ... letter" and two-character escapes.
                if sequence.isEmpty {
                    escape = character == "[" ? "[" : nil
                } else if (0x40...0x7E).contains(character.value) {
                    escape = nil
                }
                continue
            }
            switch character {
            case "\u{1B}": escape = ""
            case "\n":
                lines.append(current)
                if lines.count > 400 { lines.removeFirst(lines.count - 400) }
                current = ""
                afterReturn = false
            case "\r": afterReturn = true
            default:
                if afterReturn { current = ""; afterReturn = false }
                if character.value >= 32 || character == "\t" { current.unicodeScalars.append(character) }
            }
        }
    }
}

/// First setup, run by the engine on a terminal of its own that the app stands in front of.
/// The app picks the model app, shows the engine's phases, and passes on what the user types
/// when the engine's tools ask (Apple sign-in, the administrator password). It keeps nothing.
@MainActor
final class SetupSession: ObservableObject {
    enum State: Equatable { case running, passed, failed(String), cancelled }
    static let phases = ["Prepare tools", "Choose an app", "Sign in to Apple",
                         "Download and build the model", "Verify and finish"]

    let app: InstalledApp
    @Published var state: State = .running
    @Published var phase = 0
    @Published var text = TerminalText()
    /// What the engine's tool is asking, while it waits for a typed answer.
    @Published var prompt: String?
    /// Whether typed characters are shown: off while a tool reads a password.
    @Published var echo = true
    /// The questions shown so far, without the answers (for the debug self-check).
    private(set) var asked: [String] = []

    /// What a waiting tool wants, so the app can show a proper form for the ones it knows.
    enum Question: Hashable { case appleAccount, applePassword, verificationCode, adminPassword, other(String) }

    var question: Question? {
        guard let prompt else { return nil }
        let line = prompt.lowercased()
        if line.hasPrefix("enter apple id") { return .appleAccount }
        if line.hasPrefix("enter password") { return .applePassword }
        if line.hasPrefix("enter 2fa") { return .verificationCode }
        if line.hasPrefix("password:") || line.hasPrefix("sorry, try again") { return .adminPassword }
        return .other(prompt)
    }

    /// The Apple password typed together with the Apple ID, held only until the sign-in tool
    /// asks for it a moment later, then dropped.
    private var heldPassword: String?

    /// Answers the Apple ID question and keeps the password for the question that follows.
    func signIn(appleID: String, password: String) {
        heldPassword = password.isEmpty ? nil : password
        send(appleID)
    }

    private var process: Process?
    private var input: FileHandle?
    private var generation = 0
    private var answeredApp = false
    private var answeredLink = false
    private var cancelRequested = false
    private var onFinish: (() -> Void)?

    init(app: InstalledApp) { self.app = app }

    var isRunning: Bool { state == .running }

    /// The line to show as the current status: the unfinished line, or the last finished one.
    var status: String {
        let line = text.current.trimmingCharacters(in: .whitespaces)
        if !line.isEmpty, prompt == nil { return SetupSession.plain(line) }
        return text.lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { SetupSession.plain($0.trimmingCharacters(in: .whitespaces)) } ?? "Starting"
    }

    /// A progress line without its moving bar.
    private static func plain(_ line: String) -> String {
        var result = line
        if result.hasPrefix("> ") { result.removeFirst(2) }
        if let bar = result.range(of: #"\s*\[[.#]+\]\s*$"#, options: .regularExpression) { result.removeSubrange(bar) }
        return result
    }

    func start(command override: [String]? = nil, onFinish: @escaping () -> Void) {
        guard let root = Paths.engineRoot else {
            state = .failed("The engine is missing from this app.")
            return
        }
        self.onFinish = onFinish
        let python = "/usr/bin/python3"
        let command = override ?? [python, "-B", root.appendingPathComponent("scripts/entry.py").path, "--setup"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-B", root.appendingPathComponent("scripts/terminal_bridge.py").path] + command
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.received(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let notes = String(decoding: handle.availableData, as: UTF8.self)
            guard !notes.isEmpty else { return }
            Task { @MainActor in
                for note in notes.split(separator: "\n") {
                    if note == "echo=0" { self?.echo = false }
                    if note == "echo=1" { self?.echo = true }
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let rest = stdout.fileHandleForReading.readDataToEndOfFile()
            Task { @MainActor in self?.finished(code: code, rest: rest) }
        }
        do {
            try process.run()
        } catch {
            state = .failed("The engine could not be started: \(error.localizedDescription)")
            return
        }
        self.process = process
        self.input = stdin.fileHandleForWriting
    }

    /// Types an answer to the waiting tool. The text is written to the tool's terminal and
    /// not kept anywhere.
    func send(_ answer: String) {
        guard isRunning, let input else { return }
        prompt = nil
        generation += 1
        try? input.write(contentsOf: Data((answer + "\n").utf8))
    }

    /// Stops setup so the engine rolls back what it staged. A tool waiting for an answer is
    /// told there is none (end of input), which it reports as an ordinary failure; interrupting
    /// it there would leave the engine unsure whether it stopped. Anything else gets Control-C,
    /// and so does a second request.
    func cancel() {
        guard isRunning, let process else { return }
        let line = text.current.trimmingCharacters(in: .whitespaces)
        let asking = prompt != nil || (!line.isEmpty && !line.hasPrefix("> "))
        prompt = nil
        if asking, !cancelRequested, let input {
            cancelRequested = true
            try? input.write(contentsOf: Data([0x04]))
        } else {
            cancelRequested = true
            process.interrupt()
        }
    }

    private func received(_ data: Data) {
        text.feed(data)
        for line in text.lines.suffix(12) {
            if let match = line.range(of: #"^\[(\d)/5\] "#, options: .regularExpression),
               let number = Int(line[match].dropFirst().prefix(1)) {
                phase = max(phase, number)
            }
        }
        prompt = nil
        generation += 1
        let seen = generation
        // A tool that has stopped mid-line is asking for something.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.generation == seen, self.isRunning else { return }
            self.waiting()
        }
    }

    private func waiting() {
        let line = text.current.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("> ") else { return }
        // The two questions the app has already answered by letting the user pick an app.
        if line.contains("installed .app path") || line.hasPrefix("Installed .app path"), !answeredApp {
            answeredApp = true
            send(app.path)
        } else if line.contains("Matching App Store link or IPA"), !answeredLink {
            answeredLink = true
            send(app.storeLink)
        } else if line.lowercased().hasPrefix("enter password"), let password = heldPassword {
            heldPassword = nil
            asked.append(line)
            send(password)
        } else if !echo || [":", "?", ">"].contains(where: line.hasSuffix) {
            asked.append(line)
            prompt = line
        }
    }

    private func finished(code: Int32, rest: Data) {
        if !rest.isEmpty { text.feed(rest) }
        prompt = nil
        heldPassword = nil
        input = nil
        process = nil
        if code == 0 {
            phase = SetupSession.phases.count + 1
            state = .passed
        } else if cancelRequested {
            state = .cancelled
        } else {
            let stopped = text.lines.last { $0.hasPrefix("Stopped: ") }.map { String($0.dropFirst(9)) }
            state = .failed(stopped ?? "Setup stopped with exit code \(code).")
        }
        onFinish?()
        onFinish = nil
    }
}
