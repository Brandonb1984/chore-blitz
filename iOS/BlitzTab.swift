import ChoreKit
import UIKit
import SwiftUI

struct BlitzTab: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @State private var showingStart = false
    @State private var editingList = false
    @State private var confirmingEnd = false
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let blitz = store.state?.runningBlitz {
                    RunningBlitzView(me: me, blitz: blitz,
                                     editList: { editingList = true }, end: { confirmingEnd = true })
                } else {
                    IdleView(me: me, lastBlitz: store.state?.blitz) { showingStart = true }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                TaskDetailView(me: me, taskID: id)
            }
            .onAppear {
                if debugScreen == "start" { showingStart = true }
                if debugScreen == "edit" { editingList = true }
                if debugScreen == "detail", let blitz = store.state?.runningBlitz {
                    let mine = blitz.tasks.first { $0.claimedBy == me && $0.doneAt == nil }
                    if let task = mine ?? blitz.tasks(in: .open).first { path = [task.id] }
                }
            }
            .sheet(isPresented: $showingStart) { StartBlitzView(me: me) }
            .sheet(isPresented: $editingList) { EditListView(me: me) }
            .confirmationDialog("End today's list?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End the list", role: .destructive) {
                    store.run { try $0.endBlitz(by: me, now: .now) }
                }
            } message: {
                Text("Chores that aren't done stay unfinished, and the TV shows the results.")
            }
        }
    }
}

/// Small rounded button for the title row ("Edit", "End").
struct ChipButtonStyle: ButtonStyle {
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        Face(danger: danger, pressed: configuration.isPressed, label: configuration.label)
    }

    private struct Face<Label: View>: View {
        @Environment(\.skin) private var skin
        let danger: Bool
        let pressed: Bool
        let label: Label

        var body: some View {
            label
                .font(skin.body(15, .heavy))
                .foregroundStyle(danger ? Palette.danger : skin.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(skin.card, in: Capsule())
                .opacity(pressed ? 0.6 : 1)
        }
    }
}

// MARK: Nothing running

struct IdleView: View {
    let me: Person
    let lastBlitz: Blitz?
    let start: () -> Void
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin

