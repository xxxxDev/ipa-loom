#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `IPA_LOOM_APP_SNAPSHOT=folder` draws each page to a PNG file with
/// sample data, without starting the engine or reading the private data folder, then quits.
/// The pictures show the layout but not the glass, which the window server adds.
/// With `IPA_LOOM_APP_SNAPSHOT_LIVE=1` it reads this Mac's real setup and records instead
/// of the samples (still without starting a run), to check the app against real data.
@MainActor
enum Snapshot {
    static func run(_ model: AppModel, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        GlassLook.plain = true
        let live = ProcessInfo.processInfo.environment["IPA_LOOM_APP_SNAPSHOT_LIVE"] == "1"
        model.sampleFiles = !live
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-900))
        let sample = Data("""
            [{"id":"a1","status":"passed","started":"\(stamp)","ended":"\(stamp)","input_kind":"store",
              "app":{"CFBundleIdentifier":"com.example.notes","CFBundleShortVersionString":"4.3.3","CFBundleVersion":"1"},
              "output_filename":"Notes Pro_4.3.3_loom.ipa","verification":{"plaintext_verified":true}},
             {"id":"a2","status":"passed","started":"\(stamp)","ended":"\(stamp)","input_kind":"installed-app",
              "app":{"CFBundleIdentifier":"com.example.beta","CFBundleShortVersionString":"0.9","CFBundleVersion":"7"},
              "output_filename":"Beta Tracker_0.9_loom.ipa","verification":{"plaintext_verified":true}},
             {"id":"a3","status":"failed","started":"\(stamp)","input_kind":"file",
              "app":{"CFBundleIdentifier":"com.example.weather","CFBundleShortVersionString":"2.1.0","CFBundleVersion":"3"}}]
            """.utf8)
        let records = (try? JSONDecoder().decode([RunRecord].self, from: sample)) ?? []

        let running = RunSession(target: "https://apps.apple.com/app/id123456789")
        running.record = try? JSONDecoder().decode(RunRecord.self, from: Data("""
            {"id":"b1","status":"running","input_kind":"store",
             "app":{"CFBundleIdentifier":"com.example.weather","CFBundleShortVersionString":"2.1.0","CFBundleVersion":"3"},
             "output_filename":"Weather Lens_2.1.0_loom.ipa",
             "steps":[{"stage":"session-check","ended":"x","exit_code":0},{"stage":"download","ended":"x","exit_code":0},{"stage":"decrypt"}]}
            """.utf8))
        running.log = ["Checking your App Store session done", "Downloading the app", "Decrypting the app (working)"]

        let samples = [InstalledApp(path: "/Applications/Notes Pro.app", name: "Notes Pro", version: "4.3.3", itemID: 1),
                       InstalledApp(path: "/Applications/Weather Lens.app", name: "Weather Lens", version: "2.1.0", itemID: 2)]
        let asking = SetupSession(app: samples[0])
        asking.phase = 3
        asking.text.feed(Data("[3/5] Sign in to Apple\n  Signing in to the App Store\n".utf8))
        asking.prompt = "enter Apple ID (email address):"
        let admin = SetupSession(app: samples[0])
        admin.phase = 4
        admin.prompt = "Password:"
        admin.echo = false
        let done = SetupSession(app: samples[0])
        done.phase = 6
        done.state = .passed

        let shots: [(String, Page, Health, RunSession?)] = [
            ("decrypt", .decrypt, .ready, nil),
            ("decrypt-running", .decrypt, .ready, running),
            ("decrypt-setup", .decrypt, .setupRequired, nil),
            ("library", .library, .ready, nil),
            ("activity", .activity, .ready, nil),
            ("health-ready", .health, .ready, nil),
            ("health-setup", .health, .setupRequired, nil),
            ("health-setup-no-app", .health, .setupRequired, nil),
            ("health-setup-asking", .health, .setupRequired, nil),
            ("health-setup-admin", .health, .setupRequired, nil),
            ("health-setup-done", .health, .ready, nil),
            ("health-update", .health, .ready, nil),
        ]
        Task { @MainActor in
            if live {
                model.refresh()
                await model.checkHealth()
            }
            for (name, page, health, session) in shots {
                if live {
                    if session != nil || health != .ready { continue }
                } else {
                    model.records = records
                    model.health = health
                }
                model.installedApps = name == "health-setup-no-app" ? [] : samples
                model.setup = name == "health-setup-asking" ? asking : name == "health-setup-admin" ? admin : name == "health-setup-done" ? done : nil
                model.updater.state = (name == "health-update" ? .available(AvailableUpdate(version: "2026.12.1", page: URL(string: "https://github.com/xxxxDev/ipa-loom/releases/tag/v2026.12.1")!)) : .idle)
                model.page = page
                model.session = session
                let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: 0), size: RootView.size),
                                      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: RootView().environmentObject(model).tint(Palette.blue))
                window.orderFront(nil)
                try? await Task.sleep(for: .milliseconds(600))
                let view = window.contentView!
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
                }
                window.close()
            }
            exit(0)
        }
    }
}
#endif
