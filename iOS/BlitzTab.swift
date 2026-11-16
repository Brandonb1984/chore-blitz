import ChoreKit
import SwiftUI

struct BlitzTab: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @State private var showingStart = false

    var body: some View {
        NavigationStack {
            Group {
                if let blitz = store.state?.runningBlitz {
                    RunningBlitzView(me: me, blitz: blitz)
                } else {
                    IdleView(me: me, lastBlitz: store.state?.blitz) { showingStart = true }
                }
            }
            .navigationTitle("Chore Blitz")
            .toolbar {
                if me.isParent, store.state?.runningBlitz != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End blitz", role: .destructive) {
                            store.run { try $0.endBlitz(by: me, now: .now) }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingStart) { StartBlitzView(me: me) }
        }
    }
}

struct IdleView: View {
    let me: Person
    let lastBlitz: Blitz?
    let start: () -> Void
    @EnvironmentObject var store: HouseholdStore

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let last = lastBlitz, last.isOver {
                    FinishedCard(blitz: last)
                }
                if me.isParent {
                    Button(action: start) {
                        Label("Start a blitz", systemImage: "play.fill")
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
                        Text("No blitz right now").font(.title3.bold())
                        Text("When Brandon or Kira starts one, your chores show up here.")
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
    let blitz: Blitz

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last blitz: \(blitz.tasks(in: .done).count) of \(blitz.tasks.count) done")
                .font(.headline)
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
    @State private var selected: UUID?

    var mine: [BlitzTask] { blitz.tasks.filter { $0.claimedBy == me && $0.doneAt == nil } }
    var open: [BlitzTask] { blitz.tasks(in: .open) }
    var others: [BlitzTask] { blitz.tasks(in: .inProgress).filter { $0.claimedBy != me } }
    var done: [BlitzTask] { blitz.tasks(in: .done) }

    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = blitz.remaining(at: ctx.date)
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
            }
            if !mine.isEmpty {
                Section("Your chores") {
                    ForEach(mine) { row($0) }
                }
            }
            Section(open.isEmpty ? "Nothing left to grab" : "Up for grabs") {
                ForEach(open) { row($0) }
            }
            if !others.isEmpty {
                Section("Others are on it") { ForEach(others) { row($0) } }
            }
            if !done.isEmpty {
                Section("Done") { ForEach(done) { row($0) } }
            }
        }
        .navigationDestination(item: $selected) { id in
            TaskDetailView(me: me, taskID: id)
        }
    }

    func row(_ task: BlitzTask) -> some View {
        HStack {
            Button { selected = task.id } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name).strikethrough(task.doneAt != nil)
                        Text("\(task.room) · \(task.minutes) min").font(.caption).foregroundStyle(.secondary)
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
            } else if task.column == .inProgress && task.claimedBy == me {
                Button("Done") { store.run { try $0.markDone(taskID: task.id, by: me, now: .now) } }
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
    @State private var checked: Set<Int> = []

    var task: BlitzTask? { store.state?.blitz?.tasks.first { $0.id == taskID } }

    var body: some View {
        if let task {
            List {
                Section {
                    HStack {
                        Text("\(task.room) · about \(task.minutes) min").foregroundStyle(.secondary)
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