    var body: some View {
        Page(title: "Today") {
            PersonBadge(person: me, size: 36)
        } content: {
            SpinBanner(me: me)
            if me.isParent {
                Button(action: start) {
                    Label("Make today's list", systemImage: "plus")
                }
                .buttonStyle(BlitzButtonStyle(kind: .accent, height: 58))
                .padding(.top, 4)
            } else if lastBlitz?.isOver != true {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(skin.text2)
                    Text("Nothing to do right now").font(skin.title(20))
                    Text("When Brandon or Kira starts a list, it shows up here.")
                        .font(skin.body(15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(skin.text2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .cardBox()
            }
            EarningsPanel(me: me)
            if let last = lastBlitz, last.isOver {
                SectionLabel(text: "Last time")
                LastTimeCard(me: me, blitz: last)
                if me.isParent {
                    Button("Clear the TV") { store.run { try $0.clearBlitz(by: me) } }
                        .buttonStyle(BlitzButtonStyle(kind: .quiet, height: 46))
                }
            }
        }
    }
}

/// How the last list went: the count, the colored bar, and who did what.
struct LastTimeCard: View {
    let me: Person
    let blitz: Blitz
    @Environment(\.skin) private var skin

    var body: some View {
        let done = blitz.tasks(in: .done).count
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                (Text("\(done)").font(skin.title(30))
                    + Text(" of \(blitz.tasks.count) done").font(skin.body(16, .bold)).foregroundColor(skin.text2))
                SegmentedProgress(tasks: blitz.tasks, track: skin.inset)
                ForEach(blitz.doneByPerson, id: \.person) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        PersonBadge(person: entry.person, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.person == me ? "You" : entry.person.name) · \(entry.tasks.count)")
                                .font(skin.body(16, .heavy))
                            Text(entry.tasks.map(\.name).joined(separator: ", "))
                                .font(skin.body(14))
                                .foregroundStyle(skin.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .cardBox()
            ForEach(blitz.allRewards, id: \.person) { reward in
                RewardCard(me: me, blitz: blitz, reward: reward)
            }
        }
    }
}

// MARK: A list is running

struct RunningBlitzView: View {
    let me: Person
    let blitz: Blitz
    let editList: () -> Void
    let end: () -> Void
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin
    @State private var bursts: [PhoneBurst] = []
    @State private var knownLevel: Int?
    @State private var knownMyDone: Set<UUID>?

    var game: Bool { store.state?.isGameMode ?? false }

    var mine: [BlitzTask] { blitz.tasks.filter { $0.claimedBy == me && $0.doneAt == nil } }
    var open: [BlitzTask] { blitz.tasks(in: .open) }
    var others: [BlitzTask] { blitz.tasks(in: .inProgress).filter { $0.claimedBy != me } }
    var done: [BlitzTask] { blitz.tasks(in: .done) }

    var body: some View {
        Page(title: "Today") {
            if me.isParent {
                Button("Edit", action: editList).buttonStyle(ChipButtonStyle())
                Button("End", action: end).buttonStyle(ChipButtonStyle(danger: true))
            }
            PersonBadge(person: me, size: 36)
        } content: {
            ProgressCard(blitz: blitz, me: me)
            SpinBanner(me: me)
            ForEach(blitz.allRewards, id: \.person) { reward in
                RewardCard(me: me, blitz: blitz, reward: reward)
            }
            EarningsPanel(me: me)
            if !mine.isEmpty {
                SectionLabel(text: skin.word("Your chores", "Your quests"))
                ForEach(mine) { MyChoreCard(me: me, task: $0) }
            }
            SectionLabel(text: open.isEmpty ? skin.word("Nothing left to grab", "All quests taken")
                                            : skin.word("Up for grabs", "Quests up for grabs"),
                         trailing: open.isEmpty ? nil : "\(open.count)")
            if !open.isEmpty {
                TaskRows(me: me, tasks: open)
            }
            if !others.isEmpty {
                SectionLabel(text: skin.word("Others are on it", "Party members on it"), trailing: "\(others.count)")
                TaskRows(me: me, tasks: others)
            }
            if !done.isEmpty {
                SectionLabel(text: skin.word("Done", "Cleared"), trailing: "\(done.count)")
                TaskRows(me: me, tasks: done)
            }
        }
        .overlay { if skin.arcade { PhoneBurstLayer(bursts: bursts) } }
        .onChange(of: Set(blitz.tasks.filter { $0.doneAt != nil && $0.claimedBy == me }.map(\.id)), initial: true) { _, now in
            // One of my chores just got finished (here or on its how-to screen).
            if let known = knownMyDone {
                for id in now.subtracting(known) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    guard game, skin.arcade else { continue }
                    let minutes = blitz.tasks.first { $0.id == id }?.minutes ?? 1
                    GameAudio.shared.kaching()
                    GameAudio.shared.gem()
                    celebrate("+\(max(minutes, 1)) XP")
                }
            }
            knownMyDone = now
        }
        .onChange(of: level(forXP: familyXP(blitz)).level, initial: true) { _, lv in
            // Level-up fanfare when the family XP bar fills.
            if game, skin.arcade, let known = knownLevel, lv > known {
                GameAudio.shared.levelUp()
                celebrate("LEVEL \(lv)!")
            }
            knownLevel = lv
        }
    }

    func celebrate(_ label: String) {
        let b = PhoneBurst(label: label)
        bursts.append(b)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { bursts.removeAll { $0.id == b.id } }
    }
}

// MARK: One chore

/// The how-to for one chore: a checklist of steps and one big button.
struct TaskDetailView: View {
    let me: Person
    let taskID: UUID
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<Int> = []

    var task: BlitzTask? { store.state?.blitz?.tasks.first { $0.id == taskID } }

    var body: some View {
        Group {
            if let task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.name)
                            .font(skin.title(30))
                            .foregroundStyle(skin.arcade ? skin.accent : skin.text)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if let who = task.claimedBy { PersonBadge(person: who, size: 24) }
                            Text(status(task)).font(skin.body(15)).foregroundStyle(skin.text2)
                        }
                        if task.steps.isEmpty {
                            Text("No steps written for this one yet. Ask Brandon or Kira if you're not sure how.")
                                .font(skin.body(16))
                                .foregroundStyle(skin.text2)
                                .cardBox()
                                .padding(.top, 8)
                        } else {
                            SectionLabel(text: "How to do it", trailing: "\(checked.count) of \(task.steps.count)")
                            steps(task)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 4) { actions(task) }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .background(skin.bg.opacity(skin.arcade ? 0.9 : 1))
                }
            } else {
                Text("This chore isn't on the list anymore.")
                    .font(skin.body(16))
                    .foregroundStyle(skin.text2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(skin.text)
        .background { PageBackground() }
        .navigationBarTitleDisplayMode(.inline)
    }

    func status(_ task: BlitzTask) -> String {
        var parts: [String] = []
        if let who = task.claimedBy {
            parts.append(who == me ? (task.doneAt == nil ? "You're on it" : "You did this") : who.name)
        }
        parts.append(task.room)
        if store.showTimes { parts.append("about \(task.minutes) min") }
        return parts.joined(separator: " · ")
    }

    func steps(_ task: BlitzTask) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(task.steps.enumerated()), id: \.offset) { i, step in
                if i > 0 {
                    Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 60)
                }
                Button {
                    if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            if checked.contains(i) {
                                Circle().fill(Palette.done)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(Palette.onDone)
                            } else {
                                Circle().strokeBorder(skin.accentText, lineWidth: 2)
                                Text("\(i + 1)")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(skin.accentText)
                            }
                        }
                        .frame(width: 30, height: 30)
                        Text(step)
                            .font(skin.body(17))
                            .strikethrough(checked.contains(i))
                            .foregroundStyle(checked.contains(i) ? skin.text2 : skin.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(skin.card, in: RoundedRectangle(cornerRadius: skin.corner, style: .continuous))
    }

