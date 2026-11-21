import ChoreKit
import SwiftUI

/// Everything that used to hide in the avatar menu: who's using this phone,
/// Game mode and its options, Reagen's winnings, and the chore-list settings.
struct SettingsView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin
    @AppStorage("me") private var meRaw = ""
    @AppStorage(ArcadeLook.key) private var arcadeChoice = ""
    @State private var editingPrizes = false
    @State private var confirmingClear = false

    var game: Bool { store.state?.isGameMode ?? false }
    var canSetGame: Bool { HouseholdState.canSetGameMode(me) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        PersonBadge(person: me, size: 46)
                        TwoLineLabel(title: me.name, detail: usingText)
                        Spacer(minLength: 8)
                        Button("Switch") { meRaw = "" }
                            .buttonStyle(BlitzButtonStyle(kind: .quiet, height: 38, fill: false))
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(skin.card)

                if canSetGame || game {
                    Section {
                        if canSetGame {
                            Toggle(isOn: Binding(
                                get: { game },
                                set: { v in store.run { try $0.setGameMode(v, by: me) } })) {
                                TwoLineLabel(title: "Game mode", detail: "Arcade TV, XP, and loot chests for Reagen")
                            }
                        }
                        if game {
                            if canSetGame {
                                Toggle(isOn: Binding(
                                    get: { store.state?.isMusicOn ?? true },
                                    set: { v in store.run { try $0.setTVMusic(v, by: me) } })) {
                                    TwoLineLabel(title: "Music on the TV", detail: "Sound effects stay on either way")
                                }
                            }
                            Toggle(isOn: Binding(
                                get: { ArcadeLook.isOn(choice: arcadeChoice, me: me) },
                                set: { arcadeChoice = $0 ? "on" : "off" })) {
                                TwoLineLabel(title: "Arcade look on this \(deviceWord)")
                            }
                            if me.isParent {
                                Button { editingPrizes = true } label: {
                                    HStack {
                                        TwoLineLabel(title: "Prize pot", detail: potSummary)
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(skin.text2)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Game mode")
                    }
                    .listRowBackground(skin.card)
                    .tint(Palette.done)
                }

                if hasWinnings {
                    Section {
                        EarningsPanel(me: me)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        ForEach(recentSpins) { spin in
                            HStack(spacing: 12) {
                                Text(spin.prize.name).font(skin.body(16, .bold)).foregroundStyle(skin.text)
                                Spacer(minLength: 8)
                                Text(spin.at, format: .dateTime.month(.abbreviated).day())
                                    .font(skin.body(13)).foregroundStyle(skin.text2)
                                Text(spin.paidAt == nil ? "Owed" : "Paid")
                                    .font(skin.body(12, .heavy))
                                    .foregroundStyle(spin.paidAt == nil ? Palette.onAccent : skin.text2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(spin.paidAt == nil ? Palette.accent : skin.inset, in: Capsule())
                            }
                            .listRowBackground(skin.card)
                        }
                    } header: {
                        Text(me.isParent ? "Reagen's winnings" : "Your winnings")
                    }
                }

                if me.isParent {
                    Section {
                        Toggle(isOn: Binding(
                            get: { store.showTimes },
                            set: { v in store.run { try $0.setShowTimes(v, by: me) } })) {
                            TwoLineLabel(title: "Show chore times", detail: "The minutes next to each chore")
                        }
                        Button("Remove the starter chores", role: .destructive) { confirmingClear = true }
                            .font(skin.body(17, .bold))
                    } header: {
                        Text("Chores")
                    }
                    .listRowBackground(skin.card)
                    .tint(Palette.done)
                }
            }
            .skinnedList()
            .navigationTitle("Settings")
            .sheet(isPresented: $editingPrizes) { PrizePotView(me: me) }
            .confirmationDialog("Remove the 20 starter chores? Chores you added yourself stay.",
                                isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Remove starter chores", role: .destructive) {
                    store.run { try $0.removeStarterChores(by: me) }
                }
            }
        }
    }

    var hasWinnings: Bool {
        guard let s = store.state else { return false }
        return HouseholdState.spinners.contains { p in
            s.earnings(for: p).spins > 0 && (me == p || me.isParent)
        }
    }

    /// The latest few chests, newest first.
    var recentSpins: [Spin] {
        guard let s = store.state else { return [] }
        return Array(s.allSpins.filter { me.isParent || $0.person == me }.suffix(8).reversed())
    }

    var potSummary: String {
        let names = (store.state?.prizes ?? []).map(\.name)
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.first ?? "") to \(names.last ?? ""), \(names.count) prizes"
    }

    var usingText: String { "Using this \(deviceWord)" }
}

#if targetEnvironment(macCatalyst)
private let deviceWord = "Mac"
#else
private let deviceWord = "phone"
#endif
