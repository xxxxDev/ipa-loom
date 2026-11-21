import SwiftUI

/// The Library: every decrypted app that is still on disk, with its files.
struct LibraryPage: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var search = ""

    private var shown: [RunRecord] {
        let all = model.libraryRecords
        guard !search.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(search) || ($0.app?.bundleID.localizedCaseInsensitiveContains(search) ?? false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Spacer()
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.secondaryButtonStyle()
            }
            .padding(.horizontal, 28).padding(.top, 12)

            if model.libraryRecords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 34)).foregroundStyle(Palette.muted)
                    Text("No decrypted apps yet").font(.heading)
                    Text("Apps you decrypt appear here with their files.").foregroundStyle(Palette.muted)
                    Button("Decrypt an App") { model.page = .decrypt }.primaryButtonStyle().padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(shown) { LibraryCard(record: $0) }
                    }
                    .padding(28)
                }
                Text(summary).font(.note).foregroundStyle(Palette.muted).padding(.horizontal, 28).padding(.bottom, 14)
            }
        }
    }

    private var summary: String {
        let files = model.libraryRecords.flatMap { [model.output(of: $0), model.encrypted(of: $0)].compactMap { $0 } }
        let bytes = files.reduce(Int64(0)) { $0 + $1.size }
        let apps = model.libraryRecords.count
        return "\(apps) \(apps == 1 ? "app" : "apps") · \(files.count) \(files.count == 1 ? "file" : "files") · "
            + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " in your private data folder"
    }
}

struct LibraryCard: View {
    @EnvironmentObject var model: AppModel
    var record: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                LetterTile(name: record.displayName)
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.displayName).font(.heading).lineLimit(1)
                    Text(["Version \(record.app?.version ?? "?")", record.startedDate?.shortLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.small).foregroundStyle(Palette.muted)
                }
                Spacer()
                if record.verified { Tag(text: "Verified", color: Palette.green) }
            }
            FileRow(title: "Encrypted (original)", file: model.encrypted(of: record),
                    missing: record.inputKind == "installed-app" ? "Not available: read from the installed app" : record.inputKind == "file" ? "Your own file, not copied" : "Not kept for this run",
                    encrypted: true)
            FileRow(title: "Decrypted", file: model.output(of: record), missing: "Removed", encrypted: false)
        }
        .glassCard()
    }
}

/// Every run the engine has recorded, passed or not.
struct ActivityPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.records.isEmpty {
            Text("No runs yet").foregroundStyle(Palette.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.records) { record in
                        HStack(spacing: 12) {
                            Image(systemName: record.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(record.passed ? Palette.green : Palette.red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.displayName)
                                Text(detail(record)).font(.small).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Text(record.startedDate?.shortLabel ?? "").font(.small).foregroundStyle(Palette.muted)
                        }
                        .padding(.vertical, 9)
                        if record.id != model.records.last?.id { Divider() }
                    }
                }
                .glassCard(padding: 14)
                .padding(28)
            }
        }
    }

    private func detail(_ record: RunRecord) -> String {
        var parts = [record.kindLabel]
        if let version = record.app?.version { parts.append("Version \(version)") }
        if record.passed {
            if let start = record.startedDate, let end = record.endedDate {
                parts.append(String(format: "%.0f s", max(end.timeIntervalSince(start), 1)))
            }
            if model.output(of: record) == nil, record.outputFilename != nil { parts.append("file removed") }
        } else {
            parts.append(record.status == "failed" ? "Failed" : record.status.capitalized)
        }
        return parts.joined(separator: " · ")
    }
}
