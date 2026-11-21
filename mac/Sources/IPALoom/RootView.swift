import SwiftUI

/// The window: a glass sidebar of pages, and the chosen page beside it.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    static let size = NSSize(width: 1080, height: 700)
    static let minimum = NSSize(width: 920, height: 600)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Page.allCases) { page in
                    Button { model.page = page } label: {
                        HStack {
                            Label(page.rawValue, systemImage: page.symbol)
                            Spacer()
                            if page == .library, !model.libraryRecords.isEmpty {
                                Text("\(model.libraryRecords.count)").font(.caption).opacity(0.7)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(page == model.page ? Palette.blue : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(page == model.page ? Color.white : Palette.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HealthChip()
            }
            .frame(width: 180)
            .padding(.top, 28)
            .glassCard(cornerRadius: 16, padding: 8)
            .padding(10)

            VStack(alignment: .leading, spacing: 0) {
                Text(model.page.rawValue).font(.title2.bold()).padding(.horizontal, 20).padding(.top, 16)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
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
                    Text(title).font(.caption.weight(.semibold))
                    Text(detail).font(.caption2).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        case .ready: return "Ready"
        case .checking: return "Checking"
        case .setupRequired: return "Setup needed"
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
