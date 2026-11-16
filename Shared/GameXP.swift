import ChoreKit
import SwiftUI

/// Family XP for the current list: one point per minute of finished chores.
func familyXP(_ blitz: Blitz) -> Int {
    blitz.tasks.filter { $0.doneAt != nil }.reduce(0) { $0 + max($1.minutes, 1) }
}

func level(forXP xp: Int) -> (level: Int, into: Int, needed: Int) {
    let per = 30
    return (xp / per + 1, xp % per, per)
}

struct FloatingLabel: View {
    let text: String
    let origin: CGPoint
    let start: Date
    var size: CGFloat = 64

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            if t >= 0 && t < 1.6 {
                Text(text)
                    .font(.system(size: size, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black, radius: 0, x: 5, y: 5)
                    .padding(.horizontal, 16)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    .opacity(1 - t / 1.6)
                    .position(x: origin.x, y: origin.y - CGFloat(t * 120))
            }
        }
    }
}

/// XP bar shown in the TV header in Game mode.
struct XPBar: View {
    let blitz: Blitz
    var size: CGFloat = 34

    var body: some View {
        let lv = level(forXP: familyXP(blitz))
        HStack(spacing: 16) {
            Text("LV \(lv.level)")
                .font(.system(size: size, weight: .black, design: .monospaced))
                .foregroundStyle(.yellow)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.12))
                    Rectangle().fill(LinearGradient(colors: [.cyan, .mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(lv.into) / CGFloat(lv.needed))
                        .animation(.easeOut(duration: 0.6), value: lv.into)
                }
                .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 3))
            }
            .frame(height: size * 0.76)
        }
    }
}
