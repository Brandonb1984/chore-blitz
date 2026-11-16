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

/// Pixel bursts, ka-ching, level-ups and spin reveals on the TV when Game
/// mode is on. Watches the shared state and reacts to what changed.
struct GameLayer: View {
    let state: HouseholdState
    @State private var knownDone: Set<UUID>?
    @State private var knownSpins: Set<UUID>?
    @State private var knownLevel = 0
    @State private var bursts: [BurstEvent] = []
    @State private var banner: String?
    @State private var reveal: Spin?
    @State private var revealStart = Date()

    struct BurstEvent: Identifiable {
        let id = UUID()
        let origin: CGPoint
        let start: Date
        let seed: UInt64
        let label: String
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bursts) { b in
                    PixelBurst(origin: b.origin, start: b.start, seed: b.seed)
                    FloatingLabel(text: b.label, origin: b.origin, start: b.start)
                }
                if let banner {
                    Text(banner)
                        .font(.system(size: 120, weight: .black, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .shadow(color: .orange, radius: 0, x: 8, y: 8)
                        .transition(.scale.combined(with: .opacity))
                }
                if reveal != nil {
                    // Darken the board so the spin reads from across the room.
                    Color.black.opacity(0.65).ignoresSafeArea().transition(.opacity)
                }
                if let reveal {
                    VStack(spacing: 30) {
                        Text("\(reveal.person.name.uppercased()) SPINS!")
                            .font(.system(size: 64, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        SlotReels(start: revealStart, prizeName: reveal.prize.name, size: 160)
                        TimelineView(.periodic(from: revealStart, by: 0.25)) { ctx in
                            if ctx.date.timeIntervalSince(revealStart) > 2.5 {
                                Text(reveal.prize.name.uppercased())
                                    .font(.system(size: 96, weight: .black, design: .monospaced))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                    .padding(60)
                    .frame(minHeight: 620)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.12, green: 0.04, blue: 0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow, lineWidth: 6))
                    .transition(.scale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: state, initial: true) { _, new in react(to: new, size: geo.size) }
        }
        .allowsHitTesting(false)
    }

    func react(to s: HouseholdState, size: CGSize) {
        let blitz = s.blitz
        let done = Set(blitz?.tasks.filter { $0.doneAt != nil }.map(\.id) ?? [])
        let spins = Set(s.allSpins.map(\.id))
        defer { knownDone = done; knownSpins = spins }
        // First load: remember what's there, don't celebrate old stuff.
        guard let oldDone = knownDone, let oldSpins = knownSpins else {
            if let b = blitz { knownLevel = level(forXP: familyXP(b)).level }
            return
        }
        guard s.isGameMode else { return }

        let newlyDone = done.subtracting(oldDone)
        for (i, id) in newlyDone.enumerated() {
            let task = blitz?.tasks.first { $0.id == id }
            // Burst over the Done column, where the finished chore lands.
            let origin = CGPoint(x: size.width * CGFloat.random(in: 0.72...0.84),
                                 y: size.height * CGFloat.random(in: 0.45...0.6))
            let label = "+\(max(task?.minutes ?? 1, 1)) XP"
            bursts.append(BurstEvent(origin: origin, start: Date().addingTimeInterval(Double(i) * 0.3),
                                     seed: UInt64.random(in: 1...UInt64.max), label: label))
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                GameAudio.shared.kaching()
                GameAudio.shared.gem()
            }
        }
        if !newlyDone.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                bursts.removeAll { Date().timeIntervalSince($0.start) > 2 }
            }
        }
        if let b = blitz {
            let lv = level(forXP: familyXP(b)).level
            if lv > knownLevel && !newlyDone.isEmpty {
                show(banner: "LEVEL \(lv)!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { GameAudio.shared.levelUp() }
            }
            knownLevel = lv
        }

        if let newest = s.allSpins.last(where: { !oldSpins.contains($0.id) }) {
            revealStart = Date()
            withAnimation(.spring) { reveal = newest }
            for i in 0..<20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) { GameAudio.shared.tick() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                GameAudio.shared.win(big: newest.prize.name.lowercased().contains("jackpot"))
                bursts.append(BurstEvent(origin: CGPoint(x: size.width / 2, y: size.height / 2),
                                         start: Date(), seed: 7, label: newest.prize.name))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                withAnimation { if reveal?.id == newest.id { reveal = nil } }
            }
        }
    }

    func show(banner text: String) {
        withAnimation(.spring) { banner = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { banner = nil } }
    }
}

struct FloatingLabel: View {
    let text: String
    let origin: CGPoint
    let start: Date

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            if t >= 0 && t < 1.6 {
                Text(text)
                    .font(.system(size: 64, weight: .black, design: .monospaced))
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

    var body: some View {
        let lv = level(forXP: familyXP(blitz))
        HStack(spacing: 16) {
            Text("LV \(lv.level)")
                .font(.system(size: 34, weight: .black, design: .monospaced))
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
            .frame(height: 26)
        }
    }
}
