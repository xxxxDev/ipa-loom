import AppKit
import Foundation

/// A release version as IPA Loom's tags write it: `2026.11.13` or `v2026.11.13`.
struct ReleaseVersion: Comparable, CustomStringConvertible {
    let numbers: [Int]

    init?(_ text: String) {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("v") || s.hasPrefix("V") { s = s.dropFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { part in
            part.allSatisfy(\.isNumber) && part.count <= 9 ? Int(part) : nil
        }
        guard (1...4).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        numbers = parts.map { $0! }
    }

    var description: String { numbers.map(String.init).joined(separator: ".") }

    static func < (a: Self, b: Self) -> Bool {
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0, y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: Self, b: Self) -> Bool { !(a < b) && !(b < a) }
}

/// A published release newer than this app.
struct AvailableUpdate: Equatable {
    let version: String
    let page: URL
    /// The release's disk image for this app, when it has one the app can check.
    var image: Image?

    struct Image: Equatable {
        let name: String
        let url: URL
        /// The image's SHA-256 as GitHub records it for the uploaded file, in lowercase hex.
        let sha256: String
    }
}

enum UpdateCheck {
    /// The newest published release newer than `current` in GitHub's list of releases for
    /// `repo`. Drafts, pre-releases and tags that are not plain versions never count, and
    /// only a page under `https://github.com/<repo>/releases/` is taken.
    static func newest(in json: Data, current: String, repo: String) -> AvailableUpdate? {
        guard let now = ReleaseVersion(current),
              let releases = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return nil }
        var best: (ReleaseVersion, URL, AvailableUpdate.Image?)?
        for release in releases {
            guard release["draft"] as? Bool == false, release["prerelease"] as? Bool == false,
                  let tag = release["tag_name"] as? String, let version = ReleaseVersion(tag), version > now,
                  let address = release["html_url"] as? String, let page = URL(string: address),
                  address.hasPrefix("https://github.com/\(repo)/releases/") else { continue }
            if best == nil || version > best!.0 { best = (version, page, image(in: release, version: version, repo: repo)) }
        }
        return best.map { AvailableUpdate(version: $0.0.description, page: $0.1, image: $0.2) }
    }

    /// The release's `IPA-Loom-<version>-arm64.dmg`, only from
    /// `https://github.com/<repo>/releases/download/` and only with GitHub's SHA-256 for it.
    private static func image(in release: [String: Any], version: ReleaseVersion, repo: String) -> AvailableUpdate.Image? {
        let name = "IPA-Loom-\(version)-arm64.dmg"
        guard let assets = release["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == name }),
              let link = asset["browser_download_url"] as? String, let url = URL(string: link),
              url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/\(repo)/releases/download/"),
              let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst(7)).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return AvailableUpdate.Image(name: name, url: url, sha256: hex)
    }

    static func address(repo: String) -> URL? {
        let parts = repo.split(separator: "/")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/releases?per_page=20")
    }
}

/// Looks for a newer release on GitHub and says so. Checking sends one request for the
/// public list of releases; it carries no account, model or app data, and the automatic
/// check can be switched off. Nothing is downloaded until the user chooses Install
/// (UpdateInstall.swift).
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle, checking, current
        case available(AvailableUpdate)
        /// Installing `update`: what it is doing now.
        case working(AvailableUpdate, String)
        case failed(String)
    }

    @Published var state: State = .idle
    /// Whether a decryption or setup is running; an update waits for it.
    var busy: () -> Bool = { false }
    @Published var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Self.automaticKey) }
    }

    private static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastKey = "lastUpdateCheck"
    private var timer: Timer?

    /// The version and repository the app was built with; a build run outside an app
    /// bundle has neither and does not check.
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let repo = Bundle.main.object(forInfoDictionaryKey: "IPALoomRepository") as? String

    init() {
        automatic = UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    var canCheck: Bool { version != nil && repo.flatMap(UpdateCheck.address) != nil }

    /// Whether an install has swapped the new app in and is quitting to open it.
    var restarting = false

    var available: AvailableUpdate? {
        switch state {
        case .available(let update), .working(let update, _): return update
        default: return nil
        }
    }

    /// Checks once a day while the setting is on, the first time a minute after launch.
    func schedule() {
        guard canCheck, timer == nil else { return }
        clearLeftovers()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.tick()
        }
    }

    private func tick() {
        guard automatic, state == .idle || state == .current else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 3600 else { return }
        Task { await check(quiet: true) }
    }

    /// `quiet`: an automatic check keeps a failure to itself and leaves the last result up.
    func check(quiet: Bool = false) async {
        if case .working = state { return }
        guard let version, let repo, let address = UpdateCheck.address(repo: repo), state != .checking else { return }
        let before = state
        state = .checking
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4_000_000 else {
                throw URLError(.badServerResponse)
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastKey)
            state = UpdateCheck.newest(in: data, current: version, repo: repo).map(State.available) ?? .current
        } catch {
            state = quiet ? before : .failed("GitHub could not be reached. Try again later.")
        }
    }

    func openPage() {
        if let update = available { NSWorkspace.shared.open(update.page) }
    }
}
