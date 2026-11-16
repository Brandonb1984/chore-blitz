import ChoreKit
import SwiftUI

extension Person {
    var color: Color {
        switch self {
        case .brandon: return .blue
        case .kira: return .pink
        case .braden: return .green
        case .reagen: return .orange
        }
    }

    var initial: String { String(name.prefix(1)) }
}

struct PersonBadge: View {
    let person: Person
    var size: CGFloat = 28

    var body: some View {
        Text(person.initial)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(person.color))
            .accessibilityLabel(person.name)
    }
}
