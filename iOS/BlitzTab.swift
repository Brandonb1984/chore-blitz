import ChoreKit
import UIKit
import SwiftUI

struct BlitzTab: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }
    @State private var showingStart = false
    @State private var editingList = false

    var body: some View {
        NavigationStack {
            Group {
                if let blitz = store.state?.runningBlitz {
                    RunningBlitzView(me: me, blitz: blitz)
                } else {
                    IdleView(me: me, lastBlitz: store.state?.blitz) { showingStart = true }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                if me.isParent, store.state?.runningBlitz != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit list") { editingList = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End", role: .destructive) {
                            store.run { try $0.endBlitz(by: me, now: .now) }
                        }
                    }
                }
            }
            .onAppear {
                if debugScreen == "start" { showingStart = true }
                if debugScreen == "edit" { editingList = true }
            }
            .sheet(isPresented: $showingStart) { StartBlitzView(me: me) }
            .sheet(isPresented: $editingList) { EditListView(me: me) }
        }
    }
}

struct IdleView: View {
    let me: Person
    let lastBlitz: Blitz?
    let start: () -> Void
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SpinBanner(me: me)
                EarningsCard(me: me)
                if let last = lastBlitz, last.isOver {
                    FinishedCard(me: me, blitz: last)
                }
                if me.isParent {
                    Button(action: start) {
                        Label("Make today's list", systemImage: "plus")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    if lastBlitz?.isOver == true {
                        Button("Clear the TV") { store.run { try $0.clearBlitz(by: me) } }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer").font(.system(size: 44))
                        Text("No chores going right now").font(.title3.bold())
                        Text("When Brandon or Kira starts some, they show up here.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                }
            }
            .padding()
        }
    }
}

struct FinishedCard: View {
    let me: Person
    let blitz: Blitz

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last time: \(blitz.tasks(in: .done).count) of \(blitz.tasks.count) done")
                .font(.headline)
            ForEach(blitz.allRewards, id: \.person) { reward in
                RewardRow(me: me, blitz: blitz, reward: reward)
            }
            ForEach(blitz.doneByPerson, id: \.person) { entry in
                HStack(alignment: .top) {
                    PersonBadge(person: entry.person)
                    Text(entry.tasks.map(\.name).joined(separator: ", "))
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.green.opacity(0.12)))
    }
}

