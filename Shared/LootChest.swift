import ChoreKit
import SwiftUI

// Prize reveal for Game mode: an original pixel-art treasure chest that
// rattles, bursts open with light beams, throws out chore-themed pixel loot
// (coins, gems, stars, a broom, a sponge) and rolls a coin counter up to the
// prize. All art here is drawn from the little sprite grids below.

enum Arcade {
    static let yellow = Color(red: 1.00, green: 0.88, blue: 0.30)   // #FFE14D
    static let cyan = Color(red: 0.24, green: 0.88, blue: 1.00)     // #3DE0FF
    static let mint = Color(red: 0.36, green: 1.00, blue: 0.76)     // #5DFFC1
    static let pink = Color(red: 0.94, green: 0.34, blue: 0.60)     // #F0569A
}

enum LootTiming {
    /// The chest rattles until it pops open here.
    static let open: Double = 1.0
    /// The counter rolls from `open` to here, then the prize lands.
    static let land: Double = 2.8
    /// Loot keeps flying for this long after opening.
    static let lootLife: Double = 2.6
}

// MARK: Sprites

private struct Sprite {
    let rows: [String]
    var width: Int { rows.first?.count ?? 0 }
    var height: Int { rows.count }
}

private enum Pal {
    static func color(_ c: Character) -> Color? {
        switch c {
        case "K": return Color(red: 0.10, green: 0.05, blue: 0.18)   // outline
        case "W": return Color(red: 0.42, green: 0.25, blue: 0.83)   // chest violet #6B3FD4
        case "w": return Color(red: 0.29, green: 0.16, blue: 0.62)   // dark violet
        case "G": return Color(red: 1.00, green: 0.80, blue: 0.22)   // gold
        case "g": return Color(red: 0.82, green: 0.56, blue: 0.10)   // dark gold
        case "Y": return Color(red: 1.00, green: 0.96, blue: 0.62)   // shine
        case "T": return Color(red: 1.00, green: 0.78, blue: 0.24)   // gold trim #FFC83D
        case "t": return Color(red: 0.79, green: 0.56, blue: 0.12)   // dark trim
        case "C": return Color(red: 0.24, green: 0.88, blue: 1.00)   // gem #3DE0FF
        case "c": return Color(red: 0.15, green: 0.50, blue: 0.85)   // dark gem
        case "L": return Color(red: 0.85, green: 0.97, blue: 1.00)   // gem shine
        case "B": return Color(red: 0.55, green: 0.33, blue: 0.16)   // broom handle
        case "S": return Color(red: 0.98, green: 0.78, blue: 0.30)   // straw / sponge
        case "s": return Color(red: 0.84, green: 0.60, blue: 0.18)   // dark straw
        case "N": return Color(red: 0.30, green: 0.75, blue: 0.40)   // scrub pad
        case "P": return Color(red: 0.94, green: 0.34, blue: 0.60)   // pink #F0569A
        default: return nil
        }
    }
}

private enum Sprites {
    static let lid = Sprite(rows: [
        "..KKKKKKKKKKKK..",
        ".KTTTTTTTTTTTTK.",
        "KTTWWWWGGWWWWTTK",
        "KTWWWWWGGWWWWWTK",
        "KtwwwwwGGwwwwwtK",
        "KKKKKKKKKKKKKKKK",
    ])
    static let body = Sprite(rows: [
        "KTWWWWWWWWWWWWTK",
        "KTWWWWGGGGWWWWTK",
        "KtWWWWGCCGWWWWtK",
        "KtwwwwGggGwwwwtK",
        "KTWWWWWGGWWWWWTK",
        "KTWWWWWWWWWWWWTK",
        "KtwwwwwwwwwwwwtK",
        "KTTTTTTTTTTTTTTK",
        "KKKKKKKKKKKKKKKK",
    ])
    static let coin = Sprite(rows: [
        "..KKKK..",
        ".KGGGGK.",
        "KGYGGgGK",
        "KGYGGgGK",
        "KGGGGgGK",
        "KGGGggGK",
        ".KggggK.",
        "..KKKK..",
    ])
    static let gem = Sprite(rows: [
        "...KK...",
        "..KLCK..",
        ".KLCCcK.",
        "KLCCCCcK",
        "KCCCCccK",
        ".KCCccK.",
        "..KccK..",
        "...KK...",
    ])
    static let star = Sprite(rows: [
        "...KK...",
        "..KYGK..",
        "KKKYGKKK",
        "KYYYGGGK",
        ".KYYGGK.",
        ".KYGKGK.",
        "KGK..KGK",
        "KK....KK",
    ])
    static let pinkStar = Sprite(rows: [
        "...KK...",
        "..KPPK..",
        "KKKPPKKK",
        "KPPPPPPK",
        ".KPPPPK.",
        ".KPPKPK.",
        "KPK..KPK",
        "KK....KK",
    ])
    static let broom = Sprite(rows: [
        "......KK",
        ".....KBK",
        "....KBK.",
        "...KBK..",
        "..KKKK..",
        ".KSSSSK.",
        "KSSsSsK.",
        "KSsSsSK.",
    ])
    static let sponge = Sprite(rows: [
        "........",
        "KKKKKKKK",
        "KNNNNNNK",
        "KNNNNNNK",
        "KSSSSSSK",
        "KSsSSsSK",
        "KSSSSSSK",
        "KKKKKKKK",
    ])
    static let loot: [Sprite] = [coin, gem, star, coin, broom, coin, sponge, pinkStar, coin, gem]
}

