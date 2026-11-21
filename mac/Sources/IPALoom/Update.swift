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
}

enum UpdateCheck {
    /// The newest published release newer than `current` in GitHub's list of releases for
    /// `repo`. Drafts, pre-releases and tags that are not plain versions never count, and
    /// only a page under `https://github.com/<repo>/releases/` is taken.
    static func newest(in json: Data, current: String, repo: String) -> AvailableUpdate? {
        guard let now = ReleaseVersion(current),
              let releases = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return nil }
        var best: (ReleaseVersion, URL)?
        for release in releases {
            guard release["draft"] as? Bool == false, release["prerelease"] as? Bool == false,
                  let tag = release["tag_name"] as? String, let version = ReleaseVersion(tag), version > now,
                  let address = release["html_url"] as? String, let page = URL(string: address),
                  address.hasPrefix("https://github.com/\(repo)/releases/") else { continue }
            if best == nil || version > best!.0 { best = (version, page) }
        }
        return best.map { AvailableUpdate(version: $0.0.description, page: $0.1) }
    }

    static func address(repo: String) -> URL? {
        let parts = repo.split(separator: "/")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/releases?per_page=20")
    }
}

/// Looks for a newer release on GitHub and says so. It never downloads or installs anything:
/// the user updates with Homebrew or from the release page.
///
/// The only thing sent is one request for the public list of releases; it carries no
/// account, model or app data. The automatic check can be switched off.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle, checking, current
        case available(AvailableUpdate)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
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

    #if DEBUG
    /// For the layout pictures a debug build draws.
    func show(_ state: State) { self.state = state }
    #endif

    var canCheck: Bool { version != nil && repo.flatMap(UpdateCheck.address) != nil }

    var available: AvailableUpdate? {
        if case .available(let update) = state { return update }
        return nil
    }

    /// Checks once a day while the setting is on, the first time a minute after launch.
    func schedule() {
        guard canCheck, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.tick()
        }
    }

    private func tick() {
        guard automatic, state != .checking else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 3600 else { return }
        Task { await check(quiet: true) }
    }

    /// `quiet`: an automatic check keeps a failure to itself and leaves the last result up.
    func check(quiet: Bool = false) async {
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
