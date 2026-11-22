import ChoreKit
import SwiftUI
import UIKit

// The Chore Blitz look: navy and lightning yellow, rounded heavy titles.
// Game mode swaps in the arcade skin (purple, square corners, monospaced caps).

enum Palette {
    static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// A color that follows the phone's light or dark setting.
    static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? hex(dark) : hex(light) })
    }

    static let accent = Color(uiColor: hex(0xFFC83D))
    static let onAccent = Color(uiColor: hex(0x1B1400))
    static let done = Color(uiColor: hex(0x3DDC84))
    static let onDone = Color(uiColor: hex(0x04230F))
    static let danger = Color(uiColor: hex(0xE5484D))

    static let bg = dyn(light: 0xF2F3F8, dark: 0x0C111E)
    static let card = dyn(light: 0xFFFFFF, dark: 0x182036)
    static let inset = dyn(light: 0xECEEF5, dark: 0x222B45)
    static let line = dyn(light: 0xE1E4EE, dark: 0x2A3452)
    static let text = dyn(light: 0x131826, dark: 0xF4F6FB)
    static let text2 = dyn(light: 0x5F6880, dark: 0x98A2BA)
    /// The accent when it's used for text or icons on the background.
    static let accentText = dyn(light: 0xA36F00, dark: 0xFFC83D)

    // Arcade (Game mode).
    static let arcadeTop = Color(uiColor: hex(0x0F0524))
    static let arcadeBottom = Color(uiColor: hex(0x2A0D45))
    static let arcadeYellow = Color(uiColor: hex(0xFFE14D))
    static let arcadeCyan = Color(uiColor: hex(0x3DE0FF))
    static let arcadeMint = Color(uiColor: hex(0x5DFFC1))
    static let arcadePink = Color(uiColor: hex(0xF0569A))
    static let arcadeText2 = Color(uiColor: hex(0xB9A8E0))
}

/// Everything a screen needs to draw itself in the normal or the arcade look.
struct Skin: Equatable {
    var arcade = false

    var bg: Color { arcade ? Palette.arcadeTop : Palette.bg }
    var card: Color { arcade ? Color.white.opacity(0.09) : Palette.card }
    var inset: Color { arcade ? Color.white.opacity(0.13) : Palette.inset }
    var line: Color { arcade ? Color.white.opacity(0.10) : Palette.line }
    var text: Color { arcade ? .white : Palette.text }
    var text2: Color { arcade ? Palette.arcadeText2 : Palette.text2 }
    var accent: Color { arcade ? Palette.arcadeYellow : Palette.accent }
    var accentText: Color { arcade ? Palette.arcadeYellow : Palette.accentText }
    var corner: CGFloat { arcade ? 6 : 20 }
    var buttonCorner: CGFloat { arcade ? 4 : 14 }

    /// Screen and card titles.
    func title(_ size: CGFloat) -> Font {
        arcade ? .system(size: size * 0.9, weight: .black, design: .monospaced)
               : .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Body text with some weight to it.
    func body(_ size: CGFloat = 17, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Small caps label above a group.
    func label(_ size: CGFloat = 13) -> Font {
        arcade ? .system(size: size + 1, weight: .black, design: .monospaced)
               : .system(size: size, weight: .heavy, design: .rounded)
    }

    func word(_ normal: String, _ arcadeWord: String) -> String { arcade ? arcadeWord : normal }

    static let standard = Skin()
    static let arcadeSkin = Skin(arcade: true)
}

private struct SkinKey: EnvironmentKey {
    static let defaultValue = Skin.standard
}

extension EnvironmentValues {
    var skin: Skin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

/// A rounded panel in the skin's card color.
struct CardBox: ViewModifier {
    @Environment(\.skin) private var skin
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(skin.card, in: RoundedRectangle(cornerRadius: skin.corner, style: .continuous))
    }
}

extension View {
    func cardBox(padding: CGFloat = 16) -> some View { modifier(CardBox(padding: padding)) }
}

/// "UP FOR GRABS        4": the small caps label above a group.
struct SectionLabel: View {
    @Environment(\.skin) private var skin
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased())
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(skin.label())
        .kerning(skin.arcade ? 0 : 0.8)
        .foregroundStyle(skin.arcade ? skin.accent : skin.text2)
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }
}

/// One pill per chore: colored by whoever finished it, grey while it's still to do.
struct SegmentedProgress: View {
    let tasks: [BlitzTask]
    var height: CGFloat = 10
    var track: Color = Palette.inset

    var body: some View {
        // Finished chores first, in the order they were finished.
        let done = tasks.filter { $0.doneAt != nil }.sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
        let colors: [Color] = done.map { $0.claimedBy?.color ?? Palette.done }
            + Array(repeating: track, count: max(tasks.count - done.count, 0))
        HStack(spacing: tasks.count > 24 ? 2 : height * 0.3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Capsule().fill(color).frame(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.4), value: done.count)
        .accessibilityLabel("\(done.count) of \(tasks.count) done")
    }
}