private extension GraphicsContext {
    /// Draws a sprite with its top-left at `origin`, `p` points per pixel.
    func draw(_ s: Sprite, at origin: CGPoint, pixel p: CGFloat) {
        for (y, row) in s.rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = Pal.color(ch) else { continue }
                fill(Path(CGRect(x: origin.x + CGFloat(x) * p, y: origin.y + CGFloat(y) * p,
                                 width: p + 0.5, height: p + 0.5)), with: .color(c))
            }
        }
    }
}

// MARK: View

/// The chest, its beams and its loot, plus the rolling prize counter.
/// `start` is when the opening begins; before that the chest idles (bobs).
struct LootChestView: View {
    let start: Date
    let prize: Prize?
    var size: CGFloat = 300
    var showCounter = true

    var big: Bool { prize?.name.lowercased().contains("jackpot") ?? false }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            VStack(spacing: 0) {
                Canvas { g, sz in draw(g, sz, t: t) }
                    .frame(width: size * 1.2, height: size * 1.1)
                if showCounter { counter(t: t) }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Counter

    @ViewBuilder
    func counter(t: Double) -> some View {
        let target = prize?.cents ?? 0
        let landed = t >= LootTiming.land
        let k = min(max((t - LootTiming.open) / (LootTiming.land - LootTiming.open), 0), 1)
        let eased = 1 - pow(1 - k, 3)
        let shown = landed ? target : Int((Double(target) * eased).rounded(.down))
        let pop = landed ? max(1, 1.3 - (t - LootTiming.land) * 0.9) : 1
        // Rolls up in cents ("5¢ … 25¢"), dollars once it passes $1.
        Text(t < LootTiming.open ? "?" : Prize.format(cents: shown))
            .font(.system(size: size * 0.24, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(landed && big ? Arcade.yellow : Color.white)
            .shadow(color: .black.opacity(0.7), radius: 0, x: size * 0.012, y: size * 0.012)
            .scaleEffect(pop)
            .opacity(t < 0 ? 0.3 : 1)
        if landed, big {
            Text("JACKPOT!")
                .font(.system(size: size * 0.11, weight: .black, design: .monospaced))
                .foregroundStyle(Arcade.yellow)
                .shadow(color: Arcade.pink, radius: 0, x: size * 0.01, y: size * 0.01)
                .scaleEffect(max(1, 1.3 - (t - LootTiming.land) * 0.6))
        }
    }

    // MARK: Scene

    func draw(_ g: GraphicsContext, _ sz: CGSize, t: Double) {
        let S = min(sz.width, sz.height)
        let p = S / 26                      // one chest pixel
        let chestW = 16 * p
        let mouth = CGPoint(x: sz.width / 2, y: sz.height - 10 * p)
        let opened = t >= LootTiming.open
        let since = t - LootTiming.open     // time since the lid popped

        // Glow under everything.
        let glow = opened ? min(1, since * 3) * (0.75 + 0.25 * sin(t * 6)) : (t > 0 ? 0.25 * t : 0.12)
        g.fill(Path(ellipseIn: CGRect(x: mouth.x - S * 0.42, y: mouth.y - S * 0.30, width: S * 0.84, height: S * 0.6)),
               with: .radialGradient(Gradient(colors: [Color.yellow.opacity(0.55 * glow), .clear]),
                                     center: mouth, startRadius: 0, endRadius: S * 0.42))

        // Light beams fanning up from the open chest.
        if opened {
            let beamColors: [Color] = big
                ? [Arcade.yellow, Arcade.pink, Arcade.cyan, Arcade.mint, .orange]
                : [Arcade.yellow, Arcade.cyan, Arcade.pink]
            let grow = min(1, since * 2.5)
            for (i, c) in beamColors.enumerated() {
                let n = Double(beamColors.count)
                let base = (Double(i) - (n - 1) / 2) * (big ? 0.32 : 0.42)
                let a = base + sin(t * 1.3 + Double(i)) * 0.06 - .pi / 2
                let len = Double(mouth.y) * 1.05 * grow
                let half = 0.12
                var beam = Path()
                beam.move(to: CGPoint(x: mouth.x - p * 2, y: mouth.y))
                beam.addLine(to: CGPoint(x: mouth.x + cos(a - half) * len, y: mouth.y + sin(a - half) * len))
                beam.addLine(to: CGPoint(x: mouth.x + cos(a + half) * len, y: mouth.y + sin(a + half) * len))
                beam.addLine(to: CGPoint(x: mouth.x + p * 2, y: mouth.y))
                beam.closeSubpath()
                g.fill(beam, with: .linearGradient(Gradient(colors: [c.opacity(0.8), c.opacity(0.35), c.opacity(0)]),
                                                   startPoint: mouth,
                                                   endPoint: CGPoint(x: mouth.x + cos(a) * len, y: mouth.y + sin(a) * len)))
            }
            // Expanding pixel sparkle rings.
            for r in 0..<2 {
                let k = (since * 0.9 + Double(r) * 0.5).truncatingRemainder(dividingBy: 1)
                let rad = S * 0.12 + S * 0.4 * k
                for j in 0..<16 {
                    let ang = Double(j) / 16 * 2 * .pi + since * 0.8
                    let pt = CGPoint(x: mouth.x + cos(ang) * rad, y: mouth.y - S * 0.12 + sin(ang) * rad * 0.45)
                    g.fill(Path(CGRect(x: pt.x - p * 0.4, y: pt.y - p * 0.4, width: p * 0.8, height: p * 0.8)),
                           with: .color(.white.opacity(0.8 * (1 - k))))
                }
            }
        }

        // Loot flying out and falling back with gravity.
        if opened {
            var rng = SeededRNG(seed: big ? 77 : 31)
            let count = big ? 40 : 24
            for i in 0..<count {
                let delay = Double(i) * (big ? 0.035 : 0.05)
                let lt = since - delay
                let speed = Double.random(in: 0.95...1.45, using: &rng)
                let angle = Double.random(in: -0.62...0.62, using: &rng) - .pi / 2
                let spin = Double.random(in: -1...1, using: &rng)
                guard lt > 0, lt < LootTiming.lootLife else { continue }
                let v = Double(mouth.y) * 1.25 * speed
                let x = Double(mouth.x) + cos(angle) * v * lt
                let y = Double(mouth.y) + sin(angle) * v * lt + Double(mouth.y) * 0.8 * lt * lt
                let sprite = Sprites.loot[i % Sprites.loot.count]
                let scale = min(1, lt * 5) * (1 - max(0, lt - 1.8) / 0.8)
                let lp = p * 0.85 * CGFloat(scale)
                guard lp > 0.2 else { continue }
                var lg = g
                lg.translateBy(x: x, y: y)
                lg.rotate(by: .radians(spin * lt * 4))
                lg.draw(sprite, at: CGPoint(x: -CGFloat(sprite.width) * lp / 2, y: -CGFloat(sprite.height) * lp / 2), pixel: lp)
            }
        }

        // The chest itself: rattles, then the lid pops up and tips back.
        let rattle = t > 0 && !opened ? sin(t * 70) * Double(p) * 0.5 * min(1, t / LootTiming.open + 0.2) : 0
        let bob = t < 0 ? sin(Date().timeIntervalSinceReferenceDate * 2.5) * Double(p) * 0.4 : 0
        let bodyOrigin = CGPoint(x: sz.width / 2 - chestW / 2 + rattle, y: mouth.y + bob)
        g.draw(Sprites.body, at: bodyOrigin, pixel: p)
        var lid = g
        let lidPivot = CGPoint(x: bodyOrigin.x + chestW / 2, y: bodyOrigin.y)
        lid.translateBy(x: lidPivot.x, y: lidPivot.y)
        if opened {
            let pop = min(1, since * 6)
            lid.translateBy(x: 0, y: -p * 5 * pop)
            lid.rotate(by: .degrees(-18 * pop))
        } else if t > 0 {
            // The lid jumps a little on each rattle.
            lid.translateBy(x: 0, y: -abs(sin(t * 35)) * p * 0.8)
        }
        lid.draw(Sprites.lid, at: CGPoint(x: -chestW / 2, y: -6 * p), pixel: p)

        // White flash when it pops.
        if opened && since < 0.3 {
            let a = 0.85 * (1 - since / 0.3)
            g.fill(Path(ellipseIn: CGRect(x: mouth.x - S * 0.6, y: mouth.y - S * 0.6, width: S * 1.2, height: S * 1.2)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(a), .clear]),
                                         center: mouth, startRadius: 0, endRadius: S * 0.6))
        }
    }
}

extension GameAudio {
    /// Sound for a chest opening: rattles, a pop, counter ticks, then the win.
    func lootSequence(big: Bool) {
        for i in 0..<9 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.11) { self.tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + LootTiming.open) { self.kaching(); self.gem() }
        let ticks = Int((LootTiming.land - LootTiming.open - 0.1) / 0.09)
        for i in 0..<ticks {
            DispatchQueue.main.asyncAfter(deadline: .now() + LootTiming.open + 0.1 + Double(i) * 0.09) { self.tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + LootTiming.land) { self.win(big: big) }
    }
}
