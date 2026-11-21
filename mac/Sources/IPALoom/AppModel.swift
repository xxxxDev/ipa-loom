import AppKit
import Foundation

enum Page: String, CaseIterable, Identifiable {
    case decrypt = "Decrypt", library = "Library", activity = "Activity", health = "Setup & Health"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .decrypt: return "lock.open"
        case .library: return "square.grid.2x2"
        case .activity: return "clock"
        case .health: return "stethoscope"
        }
    }
}

enum StepState { case waiting, running, done, failed }

struct StepItem: Identifiable {
    var title: String
    var state: StepState
    var id: String { title }
}

/// One decryption started from the app: the engine process and what it has recorded so far.
@MainActor
final class RunSession: ObservableObject {
    enum State: Equatable { case running, passed, failed(String), cancelled }

    let target: String
    let kind: TargetKind
    @Published var state: State = .running
    @Published var record: RunRecord?
    @Published var log: [String] = []

    private var process: Process?
    private var known: Set<String> = []
    private var timer: Timer?
    private var cancelRequested = false
    private var onFinish: (() -> Void)?

    init(target: String) {
        self.target = target
        self.kind = TargetKind.guess(target)
    }

    var isRunning: Bool { state == .running }

    var title: String {
        if let record, record.app != nil { return record.displayName }
        if kind == .store { return "App Store app" }
        return URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
    }

