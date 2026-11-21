import ChoreKit
import SwiftUI

extension Person {
    var color: Color {
        switch self {
        case .brandon: return Color(uiColor: Palette.hex(0x3B8CFF))
        case .kira: return Color(uiColor: Palette.hex(0xF0569A))
        case .braden: return Color(uiColor: Palette.hex(0x34C77B))
        case .reagen: return Color(uiColor: Palette.hex(0xFF9534))
        }
    }

    var initial: String { String(name.prefix(1)) }
}

struct PersonBadge: View {
    let person: Person
    var size: CGFloat = 28

    var body: some View {
        Text(person.initial)
            .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(person.color))
            .accessibilityLabel(person.name)
    }
}
