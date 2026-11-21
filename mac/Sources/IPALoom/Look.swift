import AppKit
import SwiftUI

/// In recent SDKs `@State` is a macro whose plugin ships only with Xcode. The Command Line
/// Tools are enough to build this app, so the views use the property wrapper by this name.
typealias ViewState = SwiftUI.State

// Liquid Glass on macOS 26 and later, the closest older look before it. The build script
// records the current SDK in the binary, so the window and plain controls take the system's
// glass by themselves; these cover the cards and the main buttons.
enum GlassLook {
    /// Set once, before any window, by the layout pictures a debug build draws: they are
    /// drawn outside the window server, which is what renders glass.
    nonisolated(unsafe) static var plain = false
}

extension View {
    /// A rounded glass panel around a group of content.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *), !GlassLook.plain {
            self.padding(padding).glassEffect(.regular, in: shape)
        } else {
            self.padding(padding).background(.regularMaterial, in: shape)
        }
    }

    /// A glass capsule, for the link field.
    @ViewBuilder func glassCapsule() -> some View {
        if #available(macOS 26, *), !GlassLook.plain {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }

    /// The page's main action: blue-tinted glass.
    /// The green button that begins first setup.
    func startButtonStyle() -> some View { buttonStyle(StartButtonStyle()) }

    @ViewBuilder func primaryButtonStyle() -> some View {
        if #available(macOS 26, *), !GlassLook.plain {
            self.buttonStyle(.glass(.regular.tint(Palette.blue.opacity(0.6)).interactive())).foregroundStyle(.white)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Clear glass, untinted.
    @ViewBuilder func secondaryButtonStyle() -> some View {
        if #available(macOS 26, *), !GlassLook.plain {
            self.buttonStyle(.glass(.regular.interactive())).tint(nil)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// The app's type sizes, a step larger than the system's small defaults for a window that is
/// read at arm's length.
extension Font {
    static let tiny = Font.system(size: 12)
    static let small = Font.system(size: 13)
    static let note = Font.system(size: 14)
    static let text = Font.system(size: 15)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let section = Font.system(size: 18)
    static let pageTitle = Font.system(size: 24)
    static let hero = Font.system(size: 30)
}

/// The app's colours: the logo's blue on dark paper. The app has one look, dark.
enum Palette {
    static let blue = Color(red: 0x08 / 255, green: 0x66 / 255, blue: 0xFF / 255)
    static let green = rgb(0x5FE389)
    static let amber = rgb(0xFFB84D)
    static let red = rgb(0xFF7B72)
    static let paper = rgb(0x15181D)
    static let ink = rgb(0xF2F4F7)
    static let muted = rgb(0x9AA6B6)
    static let line = rgb(0x2B323D)

    private static func rgb(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// Paper with a faint grid and a blue glow behind the window's content, so the glass above
/// it has something to show.
struct WindowBackdrop: View {
    var body: some View {
        ZStack {
            Palette.paper
            Canvas { context, size in
                var grid = Path()
                let step: CGFloat = 28
                for x in stride(from: 0, through: size.width, by: step) { grid.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)) }
                for y in stride(from: 0, through: size.height, by: step) { grid.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)) }
                context.fill(grid, with: .color(Palette.line.opacity(0.55)))
            }
            .mask(RadialGradient(colors: [.black, .clear], center: .topLeading, startRadius: 0, endRadius: 760))
            RadialGradient(colors: [Palette.blue.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Palette.blue.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

/// A coloured tile with the app's initial, standing in for its icon.
struct LetterTile: View {
    var name: String
    var size: CGFloat = 40

    private static let gradients: [[Color]] = [
        [Color(red: 1.0, green: 0.62, blue: 0.26), Color(red: 1.0, green: 0.37, blue: 0.38)],
        [Color(red: 0.37, green: 0.91, blue: 0.87), Color(red: 0.18, green: 0.5, blue: 0.93)],
        [Color(red: 0.69, green: 0.42, blue: 0.7), Color(red: 0.27, green: 0.41, blue: 0.86)],
        [Color(red: 0.66, green: 0.88, blue: 0.39), Color(red: 0.23, green: 0.66, blue: 0.34)],
        [Color(red: 1.0, green: 0.81, blue: 0.36), Color(red: 1.0, green: 0.62, blue: 0.04)],
    ]

    var body: some View {
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let colors = LetterTile.gradients[seed % LetterTile.gradients.count]
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// A small rounded label: "Verified", "Failed".
struct Tag: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text).font(.small.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

/// One IPA in a card: what it is, its name and size, and a way to find it.
struct FileRow: View {
    @EnvironmentObject var model: AppModel
    var title: String
    var file: StoredFile?
    var missing: String
    var encrypted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: encrypted ? "lock.doc" : "doc.zipper")
                .font(.section).foregroundStyle(encrypted ? Palette.amber : Palette.green).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.note)
                Text(file.map { "\($0.name) · \(ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file))" } ?? missing)
                    .font(.small).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let file {
                Button("Show in Finder") { model.reveal(file) }.buttonStyle(.link).font(.small)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .opacity(file == nil ? 0.6 : 1)
    }
}

extension Date {
    /// "Today 14:02", "Yesterday 09:10", or the date.
    var shortLabel: String {
        let calendar = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(self) { return "Today " + time }
        if calendar.isDateInYesterday(self) { return "Yesterday " + time }
        return formatted(date: .abbreviated, time: .shortened)
    }
}

/// A solid green capsule: the one action a Mac that was never set up should take.
struct StartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heading).foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(Color(red: 0.12, green: 0.64, blue: 0.33).opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}
