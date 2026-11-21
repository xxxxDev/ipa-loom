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
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to IPA Loom").font(.hero.bold())
                Text("A one-time setup builds your private decryption model.")
                    .font(.section).foregroundStyle(Palette.muted)
            }
            PhaseStrip(current: 1, running: true)

            if model.installedApps.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Install one iPhone or iPad app first", systemImage: "square.and.arrow.down")
                        .font(.heading).foregroundStyle(Palette.amber)
                    ForEach(Array(["Open the App Store on this Mac and search for any free app you use on iPhone.",
                                   "Under the search field, choose \"iPhone & iPad Apps\", then install the app.",
                                   "Open the app once, then come back and choose Check Again."].enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            NumberDot(number: index + 1)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("Open App Store") { NSWorkspace.shared.open(URL(string: "macappstore://")!) }.primaryButtonStyle()
                        Button("Check Again") { model.findInstalledApps() }.secondaryButtonStyle()
                    }
                    .controlSize(.large).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 22)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick one iPhone or iPad app installed from the App Store").font(.heading)
                    VStack(spacing: 0) {
                        ForEach(model.installedApps) { app in
                            Button { picked = app } label: {
                                HStack(spacing: 14) {
                                    LetterTile(name: app.name, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name).font(.text.weight(.medium))
                                        Text("Version \(app.version)").font(.note).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    Image(systemName: picked == app ? "largecircle.fill.circle" : "circle")
                                        .font(.section).foregroundStyle(picked == app ? Palette.blue : Palette.muted)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(picked == app ? Palette.blue.opacity(0.16) : .clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if app != model.installedApps.last { Divider() }
                        }
                    }
                    .glassCard(padding: 0)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("It is used once to build the model and becomes your first decrypted app. Keep it at its current App Store version.")
                        .font(.note).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }

            if let note { Text(note).font(.note).foregroundStyle(Palette.amber) }

            HStack(spacing: 10) {
                Button("Choose Another App…", action: choose).buttonStyle(.link)
                Button("Use Terminal Instead") { model.openTerminalSetup() }.buttonStyle(.link).padding(.leading, 8)
                Spacer()
                if !model.installedApps.isEmpty {
                    Button("Check Again") { model.findInstalledApps() }.secondaryButtonStyle()
                    Button("Continue") { if let picked { model.startSetup(with: picked) } }
                        .primaryButtonStyle().disabled(picked == nil)
                }
            }
            .controlSize(.large)

            Text("Next: Apple sign-in and your Mac administrator password. Both go straight to the sign-in and system tools on this Mac; the app saves neither.")
                .font(.note).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Text("\(number)").font(.small.weight(.bold)).foregroundStyle(.white)
            .frame(width: 20, height: 20).background(Palette.blue, in: Circle())
    }
}

/// Setup while it runs, and how it ended.
struct SetupRunView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var setup: SetupSession
    @ViewState private var showOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                LetterTile(name: setup.app.name, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading).font(.pageTitle.bold())
                    Text((setup.state == .passed ? "Model built from " : "Building the model from ") + "\(setup.app.name) \(setup.app.version)")
                        .font(.note).foregroundStyle(Palette.muted)
                }
                Spacer()
                if setup.isRunning {
                    Button(setup.stopping ? "Stopping…" : "Cancel") { setup.cancel() }.secondaryButtonStyle()
                        .disabled(setup.stopping)
                        .help(setup.cancelsNow ? "Stop setup and remove what it prepared" : "This step cannot be interrupted safely. Setup will stop at its next question.")
                }
            }

            PhaseStrip(current: PhaseStrip.shown(setup.phase), running: setup.isRunning)

            if let question = setup.question {
                QuestionForm(setup: setup, question: question)
            } else {
                // The result and the way onward sit together, where the eye already is.
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        if setup.isRunning { ProgressView().controlSize(.small) }
                        if setup.state == .passed { Image(systemName: "checkmark.circle.fill").font(.section).foregroundStyle(Palette.green) }
                        Text(message).foregroundStyle(messageColor).fixedSize(horizontal: false, vertical: true)
                    }
                    if setup.state == .passed {
                        Text("Next: paste an App Store link or drop an IPA to decrypt another app.").foregroundStyle(Palette.muted)
                        HStack(spacing: 12) {
                            Button { model.setup = nil; model.page = .decrypt } label: {
                                Label("Decrypt an App", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle())
                            }.startButtonStyle()
                            Button("Open Library") { model.setup = nil; model.page = .library }.secondaryButtonStyle()
                        }
                    } else if !setup.isRunning {
                        Button("Try Again") { model.setup = nil }.primaryButtonStyle()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 20)
            }

            DisclosureGroup("Setup output", isExpanded: $showOutput) {
                // Its own scrolling box that follows the newest line, so the page stays put.
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(setup.text.lines.suffix(200).joined(separator: "\n"))
                            .font(.small.monospaced()).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            .padding(14).id("end")
                    }
                    .frame(height: 220)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line))
                    .padding(.top, 8)
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: setup.text.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .running: return setup.stopping ? "Stopping at the next question. " + setup.status : setup.status
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
    /// The steps in the order the user meets them: the app is chosen in this window before the
    /// engine starts, so choosing comes first and the engine's own first two phases (preparing
    /// tools, then taking the choice it is handed) both show as the second step.
    static let titles = [SetupSession.phases[1], SetupSession.phases[0]] + SetupSession.phases[2...]
    static func shown(_ phase: Int) -> Int { phase <= 2 ? 2 : phase }
    private static let needsInput: Set<Int> = [1, 3, 4]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(PhaseStrip.titles.enumerated()), id: \.offset) { index, title in
                let number = index + 1
                let done = current > number
                let active = current == number
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        if done { Image(systemName: "checkmark").font(.tiny.weight(.bold)) }
                        Text("\(number) · " + (PhaseStrip.needsInput.contains(number) ? "You" : "Auto"))
                            .font(.note.weight(.semibold))
                    }
                    .foregroundStyle(done ? Palette.green : active ? (running ? Palette.blue : Palette.red) : Palette.muted)
                    Text(title).font(.text.weight(active ? .semibold : .regular)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(active ? Palette.ink : Palette.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.section.weight(.semibold))
            Text(explanation).font(.note).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            switch question {
            case .appleAccount:
                VStack(spacing: 10) {
                    TextField("Apple ID (email address)", text: $first).textContentType(.username).focused($focused).onSubmit(submit)
                    SecureField("Password", text: $second).onSubmit(submit)
                }
                .frame(maxWidth: 380)
            case .applePassword:
                SecureField("Apple Account password", text: $first).focused($focused).onSubmit(submit).frame(maxWidth: 380)
            case .verificationCode:
                TextField("6-digit code", text: $first).focused($focused).onSubmit(submit).frame(maxWidth: 180)
            case .adminPassword:
                SecureField("Mac administrator password", text: $first).focused($focused).onSubmit(submit).frame(maxWidth: 380)
            case .other:
                if setup.echo {
                    TextField("Your answer", text: $first).focused($focused).onSubmit(submit)
                } else {
                    SecureField("Typed characters stay hidden", text: $first).focused($focused).onSubmit(submit)
                }
            }
            HStack {
                Text("Passed straight to the tool that asked. The app saves none of it.")
                    .font(.small).foregroundStyle(Palette.muted)
                Spacer()
                Button(question == .appleAccount ? "Sign In" : "Continue", action: submit)
                    .primaryButtonStyle().disabled(first.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(22)
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
