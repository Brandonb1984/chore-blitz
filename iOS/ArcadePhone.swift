import ChoreKit
import SwiftUI

// Game mode on the phone: the same original arcade look as the TV board,
// so finishing a chore feels like clearing a quest.

/// Purple pixel-grid background with a few dim twinkling stars.
struct ArcadePhoneBackground: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { ctx in
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .linearGradient(Gradient(colors: [Palette.arcadeTop, Palette.arcadeBottom]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                let cell: CGFloat = 24
                var grid = Path()
                var x: CGFloat = 0
                while x < size.width { grid.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += cell }
                var y: CGFloat = 0
                while y < size.height { grid.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += cell }
                g.fill(grid, with: .color(.white.opacity(0.035)))
                let tick = Int(ctx.date.timeIntervalSince1970 / 0.6)
                var rng = SeededRNG(seed: 7)
                for i in 0..<40 {
                    let px = (CGFloat.random(in: 0..<size.width, using: &rng) / 4).rounded() * 4
                    let py = (CGFloat.random(in: 0..<size.height, using: &rng) / 4).rounded() * 4
                    let on = (i + tick) % 4 != 0
                    g.fill(Path(CGRect(x: px, y: py, width: 3, height: 3)),
                           with: .color(.white.opacity(on ? 0.18 : 0.05)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A pixel burst with a floating "+N XP", shown over the whole screen.
struct PhoneBurst: Identifiable {
    let id = UUID()
    let start = Date()
    let label: String
    let seed = UInt64.random(in: 1...UInt64.max)
}

struct PhoneBurstLayer: View {
    let bursts: [PhoneBurst]

    var body: some View {
        GeometryReader { g in
            let origin = CGPoint(x: g.size.width / 2, y: g.size.height * 0.42)
            ForEach(bursts) { b in
                PixelBurst(origin: origin, start: b.start, count: 48, pixel: 9, seed: b.seed)
                FloatingLabel(text: b.label, origin: origin, start: b.start, size: 38)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
