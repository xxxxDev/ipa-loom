import Foundation

/// Where the engine and its private data live.
enum Paths {
    /// The engine's private data folder: the same one the terminal command uses.
    static let dataRoot: URL = {
        if let raw = ProcessInfo.processInfo.environment["IPA_LOOM_DATA_HOME"], raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/IPA Loom")
    }()
    static var records: URL { dataRoot.appendingPathComponent("records") }
    static var runs: URL { dataRoot.appendingPathComponent(".runtime/runs") }

    /// The folder that holds `scripts/entry.py`: the copy inside the app, or the source
    /// checkout when a debug build runs straight from it.
    static let engineRoot: URL? = {
        func holdsEngine(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.appendingPathComponent("scripts/entry.py").path)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("engine"), holdsEngine(bundled) {
            return bundled
        }
        #if DEBUG
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
            if holdsEngine(url) { return url }
        }
        #endif
        return nil
    }()
}

struct AppIdentity: Decodable, Equatable {
    var bundleID: String
    var version: String
    var build: String
    enum CodingKeys: String, CodingKey {
        case bundleID = "CFBundleIdentifier", version = "CFBundleShortVersionString", build = "CFBundleVersion"
    }
}

struct RunStep: Decodable, Equatable {
    var stage: String
    var ended: String?
    var exitCode: Int?
    enum CodingKeys: String, CodingKey { case stage, ended, exitCode = "exit_code" }
}

struct Verification: Decodable, Equatable {
    var plaintextVerified: Bool?
    enum CodingKeys: String, CodingKey { case plaintextVerified = "plaintext_verified" }
}

/// One run, as the engine records it in `records/<id>.json`.
struct RunRecord: Decodable, Identifiable, Equatable {
    var id: String
    var status: String
    var started: String?
    var ended: String?
    var inputKind: String?
    var app: AppIdentity?
    var outputFilename: String?
    var verification: Verification?
    var steps: [RunStep]?
    var failureType: String?

    enum CodingKeys: String, CodingKey {
        case id, status, started, ended, app, verification, steps
        case inputKind = "input_kind", outputFilename = "output_filename", failureType = "failure_type"
    }

    var passed: Bool { status == "passed" }
    var verified: Bool { passed && verification?.plaintextVerified == true }

    /// The app's name: the output file is named `Name_Version_label.ipa`.
    var displayName: String {
        if let file = outputFilename, let version = app?.version,
           let cut = file.range(of: "_" + version + "_", options: .backwards) {
            return String(file[file.startIndex..<cut.lowerBound])
        }
        return app?.bundleID ?? (inputKind == "login" ? "Apple sign-in" : "Unknown app")
    }

    var startedDate: Date? { started.flatMap(RunRecord.parse) }
    var endedDate: Date? { ended.flatMap(RunRecord.parse) }

    private static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    var kindLabel: String {
        switch inputKind {
        case "store": return "App Store"
        case "file": return "Local IPA"
        case "installed-app": return "Installed app"
        case "login": return "Sign-in"
        default: return "Run"
        }
    }
}

struct StoredFile: Equatable {
    var url: URL
    var size: Int64
    var name: String { url.lastPathComponent }
}

/// Read-only access to what the engine has written. The app never writes there.
enum Store {
    static func recordIDs() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.records.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
    }

    static func record(_ id: String) -> RunRecord? {
        guard let data = try? Data(contentsOf: Paths.records.appendingPathComponent(id + ".json")) else { return nil }
        return try? JSONDecoder().decode(RunRecord.self, from: data)
    }

    /// Every run, newest first.
    static func records() -> [RunRecord] {
        recordIDs().compactMap(record).sorted { ($0.started ?? "") > ($1.started ?? "") }
    }

    static func output(of record: RunRecord) -> StoredFile? {
        guard let name = record.outputFilename else { return nil }
        return file(Paths.runs.appendingPathComponent(record.id).appendingPathComponent("output").appendingPathComponent(name))
    }

    /// The still-encrypted IPA the run started from, when the engine kept one.
    static func encrypted(of record: RunRecord) -> StoredFile? {
        let folder = Paths.runs.appendingPathComponent(record.id).appendingPathComponent("encrypted")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let name = names.first(where: { $0.hasSuffix(".ipa") }) else { return nil }
        return file(folder.appendingPathComponent(name))
    }

    private static func file(_ url: URL) -> StoredFile? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true else { return nil }
        return StoredFile(url: url, size: Int64(values.fileSize ?? 0))
    }
}

/// Starting the engine. The app passes a target and reads the result. First setup, which
/// asks questions, goes through `SetupSession` instead.
enum Engine {
    static func process(_ arguments: [String]) -> Process? {
        guard let root = Paths.engineRoot else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-B", root.appendingPathComponent("scripts/entry.py").path] + arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        return process
    }

    /// Runs a short engine command and returns its exit code and combined output.
    static func capture(_ arguments: [String]) async -> (code: Int32, output: String)? {
        guard let process = process(arguments) else { return nil }
        return await run(process)
    }

    static func run(_ process: Process) async -> (code: Int32, output: String)? {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do { try process.run() } catch { continuation.resume(returning: nil); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Apple's developer tools supply python3 and the Swift compiler the engine needs.
    /// `xcode-select -p` answers without opening the system's install window.
    static func developerToolsInstalled() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardInput = FileHandle.nullDevice
        return await run(process)?.code == 0
    }
}

enum Health: Equatable {
    case checking
    case ready
    case setupRequired
    /// A setup was interrupted and left staged files to clean up.
    case pendingSetup
    case toolsMissing
    case engineMissing
    case problem(String)
}

enum TargetKind: String {
    case store, file, installedApp = "installed-app"

    static func guess(_ target: String) -> TargetKind {
        let lower = target.lowercased()
        if lower.hasSuffix(".app") || lower.hasSuffix(".app/") { return .installedApp }
        if lower.hasPrefix("http") || target.allSatisfy(\.isNumber) { return .store }
        return .file
    }
}
