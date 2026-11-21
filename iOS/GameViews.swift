import ChoreKit
import SwiftUI
import UIKit

/// Reagen's spin screen: spin the reels, win something from the prize pot.
struct SpinView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    @State private var result: Spin?
    @State private var spinStart = Date()
    @State private var spinning = false
    @State private var burstAt: Date?

    var spinsLeft: Int { store.state?.spinsLeft(for: me) ?? 0 }

    @State private var showingOdds = false

    /// What the big button says: open the first chest, open the next, or done.
    var buttonTitle: String {
        if spinning { return "OPENING…" }
        if spinsLeft == 0 { return "DONE" }
        if result == nil { return spinsLeft == 1 ? "OPEN" : "OPEN · \(spinsLeft) CHESTS" }
        return "OPEN NEXT · \(spinsLeft) LEFT"
    }

    var body: some View {
        ZStack {
            ArcadePhoneBackground()
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                    }
                    .accessibilityLabel("Close")
                }
                Text("LOOT CHEST")
                    .font(.system(size: 40, weight: .black, design: .monospaced))
                    .foregroundStyle(Arcade.yellow)
                    .shadow(color: .black.opacity(0.6), radius: 0, x: 3, y: 3)
                Spacer(minLength: 0)
                // Before opening the chest idles; then it bursts open with loot.
                LootChestView(start: result == nil ? .distantFuture : spinStart, prize: result?.prize, size: 280)
                Spacer(minLength: 0)
                Button {
                    if spinsLeft == 0 && !spinning { dismiss() } else { spin() }
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(red: 0.06, green: 0.02, blue: 0.14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Arcade.yellow))
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)).offset(x: 4, y: 5))
                }
                .buttonStyle(.plain)
                .disabled(spinning)
                Button(showingOdds ? "Hide the odds" : "What can I get?") {
                    withAnimation { showingOdds.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                if showingOdds, let pot = store.state?.prizes, !pot.isEmpty {
                    PrizeOdds(pot: pot)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            if let burstAt {
                GeometryReader { g in
                    // Gold pixel shower when the prize lands.
                    ForEach(0..<3, id: \.self) { i in
                        PixelBurst(origin: CGPoint(x: g.size.width * [0.2, 0.5, 0.8][i], y: g.size.height * 0.55),
                                   start: burstAt.addingTimeInterval(Double(i) * 0.1),
                                   count: 50, pixel: 10, colors: PixelBurst.gold, seed: UInt64(5 + i))
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if debugScreen == "spinGo" { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { spin() } }
        }
    }

    func spin() {
        spinning = true
        Task {
            var won: Spin?
            let ok = await store.apply { won = try $0.spin(by: me, roll: Double.random(in: 0..<1), now: .now) }
            guard ok, let won else { spinning = false; return }
            spinStart = Date()
            result = won
            let haptic = UISelectionFeedbackGenerator()
            for i in 0..<9 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.11) { haptic.selectionChanged() }
            }
            GameAudio.shared.lootSequence(big: store.state?.isJackpot(won.prize) ?? false)
            DispatchQueue.main.asyncAfter(deadline: .now() + LootTiming.open) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + LootTiming.land) {
                burstAt = Date()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                spinning = false
            }
        }
    }
}

/// Shows each prize and its chance, so the odds are out in the open.
struct PrizeOdds: View {
    let pot: [Prize]

    var body: some View {
        let total = max(pot.reduce(0) { $0 + $1.weight }, 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("Chance of each prize").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
            ForEach(pot) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text("\(Int((Double(p.weight) / Double(total) * 100).rounded()))%")
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
    }
}

/// Parents edit what's in the prize pot and how likely each prize is.
struct PrizePotView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State private var pot: [Prize] = []
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($pot) { $prize in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Prize", text: $prize.name)
                                .font(skin.body(18, .heavy))
                            Stepper(value: $prize.weight, in: 1...100) {
                                Text("\(percent(prize))% of chests")
                                    .font(skin.body(14))
                                    .foregroundStyle(skin.text2)
                            }
                        }
                    }
                    .onDelete { pot.remove(atOffsets: $0) }
                    HStack {
                        TextField("Add a prize, like 75¢", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Reagen earns a loot chest for each chore he finishes while Game mode is on, and bigger chores earn up to 3. Use + and − to make a prize more or less likely. Swipe left to remove one.")
                }
                .listRowBackground(skin.card)
            }
            .skinnedList()
            .navigationTitle("Prize pot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let p = pot
                        store.run { try $0.setPrizePot(p, by: me) }
                        dismiss()
                    }
                    .disabled(pot.isEmpty)
                }
            }
            .onAppear { pot = store.state?.prizes ?? Prize.starterPot }
        }
    }

    func add() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        pot.append(Prize(name: n, weight: 10))
        newName = ""
    }

    func percent(_ p: Prize) -> Int {
        let total = max(pot.reduce(0) { $0 + $1.weight }, 1)
        return Int((Double(p.weight) / Double(total) * 100).rounded())
    }
}

/// "2 loot chests! OPEN": shown on Today whenever Reagen has chests to open.
struct SpinBanner: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin
    @State private var showing = false

    var body: some View {
        let left = store.state?.spinsLeft(for: me) ?? 0
        // Keep the banner (and the chest screen hanging off it) alive while the
        // chest screen is up: opening the last chest drops `left` to 0, and
        // removing the banner then would tear the screen down mid-reveal.
        Group {
            if left > 0 || showing {
                Button { showing = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.fill")
                        Text(left == 1 ? "1 loot chest!" : "\(left) loot chests!")
                        Spacer(minLength: 8)
                        Text("OPEN")
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Palette.arcadeYellow, in: RoundedRectangle(cornerRadius: skin.buttonCorner, style: .continuous))
                    }
                    .font(.system(size: 17, weight: .black, design: skin.arcade ? .monospaced : .rounded))
                    .foregroundStyle(.white)
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [Color(uiColor: Palette.hex(0x8A3DFF)), Color(uiColor: Palette.hex(0xFF8A3D))],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: skin.corner, style: .continuous))
                    .shadow(color: .black.opacity(skin.arcade ? 0.5 : 0), radius: 0, x: 5, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { if debugScreen == "spin" || debugScreen == "spinGo" { showing = true } }
        .fullScreenCover(isPresented: $showing) { SpinView(me: me) }
    }
}
