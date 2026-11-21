import ChoreKit
import SwiftUI

// Building blocks shared by the phone screens.

/// The app's big buttons: yellow to take something on, green to finish it,
/// grey for everything else.
struct BlitzButtonStyle: ButtonStyle {
    enum Kind { case accent, done, quiet, danger }
    var kind: Kind = .accent
    var height: CGFloat = 50
    /// Stretch to the full width available.
    var fill = true

    func makeBody(configuration: Configuration) -> some View {
        Face(kind: kind, height: height, fill: fill, pressed: configuration.isPressed, label: configuration.label)
    }

    private struct Face<Label: View>: View {
        @Environment(\.skin) private var skin
        @Environment(\.isEnabled) private var isEnabled
        let kind: Kind
        let height: CGFloat
        let fill: Bool
        let pressed: Bool
        let label: Label

        var background: Color {
            switch kind {
            case .accent: return skin.accent
            case .done: return Palette.done
            case .quiet: return skin.inset
            case .danger: return Palette.danger.opacity(0.16)
            }
        }

        var foreground: Color {
            switch kind {
            case .accent: return Palette.onAccent
            case .done: return Palette.onDone
            case .quiet: return skin.text
            case .danger: return Palette.danger
            }
        }

        var body: some View {
            label
                .font(skin.arcade ? .system(size: height * 0.33, weight: .black, design: .monospaced)
                                  : .system(size: height * 0.35, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(foreground)
                .padding(.horizontal, height * 0.36)
                .frame(maxWidth: fill ? .infinity : nil, minHeight: height, maxHeight: height)
                // Hard arcade shadow on the button shape only; on the whole view it
                // would also double the label text.
                .background(
                    RoundedRectangle(cornerRadius: skin.buttonCorner, style: .continuous)
                        .fill(background)
                        .shadow(color: .black.opacity(skin.arcade ? 0.5 : 0), radius: 0, x: 4, y: 4)
                )
                .opacity(isEnabled ? (pressed ? 0.75 : 1) : 0.4)
                .scaleEffect(pressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }
    }
}

/// Scrolling page with the skin's background and a big title row.
struct Page<Trailing: View, Content: View>: View {
    @Environment(\.skin) private var skin
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Text(skin.arcade ? title.uppercased() : title)
                        .font(skin.title(34))
                        .foregroundStyle(skin.arcade ? skin.accent : skin.text)
                    Spacer(minLength: 8)
                    trailing()
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
                content()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            // Stays phone-width on the Mac and iPad.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(skin.text)
        .background { PageBackground() }
    }
}

/// The plain or arcade backdrop behind a whole screen.
struct PageBackground: View {
    @Environment(\.skin) private var skin

    var body: some View {
        if skin.arcade {
            ArcadePhoneBackground()
        } else {
            skin.bg.ignoresSafeArea()
        }
    }
}

extension View {
    /// Gives a `List` or `Form` the skin's background instead of the system grey.
    func skinnedList() -> some View {
        scrollContentBackground(.hidden).background { PageBackground() }
    }
}

/// A title with an optional smaller line under it, for settings-style rows.
struct TwoLineLabel: View {
    @Environment(\.skin) private var skin
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(skin.body(17, .bold)).foregroundStyle(skin.text)
            if let detail {
                Text(detail).font(skin.body(13)).foregroundStyle(skin.text2)
            }
        }
    }
}

/// The room picker next to "Add a chore…": a grey chip, so it reads as a
/// choice and not as a link.
struct RoomChip: View {
    @Environment(\.skin) private var skin
    let rooms: [String]
    @Binding var room: String

    var body: some View {
        Menu {
            ForEach(rooms, id: \.self) { r in Button(r) { room = r } }
        } label: {
            HStack(spacing: 4) {
                Text(room.isEmpty ? "Room" : room).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(skin.body(13, .bold))
            .foregroundStyle(skin.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(skin.inset, in: Capsule())
        }
    }
}
