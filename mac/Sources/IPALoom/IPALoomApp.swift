import AppKit
import SwiftUI

@main
enum IPALoomApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One look: dark, on the grid backdrop.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        #if DEBUG
        if let script = ProcessInfo.processInfo.environment["IPA_LOOM_APP_SETUP_CHECK"] {
            SetupCheck.run(script: script)
            return
        }
        if let file = ProcessInfo.processInfo.environment["IPA_LOOM_APP_UPDATE_CHECK"] {
            // Reads a saved list of releases instead of asking GitHub, prints the answer and quits.
            let current = ProcessInfo.processInfo.environment["IPA_LOOM_APP_UPDATE_CURRENT"] ?? ""
            let data = (try? Data(contentsOf: URL(fileURLWithPath: file))) ?? Data()
            let found = UpdateCheck.newest(in: data, current: current, repo: "xxxxDev/ipa-loom")
            print(found.map { "\($0.version) \($0.page.absoluteString)" } ?? "none")
            exit(0)
        }
        if let image = ProcessInfo.processInfo.environment["IPA_LOOM_APP_UPDATE_INSTALL"] {
            // Installs from a disk image on this Mac instead of a download, with every check
            // a real update gets, and does not open the new app. Prints why if it refuses.
            let env = ProcessInfo.processInfo.environment
            let file = URL(fileURLWithPath: image)
            let update = AvailableUpdate(version: env["IPA_LOOM_APP_UPDATE_VERSION"] ?? "", page: file,
                                         image: .init(name: file.lastPathComponent, url: file,
                                                      sha256: env["IPA_LOOM_APP_UPDATE_SHA256"] ?? ((try? Updater.sha256(of: file)) ?? "")))
            Task { @MainActor in
                await model.updater.install(update, image: file, reopen: false)
                print(model.updater.state)
                exit(1)
            }
            return
        }
        if let folder = ProcessInfo.processInfo.environment["IPA_LOOM_APP_SNAPSHOT"] {
            Snapshot.run(model, to: URL(fileURLWithPath: folder))
            return
        }
        #endif
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = AppDelegate.menu()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: RootView.size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "IPA Loom"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = RootView.minimum
        window.contentView = NSHostingView(rootView: RootView().environmentObject(model).tint(Palette.blue))
        window.center()
        window.setFrameAutosaveName("IPALoomMainWindow")
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        model.boot()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The engine also runs from Terminal: pick up what it wrote while the app was behind.
    func applicationDidBecomeActive(_ notification: Notification) {
        model.refresh()
    }

    /// Quitting during a run stops the engine the way Control-C does and waits for it to
    /// clean up, without blocking the main thread.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let run = model.session, setup = model.setup
        guard run?.isRunning == true || setup?.isRunning == true else { return .terminateNow }
        if let setup, setup.isRunning, !setup.cancelsNow {
            // A sign-in or system tool is working: stopping it now leaves files to clean up by hand.
            let alert = NSAlert()
            alert.messageText = "Setup is in the middle of a step"
            alert.informativeText = "This step cannot be stopped safely. Quitting now can leave setup files that need manual recovery."
            alert.addButton(withTitle: "Keep Running")
            alert.addButton(withTitle: "Quit Anyway")
            if alert.runModal() == .alertFirstButtonReturn {
                if model.updater.restarting {
                    model.updater.restarting = false
                    model.updater.state = .failed("The update is in place. Quit IPA Loom when setup has finished to start using it.")
                }
                return .terminateCancel
            }
            return .terminateNow
        }
        run?.cancel()
        setup?.cancel()
        Task { @MainActor in
            while run?.isRunning == true || setup?.isRunning == true { try? await Task.sleep(for: .milliseconds(100)) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Shows the answer where the rest of the app's state is: Setup & Health.
    @objc func checkForUpdates(_ sender: Any?) {
        model.page = .health
        Task { await model.updater.check() }
    }

    /// The menus a window with a text field needs: the app's own, Edit and Window.
    private static func menu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        add("IPA Loom", [
            item("About IPA Loom", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:)), ""),
            .separator(),
            item("Hide IPA Loom", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Quit IPA Loom", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        add("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return main
    }
}
