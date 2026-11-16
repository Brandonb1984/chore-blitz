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

/// Three slot reels of original pixel-ish symbols that spin, then land.
struct SlotReels: View {
    let start: Date
    let prizeName: String
    var size: CGFloat = 120
    var duration: Double = 2.4

    static let symbols = ["star.fill", "diamond.fill", "dollarsign.circle.fill", "crown.fill", "bolt.fill", "heart.fill"]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            HStack(spacing: size * 0.15) {
                ForEach(0..<3, id: \.self) { reel in
                    let stopAt = duration * (0.55 + 0.2 * Double(reel))
                    let idle = t < 0
                    let spinning = !idle && t < stopAt
                    let idx = idle ? reel : (spinning ? Int(t * 18 + Double(reel) * 3) % Self.symbols.count : landed(reel))
                    Image(systemName: Self.symbols[idx])
                        .font(.system(size: size * 0.55, weight: .black))
                        .foregroundStyle(spinning ? Color.white.opacity(0.7) : Color.yellow)
                        .frame(width: size, height: size * 1.2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow, lineWidth: 4))
                        .offset(y: spinning ? CGFloat(sin(t * 40 + Double(reel))) * 6 : 0)
                }
            }
        }
    }

    /// Big prizes land on three crowns; everything else on a matching row too.
    func landed(_ reel: Int) -> Int {
        let lower = prizeName.lowercased()
        if lower.contains("jackpot") || lower.contains("20") { return 3 }
        if lower.contains("$") || lower.contains("¢") || lower.contains("cent") { return 2 }
        return abs(prizeName.hashValue) % 2 == 0 ? 0 : 1
    }
}
