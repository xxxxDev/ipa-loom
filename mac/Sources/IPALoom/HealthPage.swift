import SwiftUI

/// Setup & Health: whether the engine can run, and what to do when it cannot.
struct HealthPage: View {
    @EnvironmentObject var model: AppModel

    private static let phases: [(String, String, Bool)] = [
        ("Prepare tools", "Builds ipatool and fetches the pinned UnfairPlay.", false),
        ("Choose an app", "One iPhone or iPad app installed from the Mac App Store.", true),
        ("Sign in to Apple", "Your Apple Account, and a code only if Apple asks.", true),
        ("Download the app and build the model", "Needs your Mac administrator password once.", true),
        ("Verify and finish", "Keeps that app decrypted as your first result.", false),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.title3.weight(.semibold))
                            Text(explanation).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Check Again") { Task { await model.checkHealth() } }.secondaryButtonStyle()
                            .disabled(model.health == .checking)
                    }
                }
                .glassCard()

                if model.health == .setupRequired {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("One-time setup").font(.headline)
                        Text("Setup builds your private decryption model. It asks for your Apple Account and your Mac administrator password, which IPA Loom takes in Terminal for now.")
                            .foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(HealthPage.phases.enumerated()), id: \.offset) { index, phase in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 20, height: 20).background(Palette.blue, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(phase.0)
                                    Text(phase.1).font(.caption).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                if phase.2 { Tag(text: "You", color: Palette.blue) }
                            }
                        }
                        Button("Start Setup in Terminal") { model.openTerminalSetup() }.primaryButtonStyle().padding(.top, 4)
                        Text("When setup finishes, come back and choose Check Again.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    .glassCard()
                }

                VStack(alignment: .leading, spacing: 0) {
                    row("Private data folder", Paths.dataRoot.path) {
                        Button("Show") { model.showDataFolder() }.buttonStyle(.link)
                    }
                    Divider()
                    row("Engine", Paths.engineRoot == nil ? "Missing from this app" : "Included in this app") { EmptyView() }
                    Divider()
                    row("Apple developer tools", model.health == .toolsMissing ? "Not installed" : "Installed") { EmptyView() }
                }
                .glassCard(padding: 14)

                Text("Tools, your encrypted account state, the private model and every output stay in the private data folder on this Mac. The app only starts the engine and reads its results.")
                    .font(.caption).foregroundStyle(Palette.muted).padding(.horizontal, 4)
            }
            .padding(20)
        }
    }

    private func row<Trailing: View>(_ name: String, _ value: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            trailing()
        }
        .padding(.vertical, 8)
    }

    private var symbol: String {
        switch model.health {
        case .ready: return "checkmark.seal.fill"
        case .checking: return "hourglass"
        case .setupRequired: return "wrench.and.screwdriver.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
    private var color: Color {
        switch model.health {
        case .ready: return Palette.green
        case .checking: return Palette.muted
        case .setupRequired: return Palette.amber
        default: return Palette.red
        }
    }
    private var title: String {
        switch model.health {
        case .ready: return "Ready to decrypt"
        case .checking: return "Checking"
        case .setupRequired: return "Setup needed"
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
        case .toolsMissing: return "Install Apple's Command Line Tools (run xcode-select --install in Terminal), then check again."
        case .engineMissing: return "This copy of the app was built without the engine. Build it again with mac/build-app.sh."
        case .problem(let message): return message
        }
    }
}