struct RunningBlitzView: View {
    let me: Person
    let blitz: Blitz
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }
    @State private var selected: UUID?
    @AppStorage("seenHint") private var seenHint = false
    @State private var bursts: [PhoneBurst] = []
    @State private var knownLevel: Int?
    @State private var knownMyDone: Set<UUID>?

    /// Game mode turns the list into an arcade screen (see ArcadePhone.swift).
    var game: Bool { store.state?.isGameMode ?? false }
    var rowBackground: Color? { game ? Color.white.opacity(0.09) : nil }

    var mine: [BlitzTask] { blitz.tasks.filter { $0.claimedBy == me && $0.doneAt == nil } }
    var open: [BlitzTask] { blitz.tasks(in: .open) }
    var others: [BlitzTask] { blitz.tasks(in: .inProgress).filter { $0.claimedBy != me } }
    var done: [BlitzTask] { blitz.tasks(in: .done) }

    var body: some View {
        List {
            if !seenHint {
                Section {
                    HStack(alignment: .top) {
                        Image(systemName: "hand.tap.fill").foregroundStyle(Color.accentColor)
                        Text("Tap **Claim** to take a chore, then **Done** when it's finished. Tap a chore's name to see how to do it.")
                            .font(.subheadline)
                        Spacer()
                        Button { seenHint = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless)
                    }
                }
            }
            if game {
                Section {
                    XPBar(blitz: blitz, size: 18)
                        .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
            }
            Section {
                if blitz.hasTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = blitz.remaining(at: ctx.date) ?? 0
                        HStack {
                            Text(countdownText(left))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(left > 0 ? Color.primary : Color.red)
                            Spacer()
                            Text("\(done.count) of \(blitz.tasks.count) done")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Text("\(done.count) of \(blitz.tasks.count) done").font(.title2.bold())
                        Spacer()
                    }
                }
                ForEach(blitz.allRewards, id: \.person) { reward in
                    RewardRow(me: me, blitz: blitz, reward: reward)
                }
                SpinBanner(me: me)
            }
            .listRowBackground(rowBackground)
            WinningsSection(me: me)
            if !mine.isEmpty {
                Section {
                    ForEach(mine) { row($0) }.listRowBackground(rowBackground)
                } header: { header("Your chores", arcade: "Your quests") }
            }
            Section {
                ForEach(open) { row($0) }.listRowBackground(rowBackground)
            } header: {
                header(open.isEmpty ? "Nothing left to grab" : "Up for grabs",
                       arcade: open.isEmpty ? "All quests taken" : "Quests up for grabs")
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { row($0) }.listRowBackground(rowBackground)
                } header: { header("Others are on it", arcade: "Party members on it") }
            }
            if !done.isEmpty {
                Section {
                    ForEach(done) { row($0) }.listRowBackground(rowBackground)
                } header: { header("Done", arcade: "Cleared") }
            }
        }
        .scrollContentBackground(game ? .hidden : .automatic)
        .background { if game { ArcadePhoneBackground() } }
        .preferredColorScheme(game ? .dark : nil)
        .overlay { if game { PhoneBurstLayer(bursts: bursts) } }
        .onChange(of: Set(blitz.tasks.filter { $0.doneAt != nil && $0.claimedBy == me }.map(\.id)), initial: true) { _, now in
            // One of my chores just got finished (here or on its detail screen).
            if game, let known = knownMyDone {
                for id in now.subtracting(known) {
                    let minutes = blitz.tasks.first { $0.id == id }?.minutes ?? 1
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    GameAudio.shared.kaching()
                    GameAudio.shared.gem()
                    celebrate("+\(max(minutes, 1)) XP")
                }
            }
            knownMyDone = now
        }
        .onChange(of: level(forXP: familyXP(blitz)).level, initial: true) { _, lv in
            // Level-up fanfare when the family XP bar fills.
            if game, let known = knownLevel, lv > known {
                GameAudio.shared.levelUp()
                celebrate("LEVEL \(lv)!")
            }
            knownLevel = lv
        }
        .onAppear {
            if debugScreen == "detail" { selected = (mine.first ?? open.first)?.id }
        }
        .navigationDestination(item: $selected) { id in
            TaskDetailView(me: me, taskID: id)
        }
    }

    @ViewBuilder
    func header(_ normal: String, arcade: String) -> some View {
        if game { ArcadeHeader(text: arcade) } else { Text(normal) }
    }

    func celebrate(_ label: String) {
        let b = PhoneBurst(label: label)
        bursts.append(b)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { bursts.removeAll { $0.id == b.id } }
    }

    func row(_ task: BlitzTask) -> some View {
        HStack {
            Button { selected = task.id } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name).strikethrough(task.doneAt != nil)
                        Text(showTimes ? "\(task.room) · \(task.minutes) min" : task.room)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let who = task.claimedBy { PersonBadge(person: who) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            if task.column == .open {
                Button("Claim") { store.run { try $0.claim(taskID: task.id, by: me) } }
                    .buttonStyle(.borderedProminent)
            } else if task.column == .inProgress && (task.claimedBy == me || me.isParent) {
                Button("Done") {
                    store.run { try $0.markDone(taskID: task.id, by: me, now: .now) }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
    }
}

/// The how-to for one chore, with Claim and Done.
struct TaskDetailView: View {
    let me: Person
    let taskID: UUID
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }
    @State private var checked: Set<Int> = []

    var task: BlitzTask? { store.state?.blitz?.tasks.first { $0.id == taskID } }

    var body: some View {
        if let task {
            List {
                Section {
                    HStack {
                        Text(showTimes ? "\(task.room) · about \(task.minutes) min" : task.room)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let who = task.claimedBy {
                            PersonBadge(person: who)
                            Text(who == me ? "You" : who.name)
                        }
                    }
                }
                Section("How to do it") {
                    ForEach(Array(task.steps.enumerated()), id: \.offset) { i, step in
                        Button {
                            if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: checked.contains(i) ? "checkmark.circle.fill" : "\(i + 1).circle")
                                    .foregroundStyle(checked.contains(i) ? Color.green : Color.accentColor)
                                    .font(.title3)
                                Text(step).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                Section { actions(task) }
            }
            .navigationTitle(task.name)
        } else {
            Text("This chore isn't in the blitz anymore.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func actions(_ task: BlitzTask) -> some View {
        let canAct = task.claimedBy == nil || task.claimedBy == me || me.isParent
        switch task.column {
        case .open:
            Button("Claim this chore") { store.run { try $0.claim(taskID: taskID, by: me) } }
                .font(.headline)
            Button("Mark done") { store.run { try $0.markDone(taskID: taskID, by: me, now: .now) } }
        case .inProgress:
            if canAct {
                Button("Mark done") { store.run { try $0.markDone(taskID: taskID, by: me, now: .now) } }
                    .font(.headline)
                Button("Give it back", role: .destructive) {
                    store.run { try $0.unclaim(taskID: taskID, by: me) }
                }
            } else {
                Text("\(task.claimedBy!.name) is on this one.").foregroundStyle(.secondary)
            }
        case .done:
            Label("Done", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            if canAct {
                Button("Not done yet") { store.run { try $0.markNotDone(taskID: taskID, by: me) } }
            }
        }
    }
}

/// Shows a reward's progress. Parents get "Mark paid" once it's earned.
struct RewardRow: View {
    let me: Person
    let blitz: Blitz
    let reward: Reward
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }

    var body: some View {
        let mine = blitz.assignedTasks(for: reward.person)
        let done = mine.filter { $0.doneAt != nil }.count
        let earned = blitz.hasEarned(reward)
        let who = reward.person == me ? "You" : reward.person.name
        HStack(spacing: 12) {
            PersonBadge(person: reward.person)
            VStack(alignment: .leading, spacing: 2) {
                if earned {
                    Text(reward.paidAt != nil ? "\(who) earned \(reward.prize) · paid" : "\(who) earned \(reward.prize)!")
                        .font(.headline)
                } else {
                    Text(reward.person == me
                         ? "Finish your \(mine.count) chores to earn \(reward.prize)"
                         : "\(reward.person.name): finish \(mine.count) chores for \(reward.prize)")
                        .font(.headline)
                    ProgressView(value: Double(done), total: Double(max(mine.count, 1)))
                        .tint(reward.person.color)
                }
            }
            Spacer()
            if earned && reward.paidAt == nil && me.isParent {
                Button("Mark paid") {
                    store.run { try $0.markRewardPaid(for: reward.person, by: me, now: .now) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
