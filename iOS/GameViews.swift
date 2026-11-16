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
    @State private var showPrize = false
    @State private var spinning = false

    var spinsLeft: Int { store.state?.spinsLeft(for: me) ?? 0 }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.02, blue: 0.14), Color(red: 0.2, green: 0.05, blue: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Text("PRIZE SPIN")
                    .font(.system(size: 40, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
                if let result {
                    SlotReels(start: spinStart, prizeName: result.prize.name, size: 90)
                    if showPrize {
                        Text(result.prize.name.uppercased())
                            .font(.system(size: 44, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .transition(.scale)
                    }
                } else {
                    SlotReels(start: .distantFuture, prizeName: "", size: 90)
                }
                Text("\(spinsLeft) spin\(spinsLeft == 1 ? "" : "s") left")
                    .font(.headline.monospaced())
                    .foregroundStyle(.white.opacity(0.8))
                Button(action: spin) {
                    Text(spinning ? "…" : "SPIN")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(spinning || spinsLeft == 0)
                Button("Close") { dismiss() }
                    .foregroundStyle(.white.opacity(0.8))
                if let pot = store.state?.prizes, !pot.isEmpty {
                    PrizeOdds(pot: pot)
                }
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
    }

    func spin() {
        spinning = true
        showPrize = false
        Task {
            var won: Spin?
            let ok = await store.apply { won = try $0.spin(by: me, roll: Double.random(in: 0..<1), now: .now) }
            guard ok, let won else { spinning = false; return }
            spinStart = Date()
            result = won
            let haptic = UISelectionFeedbackGenerator()
            for i in 0..<18 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.11) {
                    haptic.selectionChanged()
                    GameAudio.shared.tick()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(.spring) { showPrize = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                GameAudio.shared.win(big: won.prize.name.lowercased().contains("jackpot"))
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
            Text("Odds").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
            ForEach(pot) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text("\(Int((Double(p.weight) / Double(total) * 100).rounded()))%")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }
}

/// Parents edit what's in the prize pot and how likely each prize is.
struct PrizePotView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    @State private var pot: [Prize] = []
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($pot) { $prize in
                        VStack(alignment: .leading) {
                            TextField("Prize", text: $prize.name).font(.headline)
                            Stepper("Chance: \(percent(prize))%  (weight \(prize.weight))",
                                    value: $prize.weight, in: 1...100)
                                .font(.caption)
                        }
                    }
                    .onDelete { pot.remove(atOffsets: $0) }
                    HStack {
                        TextField("Add a prize, like \"Movie night\"", text: $newName)
                        Button {
                            let n = newName.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            pot.append(Prize(name: n, weight: 10))
                            newName = ""
                        } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .buttonStyle(.borderless)
                    }
                } footer: {
                    Text("Reagen gets one spin for each chore he finishes while Game mode is on. Higher weight means more likely.")
                }
            }
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
                }
            }
            .onAppear { pot = store.state?.prizes ?? Prize.starterPot }
        }
    }

    func percent(_ p: Prize) -> Int {
        let total = max(pot.reduce(0) { $0 + $1.weight }, 1)
        return Int((Double(p.weight) / Double(total) * 100).rounded())
    }
}

/// Spin button for Reagen, shown on Today when he has spins.
struct SpinBanner: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @State private var showing = false

    var body: some View {
        let left = store.state?.spinsLeft(for: me) ?? 0
        if left > 0 {
            Button { showing = true } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("You have \(left) prize spin\(left == 1 ? "" : "s")!")
                        .font(.headline.monospaced())
                    Spacer()
                    Text("SPIN").font(.headline.weight(.black))
                }
                .padding()
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 14).fill(
                    LinearGradient(colors: [.purple, .orange], startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showing) { SpinView(me: me) }
        }
    }
}

/// Unpaid spin winnings, for parents to mark paid.
struct WinningsSection: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore

    var body: some View {
        let unpaid = store.state?.unpaidSpins ?? []
        if !unpaid.isEmpty {
            Section("Prize spins won") {
                ForEach(unpaid) { spin in
                    HStack {
                        PersonBadge(person: spin.person)
                        Text(spin.prize.name).font(.headline)
                        Spacer()
                        if me.isParent {
                            Button("Paid") {
                                store.run { try $0.markSpinPaid(spin.id, by: me, now: .now) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                }
            }
        }
    }
}
