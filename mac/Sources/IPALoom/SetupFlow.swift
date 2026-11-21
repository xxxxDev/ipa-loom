import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// First setup inside the app: pick the app the model is built from, then follow the engine
/// through its five phases, answering its tools when they ask.
struct SetupFlow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let setup = model.setup {
            SetupRunView(setup: setup)
        } else {
            AppPicker()
        }
    }
}

/// Step one, before anything is downloaded: the installed app to build the model from.
struct AppPicker: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var picked: InstalledApp?
    @ViewState private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One-time setup").font(.headline)
            PhaseStrip(current: 2, running: true, started: false)
            Text("IPA Loom builds a private decryption model from one iPhone or iPad app that is installed on this Mac from the App Store. The model then decrypts the other apps you choose.")
                .foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)

            if model.installedApps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No iPhone or iPad app from the App Store is installed yet", systemImage: "square.and.arrow.down")
                        .font(.headline).foregroundStyle(Palette.amber)
                    ForEach(Array(["Open the App Store on this Mac and search for any free app you use on iPhone.",
                                   "Under the search field, choose \"iPhone & iPad Apps\", then install the app.",
                                   "Open the app once, come back here and choose Check Again."].enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            NumberDot(number: index + 1)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        Button("Open App Store") { NSWorkspace.shared.open(URL(string: "macappstore://")!) }.primaryButtonStyle()
                        Button("Check Again") { model.findInstalledApps() }.secondaryButtonStyle()
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text("CHOOSE AN APP").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                VStack(spacing: 0) {
                    ForEach(model.installedApps) { app in
                        Button { picked = app } label: {
                            HStack(spacing: 12) {
                                Image(systemName: picked == app ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(picked == app ? Palette.blue : Palette.muted)
                                LetterTile(name: app.name, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                    Text("Version \(app.version)").font(.caption).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 7).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if app != model.installedApps.last { Divider() }
                    }
                }
                Text("Make sure the app is at its current App Store version. Setup downloads the same version to compare.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }

            if let note { Text(note).font(.caption).foregroundStyle(Palette.amber) }

            HStack {
                Button("Start Setup") { if let picked { model.startSetup(with: picked) } }
                    .primaryButtonStyle().disabled(picked == nil)
                Button("Choose Another App…", action: choose).secondaryButtonStyle()
                if !model.installedApps.isEmpty {
                    Button("Check Again") { model.findInstalledApps() }.secondaryButtonStyle()
                }
                Spacer()
                Button("Use Terminal Instead") { model.openTerminalSetup() }.buttonStyle(.link)
            }
            Text("Setup asks for your Apple Account and your Mac administrator password. The app passes what you type straight to the sign-in and system tools and keeps none of it.")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear {
            model.findInstalledApps()
            if picked == nil, model.installedApps.count == 1 { picked = model.installedApps.first }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let app = InstalledApps.identity(of: url) {
            if !model.installedApps.contains(app) { model.installedApps.append(app) }
            picked = app
            note = nil
        } else {
            note = "That is a Mac app or a TestFlight beta. Setup needs an iPhone or iPad app from the App Store."
        }
    }
}

struct NumberDot: View {
    var number: Int
    var body: some View {
        Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.white)
            .frame(width: 20, height: 20).background(Palette.blue, in: Circle())
    }
}

/// Setup while it runs, and how it ended.
struct SetupRunView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var setup: SetupSession
    @ViewState private var showOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LetterTile(name: setup.app.name, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(heading).font(.headline)
                    Text("Building the model from \(setup.app.name) \(setup.app.version)")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                if setup.isRunning {
                    Button("Cancel") { setup.cancel() }.secondaryButtonStyle()
                } else if setup.state == .passed {
                    Button("Decrypt an App") { model.setup = nil; model.page = .decrypt }.primaryButtonStyle()
                } else {
                    Button("Try Again") { model.setup = nil }.primaryButtonStyle()
                }
            }

            PhaseStrip(current: setup.phase, running: setup.isRunning)

            if let question = setup.question {
                QuestionForm(setup: setup, question: question)
            } else {
                Text(message).font(.callout).foregroundStyle(messageColor).fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("Setup output", isExpanded: $showOutput) {
                Text(setup.text.lines.suffix(30).joined(separator: "\n"))
                    .font(.caption.monospaced()).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var heading: String {
        switch setup.state {
        case .running: return "Setting up IPA Loom"
        case .passed: return "IPA Loom is ready"
        case .cancelled: return "Setup cancelled"
        case .failed: return "Setup stopped"
        }
    }
    private var message: String {
        switch setup.state {
        case .running: return setup.status
        case .passed: return "The model is verified. \(setup.app.name) is in your Library as the first decrypted app."
        case .cancelled: return "Nothing was installed. You can start again when you are ready."
        case .failed(let reason): return reason
        }
    }
    private var messageColor: Color {
        switch setup.state {
        case .running: return Palette.muted
        case .passed: return Palette.green
        case .cancelled: return Palette.amber
        case .failed: return Palette.red
        }
    }
}

/// The five phases across the top: done, current, still to come. "You" marks the ones that
/// ask for something.
struct PhaseStrip: View {
    var current: Int
    var running: Bool
    /// False before setup starts: the first phase has not run yet, the user is choosing.
    var started = true
    private static let needsInput: Set<Int> = [2, 3, 4]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(SetupSession.phases.enumerated()), id: \.offset) { index, title in
                let number = index + 1
                let done = started && current > number
                let active = current == number
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if done { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                        Text("\(number) · " + (PhaseStrip.needsInput.contains(number) ? "You" : "Auto"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(done ? Palette.green : active ? (running ? Palette.blue : Palette.red) : Palette.muted)
                    Text(title).font(.caption).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(active ? Palette.ink : Palette.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                .background(Color.white.opacity(active ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(active ? Palette.blue.opacity(running ? 0.9 : 0) : .clear, lineWidth: 1.5))
            }
        }
    }
}

/// A native form for what the sign-in or system tool is asking.
struct QuestionForm: View {
    @ObservedObject var setup: SetupSession
    var question: SetupSession.Question
    @ViewState private var first = ""
    @ViewState private var second = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            Text(explanation).font(.callout).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            switch question {
            case .appleAccount:
                TextField("Apple ID (email address)", text: $first).textContentType(.username).focused($focused).onSubmit(submit)
                SecureField("Password", text: $second).onSubmit(submit)
            case .applePassword:
                SecureField("Apple Account password", text: $first).focused($focused).onSubmit(submit)
            case .verificationCode:
                TextField("6-digit code", text: $first).focused($focused).onSubmit(submit).frame(maxWidth: 180)
            case .adminPassword:
                SecureField("Mac administrator password", text: $first).focused($focused).onSubmit(submit)
            case .other:
                if setup.echo {
                    TextField("Your answer", text: $first).focused($focused).onSubmit(submit)
                } else {
                    SecureField("Typed characters stay hidden", text: $first).focused($focused).onSubmit(submit)
                }
            }
            HStack {
                Text("Passed straight to the tool that asked. The app saves none of it.")
                    .font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Button(question == .appleAccount ? "Sign In" : "Continue", action: submit)
                    .primaryButtonStyle().disabled(first.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(14)
        .background(Palette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { focused = true }
        .id(question)
    }

    private func submit() {
        guard !first.isEmpty else { return }
        if question == .appleAccount { setup.signIn(appleID: first, password: second) } else { setup.send(first) }
        first = ""
        second = ""
    }

    private var title: String {
        switch question {
        case .appleAccount: return "Sign in with your Apple Account"
        case .applePassword: return "Apple Account password"
        case .verificationCode: return "Verification code"
        case .adminPassword: return "Mac administrator password"
        case .other(let prompt): return prompt
        }
    }
    private var symbol: String {
        switch question {
        case .appleAccount, .applePassword: return "person.crop.circle"
        case .verificationCode: return "lock.shield"
        case .adminPassword: return "lock.laptopcomputer"
        case .other: return "questionmark.circle"
        }
    }
    private var explanation: String {
        switch question {
        case .appleAccount, .applePassword:
            return "The App Store sign-in downloads the app you chose. Your password is encrypted on this Mac and its unlock key goes into your Keychain."
        case .verificationCode: return "Apple sent a code to your trusted devices."
        case .adminPassword: return "Building the model reads the installed app with administrator rights, once."
        case .other: return "Setup needs an answer to continue."
        }
    }
}
