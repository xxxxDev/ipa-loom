import SwiftUI

/// The window: a glass sidebar of pages, and the chosen page beside it.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    static let size = NSSize(width: 1180, height: 780)
    static let minimum = NSSize(width: 980, height: 640)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Page.allCases) { page in
                    Button { model.page = page } label: {
                        HStack {
                            Label(page.rawValue, systemImage: page.symbol)
                            Spacer()
                            if page == .library, !model.libraryRecords.isEmpty {
                                Text("\(model.libraryRecords.count)").font(.small).opacity(0.7)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(page == model.page ? Palette.blue : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(page == model.page ? Color.white : Palette.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                UpdateChip(updater: model.updater)
                HealthChip()
            }
            .frame(width: 212)
            .padding(.top, 30)
            .glassCard(cornerRadius: 18, padding: 10)
            .padding(12)

            VStack(alignment: .leading, spacing: 0) {
                if !(model.page == .health && (model.health == .setupRequired || model.setup != nil)) {
                    Text(model.page.rawValue).font(.pageTitle.bold()).padding(.horizontal, 28).padding(.top, 22)
                }
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .font(.text)
        .controlSize(.large)
        .background(WindowBackdrop())
        .frame(minWidth: RootView.minimum.width, minHeight: RootView.minimum.height)
    }

    @ViewBuilder private var detail: some View {
        switch model.page {
        case .decrypt: DecryptPage()
        case .library: LibraryPage()
        case .activity: ActivityPage()
        case .health: HealthPage()
        }
    }
}

/// The engine's state, at the foot of the sidebar.
struct HealthChip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button { model.page = .health } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.small.weight(.semibold))
                    Text(detail).font(.tiny).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        case .ready: return "Ready"
        case .checking: return "Checking"
        case .setupRequired: return "Setup needed"
        case .pendingSetup: return "Clean-up needed"
        case .toolsMissing: return "Tools missing"
        case .engineMissing: return "Engine missing"
        case .problem: return "Needs attention"
        }
    }
    private var detail: String {
        switch model.health {
        case .ready: return "Model and tools verified"
        case .checking: return "Reading the setup"
        case .setupRequired: return "One-time setup"
        default: return "See Setup & Health"
        }
    }
}

/// A newer release, above the engine's state in the sidebar; nothing when there is none.
struct UpdateChip: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var updater: Updater

    var body: some View {
        if let update = updater.available {
            Button { model.page = .health } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update available").font(.small.weight(.semibold))
                        Text("Version " + update.version).font(.tiny).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Palette.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
