import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Decrypt page: a link field and a drop area, or the run in progress.
struct DecryptPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let session = model.session {
            RunView(session: session).padding(28)
        } else if model.health == .ready || model.health == .checking {
            TargetEntry()
        } else {
            NotReadyNotice().padding(28)
        }
    }
}

/// Where a run starts: paste a link or an App ID, or drop a file.
struct TargetEntry: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var text = ""
    @ViewState private var dropping = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("What do you want to decrypt?").font(.system(size: 26, weight: .bold)).padding(.top, 44)
                Text("Paste an App Store link or App ID, or drop a file below.")
                    .foregroundStyle(Palette.muted).padding(.top, 6)

                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(Palette.muted)
                    TextField("https://apps.apple.com/app/id123456789", text: $text)
                        .textFieldStyle(.plain).font(.section).onSubmit(start)
                    Button("Decrypt", action: start).controlSize(.large).primaryButtonStyle()
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.leading, 20).padding(.trailing, 8).frame(height: 54)
                .glassCapsule()
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text("Drop an .ipa or an installed .app here").font(.heading)
                    Text("Installed iPhone and iPad apps from the App Store or TestFlight are supported.\nA TestFlight beta must be installed first.")
                        .font(.note).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button("Choose a File…", action: choose).secondaryButtonStyle().padding(.top, 6)
                }
                .frame(maxWidth: .infinity).padding(22)
                .background(dropping ? Palette.blue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(dropping ? Palette.blue : Palette.muted.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first(where: TargetEntry.accepts) else { return false }
                    model.start(target: url.path)
                    return true
                } isTargeted: { dropping = $0 }
                .padding(.top, 18)

                let recent = Array(model.libraryRecords.prefix(3))
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECENT").font(.small.weight(.semibold)).foregroundStyle(Palette.muted).padding(.leading, 6)
                        VStack(spacing: 0) {
                            ForEach(recent) { record in
                                HStack(spacing: 12) {
                                    LetterTile(name: record.displayName, size: 32)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(record.displayName)
                                        Text([record.app?.version, record.startedDate?.shortLabel].compactMap { $0 }.joined(separator: " · "))
                                            .font(.small).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    if record.verified { Tag(text: "Verified", color: Palette.green) }
                                }
                                .padding(.vertical, 12)
                                if record.id != recent.last?.id { Divider() }
                            }
                        }
                        .glassCard(padding: 12)
                    }
                    .padding(.top, 26)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.bottom, 24)
        }
    }

    private func start() { model.start(target: text) }

    private static func accepts(_ url: URL) -> Bool {
        ["ipa", "app"].contains(url.pathExtension.lowercased())
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.applicationBundle] + [UTType(filenameExtension: "ipa")].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Decrypt"
        if panel.runModal() == .OK, let url = panel.url { model.start(target: url.path) }
    }
}

/// The run in progress or just finished: its steps, its files and how it ended.
struct RunView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: RunSession
    @ViewState private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        LetterTile(name: session.title, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).font(.section.weight(.semibold))
                            Text(subtitle).font(.note).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if session.isRunning {
                            Button("Cancel") { session.cancel() }.secondaryButtonStyle()
                        } else {
                            Button("Decrypt Another") { model.session = nil }.primaryButtonStyle()
                        }
                    }
                    ProgressView(value: session.progress).tint(barColor)
                    Text(statusLine).font(.note).foregroundStyle(statusColor)
                }
                .glassCard()

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Steps").font(.heading)
                        ForEach(session.steps) { step in
                            HStack(spacing: 10) {
                                StepMark(state: step.state)
                                Text(step.title).fontWeight(step.state == .running ? .semibold : .regular)
                                    .foregroundStyle(step.state == .waiting ? Palette.muted : Palette.ink)
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Files").font(.heading)
                        let record = session.record
                        FileRow(title: "Encrypted (original)", file: record.flatMap(model.encrypted),
                                missing: session.kind == .store ? (session.isRunning ? "Kept when the run passes" : "Not kept") : session.kind == .file ? "Your own file, not copied" : "Not available: read from the installed app",
                                encrypted: true)
                        FileRow(title: "Decrypted", file: session.state == .passed ? record.flatMap(model.output) : nil,
                                missing: record?.outputFilename ?? "Pending", encrypted: false)
                        Text("The output is not re-signed. A passed verification is not Apple signature trust or proof that the app installs or runs.")
                            .font(.small).foregroundStyle(Palette.muted).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                DisclosureGroup("Engine output", isExpanded: $showLog) {
                    OutputBox(lines: session.log, height: 130)
                }
                .glassCard(padding: 12)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let app = session.record?.app { parts.append("Version \(app.version)") }
        switch session.kind {
        case .store: parts.append("from the App Store")
        case .file: parts.append("from a local IPA")
        case .installedApp: parts.append("from the installed app")
        }
        return parts.joined(separator: " · ")
    }

    private var statusLine: String {
        switch session.state {
        case .running: return session.steps.first { $0.state == .running }?.title ?? "Starting"
        case .passed: return "Done. The decrypted app passed verification and is in your Library."
        case .cancelled: return "Cancelled. The engine cleaned up its run."
        case .failed(let message): return message
        }
    }
    private var statusColor: Color {
        switch session.state {
        case .running: return Palette.muted
        case .passed: return Palette.green
        case .cancelled: return Palette.amber
        case .failed: return Palette.red
        }
    }
    private var barColor: Color {
        switch session.state {
        case .failed: return Palette.red
        case .cancelled: return Palette.amber
        case .passed: return Palette.green
        case .running: return Palette.blue
        }
    }
}

struct StepMark: View {
    var state: StepState
    var body: some View {
        Group {
            switch state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.red)
            case .running: ProgressView().controlSize(.small)
            case .waiting: Image(systemName: "circle").foregroundStyle(Palette.muted)
            }
        }
        .font(.section).frame(width: 22, height: 22)
    }
}

/// Shown on the Decrypt page while the engine is not ready to run.
struct NotReadyNotice: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.health == .setupRequired {
                Label("Set up IPA Loom first", systemImage: "sparkles")
                    .font(.heading).foregroundStyle(Palette.green)
                Text("A one-time setup prepares the tools, signs in to the App Store and builds what decryption needs. It takes a few minutes.")
                    .foregroundStyle(Palette.muted)
                Button("Start Setup") { model.page = .health }.startButtonStyle()
            } else {
                Label("IPA Loom is not ready to decrypt yet", systemImage: "exclamationmark.triangle.fill")
                    .font(.heading).foregroundStyle(Palette.amber)
                Text("Open Setup & Health to see what is missing and how to finish it.").foregroundStyle(Palette.muted)
                Button("Open Setup & Health") { model.page = .health }.primaryButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
