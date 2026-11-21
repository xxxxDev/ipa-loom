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
        run?.cancel()
        setup?.cancel()
        Task { @MainActor in
            while run?.isRunning == true || setup?.isRunning == true { try? await Task.sleep(for: .milliseconds(100)) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
