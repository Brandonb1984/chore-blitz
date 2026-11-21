import SwiftUI

/// Chunky pixel particles that fly out and fall, for chore-done bursts.
struct PixelBurst: View {
    let origin: CGPoint
    let start: Date
    var count = 64
    var pixel: CGFloat = 16
    var colors: [Color] = [.yellow, .cyan, .mint, .pink, .orange, .white]
    var seed: UInt64 = 1

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, _ in
                let t = ctx.date.timeIntervalSince(start)
                guard t >= 0, t < 1.6 else { return }
                var rng = SeededRNG(seed: seed)
                for i in 0..<count {
                    let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                    let speed = Double.random(in: 220...620, using: &rng)
                    let x = origin.x + CGFloat(cos(angle) * speed * t)
                    let y = origin.y + CGFloat(sin(angle) * speed * t + 700 * t * t)
                    // Snap to a pixel grid for the retro look.
                    let sx = (x / pixel).rounded() * pixel
                    let sy = (y / pixel).rounded() * pixel
                    let fade = max(0, 1 - t / 1.6)
                    g.opacity = fade
                    g.fill(Path(CGRect(x: sx, y: sy, width: pixel, height: pixel)),
                           with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension PixelBurst {
    /// Gold-and-white palette for prize wins.
    static let gold: [Color] = [.yellow, .orange, .white, Color(red: 1, green: 0.84, blue: 0.2)]
}

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