    func start(suffix: String?, onFinish: @escaping () -> Void) {
        var arguments = [target]
        // Only an App Store download has an encrypted original the user does not already hold.
        if kind == .store { arguments.append("--keep-encrypted") }
        if let suffix, !suffix.isEmpty { arguments += ["--suffix", suffix] }
        guard let process = Engine.process(arguments) else {
            state = .failed("The engine is missing from this app.")
            return
        }
        self.onFinish = onFinish
        known = Store.recordIDs()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor in self?.append(text) }
        }
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in
                output.fileHandleForReading.readabilityHandler = nil
                self?.finish(code: code)
            }
        }
        do { try process.run() } catch {
            state = .failed("The engine could not be started: \(error.localizedDescription)")
            return
        }
        self.process = process
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    /// Asks the engine to stop the way Control-C does; it cleans up its own run.
    func cancel() {
        guard isRunning, let process, process.isRunning else { return }
        cancelRequested = true
        process.interrupt()
    }

    private static func isProgress(_ line: String) -> Bool {
        line.range(of: #"^\S+\s+\d{1,3}%"#, options: .regularExpression) != nil
    }

    private func append(_ text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }
            // A progress line the tool redraws in place replaces its earlier reading.
            if let last = log.last, RunSession.isProgress(clean), RunSession.isProgress(last),
               clean.prefix(while: { $0 != " " }) == last.prefix(while: { $0 != " " }) {
                log[log.count - 1] = clean
            } else {
                log.append(clean)
            }
        }
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    /// The engine writes its record as it goes; the newest one that was not there before
    /// this run started is this run's.
    private func poll() {
        if record == nil {
            guard let id = Store.recordIDs().subtracting(known).first else { return }
            record = Store.record(id)
        } else if let id = record?.id, let fresh = Store.record(id), fresh != record {
            record = fresh
        }
    }

    private func finish(code: Int32) {
        timer?.invalidate()
        timer = nil
        poll()
        if code == 0 {
            state = .passed
        } else if cancelRequested {
            state = .cancelled
        } else {
            let stopped = log.last { $0.hasPrefix("Stopped: ") }.map { String($0.dropFirst(9)) }
            state = .failed(stopped ?? "The engine stopped with exit code \(code).")
        }
        onFinish?()
    }

    var steps: [StepItem] {
        let recorded = record?.steps ?? []
        func stage(_ name: String) -> StepState {
            guard let step = recorded.first(where: { $0.stage == name }) else { return .waiting }
            guard step.ended != nil else { return isRunning ? .running : .failed }
            return step.exitCode == 0 ? .done : .failed
        }
        let effectiveKind = record?.inputKind.flatMap(TargetKind.init(rawValue:)) ?? kind
        var items: [StepItem] = []
        switch effectiveKind {
        case .store:
            items.append(StepItem(title: "Check your App Store session", state: stage("session-check")))
            items.append(StepItem(title: "Download the encrypted IPA", state: stage("download")))
        case .file, .installedApp:
            let title = effectiveKind == .file ? "Read the IPA" : "Package the installed app"
            let state: StepState = record?.app != nil ? .done : (isRunning ? .running : .failed)
            items.append(StepItem(title: title, state: state))
        }
        let decrypt = stage("decrypt")
        items.append(StepItem(title: "Decrypt with your model", state: decrypt))
        var verify: StepState = .waiting
        if record?.verification != nil { verify = .done }
        else if decrypt == .done { verify = isRunning ? .running : .failed }
        items.append(StepItem(title: "Verify the decrypted app", state: verify))
        items.append(StepItem(title: "Save to Library", state: state == .passed ? .done : .waiting))
        return items
    }

    var progress: Double {
        let all = steps
        return Double(all.filter { $0.state == .done }.count) / Double(max(all.count, 1))
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var page: Page = .decrypt
    @Published var health: Health = .checking
    @Published var healthDetail = ""
    @Published var records: [RunRecord] = []
    @Published var session: RunSession?
    @Published var setup: SetupSession?
    @Published var installedApps: [InstalledApp] = []
    let updater = Updater()
    /// Sample data for the layout pictures a debug build draws; never set in the real app.
    var sampleFiles = false

    var libraryRecords: [RunRecord] {
        records.filter { $0.passed && $0.app != nil && output(of: $0) != nil }
    }

    func output(of record: RunRecord) -> StoredFile? {
        if sampleFiles, let name = record.outputFilename {
            return StoredFile(url: URL(fileURLWithPath: "/sample/" + name), size: 64_500_000)
        }
        return Store.output(of: record)
    }

    func encrypted(of record: RunRecord) -> StoredFile? {
        if sampleFiles { return nil }
        return Store.encrypted(of: record)
    }

    func boot() {
        refresh()
        Task {
            await checkHealth()
            // A Mac that was never set up opens on setup: nothing else works before it.
            if health == .setupRequired, session == nil { page = .health }
        }
        updater.busy = { [weak self] in self?.session?.isRunning == true || self?.setup?.isRunning == true }
        updater.schedule()
    }

    func refresh() {
        records = Store.records()
    }

    func checkHealth() async {
        health = .checking
        guard Paths.engineRoot != nil else { health = .engineMissing; return }
        guard await Engine.developerToolsInstalled() else { health = .toolsMissing; return }
        guard let result = await Engine.capture(["--doctor"]) else { health = .engineMissing; return }
        let lines = result.output.split(whereSeparator: \.isNewline).map(String.init)
        healthDetail = lines.joined(separator: "\n")
        if result.code == 0 {
            health = .ready
        } else if lines.first?.hasPrefix("Pending setup") == true {
            health = .pendingSetup
        } else if lines.first == "Setup required" {
            health = .setupRequired
        } else {
            let message = lines.first { $0.hasPrefix("Stopped: ") }.map { String($0.dropFirst(9)) } ?? lines.first
            health = .problem(message ?? "The check stopped with exit code \(result.code).")
        }
    }

    func start(target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, session?.isRunning != true else { return }
        let run = RunSession(target: trimmed)
        session = run
        page = .decrypt
        run.start(suffix: nil) { [weak self] in
            self?.refresh()
            Task { await self?.checkHealth() }
        }
    }

    func reveal(_ file: StoredFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func showDataFolder() {
        NSWorkspace.shared.open(Paths.dataRoot)
    }

    /// Rolls back a setup that was interrupted before it finished.
    func recoverSetup() async {
        health = .checking
        let result = await Engine.capture(["--recover"])
        await checkHealth()
        if let result, result.code != 0, case .problem = health {
            let lines = result.output.split(whereSeparator: \.isNewline).map(String.init)
            if let stopped = lines.last(where: { $0.hasPrefix("Stopped: ") }) { health = .problem(String(stopped.dropFirst(9))) }
        }
    }

    func findInstalledApps() {
        if sampleFiles { return }
        installedApps = InstalledApps.discover()
    }

    /// Starts first setup with the app the user picked to build the model from.
    func startSetup(with app: InstalledApp) {
        guard setup?.isRunning != true, session?.isRunning != true else { return }
        let run = SetupSession(app: app)
        setup = run
        run.start { [weak self] in
            self?.refresh()
            Task { await self?.checkHealth() }
        }
    }

    /// The same setup in Terminal, for anyone who prefers it there.
    func openTerminalSetup() {
        guard let command = Paths.engineRoot?.appendingPathComponent("ipa-loom.command") else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([command], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
