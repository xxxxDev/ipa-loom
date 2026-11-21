import SwiftUI

/// Setup & Health: whether the engine can run, and what to do when it cannot.
struct HealthPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if settingUp {
            // Setup gets the page to itself; the health details come back when it is done.
            SetupFlow()
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.section.weight(.semibold))
                            Text(explanation).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if model.health == .pendingSetup {
                            Button("Clean Up") { Task { await model.recoverSetup() } }.primaryButtonStyle()
                        }
                        Button("Check Again") { Task { await model.checkHealth() } }.secondaryButtonStyle()
                            .disabled(model.health == .checking)
                    }
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 0) {
                    row("Private data folder", Paths.dataRoot.path) {
                        Button("Show") { model.showDataFolder() }.buttonStyle(.link)
                    }
                    Divider()
                    row("Engine", Paths.engineRoot == nil ? "Missing from this app" : "Included in this app") { EmptyView() }
                    Divider()
                    row("Apple developer tools", model.health == .toolsMissing ? "Not installed" : "Installed") { EmptyView() }
                }
                .glassCard(padding: 20)

                UpdateCard(updater: model.updater)

                Text("Tools, your encrypted account state, the private model and every output stay in the private data folder on this Mac. The app only starts the engine and reads its results.")
                    .font(.small).foregroundStyle(Palette.muted).padding(.horizontal, 4)
            }
            .padding(28)
        }
        }
    }

    private var settingUp: Bool { model.health == .setupRequired || model.setup != nil }

    private func row<Trailing: View>(_ name: String, _ value: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            trailing()
        }
        .padding(.vertical, 12)
    }

    private var symbol: String {
        switch model.health {
        case .ready: return "checkmark.seal.fill"
        case .checking: return "hourglass"
        case .setupRequired, .pendingSetup: return "wrench.and.screwdriver.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
    private var color: Color {
        switch model.health {
        case .ready: return Palette.green
        case .checking: return Palette.muted
        case .setupRequired, .pendingSetup: return Palette.amber
        default: return Palette.red
        }
    }
    private var title: String {
        switch model.health {
        case .ready: return "Ready to decrypt"
        case .checking: return "Checking"
        case .setupRequired: return "Setup needed"
        case .pendingSetup: return "An earlier setup did not finish"
        case .toolsMissing: return "Apple developer tools are missing"
        case .engineMissing: return "The engine is missing"
        case .problem: return "Needs attention"
        }
    }
    private var explanation: String {
        switch model.health {
        case .ready: return "Your tools and model are verified."
        case .checking: return "Reading the setup on this Mac."
        case .setupRequired: return "IPA Loom has not been set up on this Mac yet."
        case .pendingSetup: return "Clean up what it left behind, then start setup again. Nothing from it is in use."
        case .toolsMissing: return "Install Apple's Command Line Tools (run xcode-select --install in Terminal), then check again."
        case .engineMissing: return "This copy of the app was built without the engine. Build it again with mac/build-app.sh."
        case .problem(let message): return message
        }
    }
}

/// This app's version, whether a newer release is out, and how to get it.
struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.heading).foregroundStyle(updater.available == nil ? Palette.ink : Palette.green)
                    Text(detail).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if working {
                    ProgressView().controlSize(.small)
                } else {
                    if installs {
                        Button("Install and Restart") { Task { await updater.install() } }.startButtonStyle()
                    }
                    if updater.available != nil {
                        Button("View Release") { updater.openPage() }.secondaryButtonStyle()
                    }
                    Button(updater.state == .checking ? "Checking…" : "Check Now") { Task { await updater.check() } }
                        .secondaryButtonStyle().disabled(!updater.canCheck || updater.state == .checking)
                }
            }
            if updater.available != nil, !installs, !working {
                Text("brew upgrade --cask ipa-loom").font(.small.monospaced()).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Toggle("Check for updates automatically, once a day", isOn: $updater.automatic)
                .toggleStyle(.switch).controlSize(.small).disabled(!updater.canCheck)
        }
        .glassCard(padding: 20)
    }

    private var working: Bool {
        if case .working = updater.state { return true }
        return false
    }
    /// Whether this copy can install the release it found by itself.
    private var installs: Bool {
        if case .available(let update) = updater.state { return update.image != nil && updater.cannotInstall == nil }
        return false
    }

    private var title: String {
        if let update = updater.available { return "Version \(update.version) is available" }
        return "IPA Loom " + (updater.version ?? "development build")
    }
    private var detail: String {
        if updater.available == nil, !updater.canCheck { return "This copy was not built as an app, so it does not look for updates." }
        switch updater.state {
        case .idle: return "Asks GitHub for the list of releases. Nothing about you or your apps is sent."
        case .checking: return "Asking GitHub for the list of releases."
        case .current: return "You have the newest release."
        case .available:
            let have = "You have \(updater.version ?? "a development build"). "
            if installs { return have + "IPA Loom downloads it, checks it comes from the same signer, and restarts. Your setup and Library stay as they are." }
            return have + "Update with Homebrew, or download it from the release page. Your setup and Library stay as they are."
        case .working(_, let step): return step
        case .failed(let message): return message
        }
    }
}
