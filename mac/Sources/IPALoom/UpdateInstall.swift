import AppKit
import CryptoKit
import Foundation
import Security

/// Installs a newer release in place of this app.
///
/// An update is installed only if every check passes: the disk image matches the SHA-256
/// GitHub records for it, and the app inside satisfies this app's own designated
/// requirement (the same identifier, signed with the same certificate) and says it is the
/// version offered. An app built without a certificate (ad hoc) has no such requirement
/// to share, so it does not update itself. The new app and the old one change places in
/// one step, so there is never a moment without an app; IPA Loom then quits, and a small
/// script removes the old copy and opens the new one. Only the app is replaced: the
/// private data folder is not touched.
extension Updater {
    struct Failure: Error { let text: String; init(_ text: String) { self.text = text } }

    /// Why this copy cannot update itself, if it cannot.
    var cannotInstall: String? {
        guard canCheck else { return "This copy was not built as an app." }
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return "This copy was not built as an app." }
        guard let requirement = Self.ownRequirement(), Self.namesCertificate(requirement) else {
            return "This build is signed ad hoc, so it cannot check that an update comes from the same signer."
        }
        if bundle.path.contains("/AppTranslocation/") {
            return "Move IPA Loom to Applications first: macOS is running it from a temporary place."
        }
        if let why = Self.unsafePlace(bundle, staging: Self.cachesFolder) {
            return "IPA Loom cannot replace itself where it is (\(why)). Move it to Applications, or update with Homebrew or from the release page."
        }
        return nil
    }

    /// `url` with symbolic links resolved: the path the checks, the exchange and the reopen all use.
    /// (realpath, which keeps /private where Foundation's own resolving drops it.)
    nonisolated static func resolved(_ url: URL) -> URL {
        guard let real = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    /// Why an app in `folder` cannot safely be replaced by this user, or nil. The folder and
    /// every folder above it must belong to this user or to root, and nobody else may write
    /// to them (the admin group may, as it may in /Applications): otherwise another account
    /// could rename or replace what is there while the update puts the new app in.
    nonisolated static func unsafeFolder(_ folder: URL) -> String? {
        var path = resolved(folder).path
        guard access(path, W_OK) == 0 else { return "this account cannot write to \(path)" }
        while true {
            var info = stat()
            guard lstat(path, &info) == 0 else { return "\(path) cannot be read" }
            guard info.st_mode & S_IFMT == S_IFDIR else { return "\(path) is not a folder" }
            guard info.st_uid == getuid() || info.st_uid == 0 else { return "\(path) belongs to another account" }
            if info.st_mode & S_IWOTH != 0 { return "every account can write to \(path)" }
            if info.st_mode & S_IWGRP != 0, info.st_gid != 80 { return "a group other than admin can write to \(path)" }
            if path == "/" { return nil }
            path = (path as NSString).deletingLastPathComponent
            if path.isEmpty { path = "/" }
        }
    }

    /// Why the app at `app` cannot safely change places with a copy staged under `staging`,
    /// or nil. The app must be this user's own folder, in a folder that is safe
    /// (`unsafeFolder`), on the same volume as `staging`: the exchange cannot cross volumes.
    nonisolated static func unsafePlace(_ app: URL, staging: URL) -> String? {
        let path = resolved(app).path
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return "\(path) is not a folder" }
        guard info.st_uid == getuid() else { return "\(path) belongs to another account" }
        if let why = unsafeFolder(resolved(app).deletingLastPathComponent()) { return why }
        var here = stat(), there = stat()
        guard lstat((path as NSString).deletingLastPathComponent, &here) == 0, stat(staging.path, &there) == 0 else {
            return "\(staging.path) cannot be read"
        }
        guard here.st_dev == there.st_dev else { return "it is on another disk than your home folder" }
        return nil
    }

    private static var cachesFolder: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }

    private static var updatesFolder: URL {
        cachesFolder.appendingPathComponent("io.ipaloom.app", isDirectory: true).appendingPathComponent("updates", isDirectory: true)
    }

    /// Removes what an earlier install left behind: its download, and its disk image if it
    /// is still open. Anything from the last hour is left alone, in case another copy of
    /// the app is installing right now.
    nonisolated static func clearLeftovers(in folder: URL) async {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in items {
            let changed = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(changed) > 3600 else { continue }
            try? await run("/usr/bin/hdiutil", ["detach", "-force", item.appendingPathComponent("mount").path])
            try? fm.removeItem(at: item)
        }
    }

    func clearLeftovers() {
        let folder = Self.updatesFolder
        Task.detached { await Self.clearLeftovers(in: folder) }
    }

    /// Downloads, checks and stages the update, then quits so the script can swap it in.
    func install() async {
        guard case .available(let update) = state else { return }
        if busy() { state = .failed("A decryption or setup is running. Install the update when it has finished."); return }
        if let reason = cannotInstall { state = .failed(reason); return }
        guard let wanted = update.image, let requirement = Self.ownRequirement() else {
            state = .failed("This release has no disk image the app can check. Update with Homebrew or from the release page.")
            return
        }
        let fm = FileManager.default
        // The path the checks looked at is the one exchanged and opened.
        let dest = Self.resolved(Bundle.main.bundleURL)
        // Staged in this user's own folder (0700), not next to the app: nobody else can put
        // anything at that path before the copy, or change it after the check.
        // Each install has a folder of its own, so two copies of the app never share one.
        let dir = Self.updatesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staged = dir.appendingPathComponent("new", isDirectory: true).appendingPathComponent(dest.lastPathComponent, isDirectory: true)
        func step(_ text: String) { state = .working(update, text) }
        step("Starting…")
        do {
            try Self.ownDirectory(dir.deletingLastPathComponent().deletingLastPathComponent())
            try Self.ownDirectory(dir.deletingLastPathComponent())
            try Self.ownDirectory(dir)
            try Self.ownDirectory(staged.deletingLastPathComponent())

            let image = dir.appendingPathComponent("update.dmg")
            step("Downloading \(wanted.name)…")
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            let (file, response) = try await session.download(from: wanted.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Failure("the download answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            try fm.moveItem(at: file, to: image)

            step("Checking the download…")
            let digest = try await Task.detached { try Self.sha256(of: image) }.value
            guard digest == wanted.sha256 else { throw Failure("the download does not match the SHA-256 GitHub records for it") }

            step("Opening the disk image…")
            let mount = dir.appendingPathComponent("mount", isDirectory: true)
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try await Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, image.path])
            let source = mount.appendingPathComponent("IPA Loom.app", isDirectory: true)
            let values = try? source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            let copied: Result<Void, Error>
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                step("Checking the new version…")
                do { try await Self.run("/usr/bin/ditto", ["--noacl", source.path, staged.path]); copied = .success(()) } catch { copied = .failure(error) }
            } else {
                copied = .failure(Failure("the disk image holds no IPA Loom.app"))
            }
            // The image is no longer needed, whatever happened.
            try? await Self.run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            try copied.get()
            // The signature covers the contents, not who may write them: the copy is made
            // this user's alone before it is checked.
            try Self.tighten(staged)
            // The copy, not the image, is what will run: it is the one checked.
            guard Self.satisfies(staged, requirement) else { throw Failure("the new app is not signed by the same signer as this one") }
            // Read from the file: Bundle keeps what it read at a path the first time.
            let plist = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))
            let found = plist?["CFBundleShortVersionString"] as? String
            guard found == update.version else { throw Failure("the new app says it is \(found ?? "no version"), not \(update.version)") }
            // A run may have started while the download was going.
            guard !busy() else { throw Failure("a decryption or setup started meanwhile; install it when that has finished") }

            step("Restarting into IPA Loom \(update.version)…")
            let script = dir.appendingPathComponent("finish.sh")
            try Self.finishScript.write(to: script, atomically: true, encoding: .utf8)
            // Looked at again now: the folders could have changed while the download ran.
            if let why = Self.unsafePlace(dest, staging: dir) { throw Failure("IPA Loom cannot replace itself where it is (\(why))") }
            // The new app and this one change places in one step: the path always holds a
            // whole app, and it works only within one volume. From here the old app (this
            // one, still running) is the copy in the staging folder.
            guard renamex_np(staged.path, dest.path, UInt32(RENAME_SWAP)) == 0 else {
                throw Failure("the new app could not take this one's place (\(String(cString: strerror(errno))))")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), dir.path, dest.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch {
                // Nothing will reopen the app: put this one back and say so.
                _ = renamex_np(staged.path, dest.path, UInt32(RENAME_SWAP))
                throw error
            }
            // Quit from the run loop, not from inside this task, which the app's own
            // quit handling would otherwise wait on.
            restarting = true
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        } catch {
            try? await Self.run("/usr/bin/hdiutil", ["detach", "-force", dir.appendingPathComponent("mount").path])
            try? fm.removeItem(at: dir)
            state = .failed("Update not installed: \((error as? Failure)?.text ?? error.localizedDescription).")
        }
    }

    /// Waits for IPA Loom to quit, removes the install's folder (the old app is in it) and
    /// opens the new app. The paths come as arguments, never inside the script. If the
    /// app does not quit, the folder stays for a later launch to clear.
    private static let finishScript = """
    #!/bin/sh
    pid=$1; dir=$2; dest=$3
    i=0
    while kill -0 "$pid" 2>/dev/null; do i=$((i+1)); [ "$i" -gt 6000 ] && exit 1; sleep 0.1; done
    cd / && rm -rf "$dir"
    open "$dest"
    """

    /// A directory of this user's own that nobody else can read or write.
    nonisolated static func ownDirectory(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
            guard lstat(url.path, &info) == 0 else { throw Failure("could not make \(url.path)") }
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { throw Failure("\(url.path) is not this user's own folder") }
        if info.st_mode & 0o777 != 0o700, chmod(url.path, 0o700) != 0 { throw Failure("could not close \(url.path) to others") }
    }

    /// Every item must be this user's own directory, file or symbolic link; group and others
    /// lose write access, and set-id bits go.
    nonisolated static func tighten(_ root: URL) throws {
        var paths = [root.path]
        if let items = FileManager.default.enumerator(atPath: root.path) {
            while let item = items.nextObject() as? String { paths.append(root.path + "/" + item) }
        }
        let uid = getuid()
        for path in paths {
            var info = stat()
            guard lstat(path, &info) == 0 else { throw Failure("could not read \(path)") }
            let kind = info.st_mode & S_IFMT
            guard kind == S_IFDIR || kind == S_IFREG || kind == S_IFLNK else { throw Failure("the new app holds a special file") }
            guard info.st_uid == uid else { throw Failure("the new app holds a file owned by someone else") }
            if kind != S_IFLNK {
                guard chmod(path, info.st_mode & 0o7777 & ~mode_t(0o6022)) == 0 else { throw Failure("could not set permissions in the new app") }
            }
        }
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 { done.resume() }
                else { done.resume(throwing: Failure("\((tool as NSString).lastPathComponent) failed (\(process.terminationStatus))")) }
            }
            do { try process.run() } catch { done.resume(throwing: error) }
        }
    }

    /// This app's designated requirement: its identifier and the certificate it is signed with.
    nonisolated static func ownRequirement() -> SecRequirement? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// Whether the requirement names a certificate. An ad hoc signature's names only that
    /// one build (its code hash), which no other build can meet.
    nonisolated static func namesCertificate(_ requirement: SecRequirement) -> Bool {
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text = text as String? else { return false }
        return text.contains("certificate") && !text.contains("cdhash")
    }

    /// Whether the app at `url` is validly signed, nested code included, and meets `requirement`.
    nonisolated static func satisfies(_ url: URL, _ requirement: SecRequirement) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }
}