    @ViewBuilder
    func actions(_ task: BlitzTask) -> some View {
        let canAct = task.claimedBy == nil || task.claimedBy == me || me.isParent
        switch task.column {
        case .open:
            Button("Claim this chore") { store.run { try $0.claim(taskID: taskID, by: me) } }
                .buttonStyle(BlitzButtonStyle(kind: .accent, height: 56))
            Button("I already did it") { finish() }
                .buttonStyle(QuietTextButtonStyle())
        case .inProgress:
            if canAct {
                Button { finish() } label: { Label("Mark done", systemImage: "checkmark") }
                    .buttonStyle(BlitzButtonStyle(kind: .done, height: 56))
                // A chore a parent assigned can only be handed back by a parent.
                if task.assignedTo == nil || me.isParent {
                    Button(task.claimedBy == me ? "Give it back" : "Take it off \(task.claimedBy?.name ?? "them")") {
                        store.run { try $0.unclaim(taskID: taskID, by: me) }
                    }
                    .buttonStyle(QuietTextButtonStyle())
                }
            } else {
                Text("\(task.claimedBy?.name ?? "Someone") is on this one.")
                    .font(skin.body(16, .bold))
                    .foregroundStyle(skin.text2)
                    .frame(height: 56)
            }
        case .done:
            Label("Done", systemImage: "checkmark.seal.fill")
                .font(skin.body(18, .heavy))
                .foregroundStyle(Palette.done)
                .frame(height: 44)
            if canAct {
                Button("Not done yet") { store.run { try $0.markNotDone(taskID: taskID, by: me) } }
                    .buttonStyle(QuietTextButtonStyle())
            }
        }
    }

    /// Marks it done and goes back to the list.
    func finish() {
        Task {
            let ok = await store.apply { try $0.markDone(taskID: taskID, by: me, now: .now) }
            if ok { dismiss() }
        }
    }
}

/// A plain text button under a big one ("Give it back").
struct QuietTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(pressed: configuration.isPressed, label: configuration.label)
    }

    private struct Face<Label: View>: View {
        @Environment(\.skin) private var skin
        let pressed: Bool
        let label: Label

        var body: some View {
            label
                .font(skin.body(15, .heavy))
                .foregroundStyle(skin.text2)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
                .opacity(pressed ? 0.5 : 1)
        }
    }
}
