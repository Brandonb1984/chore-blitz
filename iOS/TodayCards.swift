import ChoreKit
import SwiftUI

// Cards that make up the Today screen.

/// "5 of 12 done" with one pill per chore, colored by who finished it.
struct ProgressCard: View {
    let blitz: Blitz
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin

    var game: Bool { store.state?.isGameMode ?? false }

    var body: some View {
        let done = blitz.tasks(in: .done).count
        let total = blitz.tasks.count
        VStack(alignment: .leading, spacing: 12) {
            if skin.arcade && game {
                XPBar(blitz: blitz, size: 18)
            }
            HStack(alignment: .firstTextBaseline) {
                (Text("\(done)").font(skin.title(30))
                    + Text(" of \(total) \(skin.word("done", "cleared"))").font(skin.body(16, .bold)).foregroundColor(skin.text2))
                Spacer(minLength: 8)
                if blitz.hasTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = blitz.remaining(at: ctx.date) ?? 0
                        Text(left > 0 ? "\(countdownText(left)) left" : "Time's up")
                            .font(skin.body(18, .heavy))
                            .monospacedDigit()
                            .foregroundStyle(left > 300 ? skin.text : (left > 0 ? skin.accentText : Palette.danger))
                    }
                } else if skin.arcade && game {
                    Text("You: \(personXP(me, blitz)) XP").font(skin.body(14, .bold)).foregroundStyle(skin.text2)
                } else {
                    Text(total - done == 0 ? "All done" : "\(total - done) to go")
                        .font(skin.body(14, .bold)).foregroundStyle(skin.text2)
                }
            }
            SegmentedProgress(tasks: blitz.tasks, track: skin.inset)
        }
        .cardBox()
    }
}

/// Progress toward a reward a parent set ("Finish your 3 chores to earn $20").
/// Parents get "Mark paid" once it's earned.
struct RewardCard: View {
    let me: Person
    let blitz: Blitz
    let reward: Reward
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin

    var body: some View {
        let mine = blitz.assignedTasks(for: reward.person)
        let done = mine.filter { $0.doneAt != nil }.count
        let earned = blitz.hasEarned(reward)
        let isMe = reward.person == me
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PersonBadge(person: reward.person, size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(count: mine.count, done: done, earned: earned, isMe: isMe))
                        .font(skin.body(16, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    if !earned && !blitz.isOver {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(skin.inset)
                                Capsule().fill(reward.person.color)
                                    .frame(width: g.size.width * CGFloat(done) / CGFloat(max(mine.count, 1)))
                            }
                        }
                        .frame(height: 8)
                    }
                }
                if !earned {
                    Text("\(done) of \(mine.count)").font(skin.body(14, .bold)).foregroundStyle(skin.text2)
                }
            }
            if earned && reward.paidAt == nil && me.isParent {
                Button("Mark \(reward.prize) paid") {
                    store.run { try $0.markRewardPaid(for: reward.person, by: me, now: .now) }
                }
                .buttonStyle(BlitzButtonStyle(kind: .done, height: 46))
            }
        }
        .cardBox()
    }

    func title(count: Int, done: Int, earned: Bool, isMe: Bool) -> String {
        let who = isMe ? "You" : reward.person.name
        if earned {
            return reward.paidAt != nil ? "\(who) earned \(reward.prize), and it's paid" : "\(who) earned \(reward.prize)!"
        }
        if blitz.isOver {
            return "\(who) finished \(done) of \(count) for \(reward.prize), so it wasn't earned"
        }
        return isMe ? "Finish your \(count) chore\(count == 1 ? "" : "s") to earn \(reward.prize)"
                    : "\(reward.person.name): finish \(count) chore\(count == 1 ? "" : "s") for \(reward.prize)"
    }
}

/// What Reagen has won from loot chests. He sees his total; parents see what
/// they owe and pay it all with one button.
struct EarningsPanel: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin

    var body: some View {
        if let s = store.state {
            ForEach(HouseholdState.spinners.sorted { $0.rawValue < $1.rawValue }, id: \.self) { earner in
                let e = s.earnings(for: earner)
                if e.spins > 0 && (me == earner || me.isParent) {
                    card(earner: earner, e: e, extras: s.unpaidSpins.filter { $0.person == earner && $0.prize.cents == nil })
                }
            }
        }
    }

    func card(earner: Person, e: Earnings, extras: [Spin]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PersonBadge(person: earner, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(earner: earner, e: e)).font(skin.body(18, .heavy))
                    Text("\(Prize.format(cents: e.totalCents)) won in all · \(Prize.format(cents: e.paidCents)) paid · \(e.spins) chest\(e.spins == 1 ? "" : "s")")
                        .font(skin.body(13)).foregroundStyle(skin.text2)
                    if !extras.isEmpty {
                        Text("Also won: " + extras.map(\.prize.name).joined(separator: ", "))
                            .font(skin.body(13)).foregroundStyle(skin.text2)
                    }
                }
                Spacer(minLength: 0)
            }
            if me.isParent && (e.owedCents > 0 || !extras.isEmpty) {
                Button(e.owedCents > 0 ? "Mark \(Prize.format(cents: e.owedCents)) paid" : "Mark all paid") {
                    store.run { try $0.markAllSpinsPaid(for: earner, by: me, now: .now) }
                }
                .buttonStyle(BlitzButtonStyle(kind: .done, height: 46))
            }
        }
        .cardBox()
    }

    func headline(earner: Person, e: Earnings) -> String {
        if me == earner {
            return e.owedCents > 0 ? "You're owed \(Prize.format(cents: e.owedCents))" : "You've won \(Prize.format(cents: e.totalCents))"
        }
        return e.owedCents > 0 ? "\(earner.name) is owed \(Prize.format(cents: e.owedCents))" : "\(earner.name) is all paid up"
    }
}

/// The big card for a chore you've taken: how to do it, and a large Done.
struct MyChoreCard: View {
    let me: Person
    let task: BlitzTask
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(task.name)
                .font(skin.title(22))
                .fixedSize(horizontal: false, vertical: true)
            Text(TaskText.detail(task, store: store, skin: skin, me: me, steps: true))
                .font(skin.body(14))
                .foregroundStyle(skin.text2)
                .padding(.top, 3)
            HStack(spacing: 10) {
                NavigationLink(value: task.id) { Text("How to") }
                    .buttonStyle(BlitzButtonStyle(kind: .quiet, fill: false))
                Button {
                    store.run { try $0.markDone(taskID: task.id, by: me, now: .now) }
                } label: {
                    Label(skin.word("Done", "DONE"), systemImage: "checkmark")
                }
                .buttonStyle(BlitzButtonStyle(kind: .done))
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(skin.card, in: RoundedRectangle(cornerRadius: skin.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: skin.corner, style: .continuous)
            .strokeBorder(skin.arcade ? skin.accent : me.color, lineWidth: 2))
    }
}

/// A card of chore rows with hairlines between them.
struct TaskRows: View {
    let me: Person
    let tasks: [BlitzTask]
    @Environment(\.skin) private var skin

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { i, task in
                if i > 0 {
                    Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 16)
                }
                TaskRow(me: me, task: task)
            }
        }
        .background(skin.card, in: RoundedRectangle(cornerRadius: skin.corner, style: .continuous))
    }
}

/// One chore in a list: tap the name for the how-to, or the button to act.
struct TaskRow: View {
    let me: Person
    let task: BlitzTask
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: task.id) {
                HStack(spacing: 12) {
                    if let who = task.claimedBy {
                        PersonBadge(person: who, size: 28)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name)
                            .font(skin.body(17, .bold))
                            .strikethrough(task.doneAt != nil)
                            .foregroundStyle(task.doneAt != nil ? skin.text2 : skin.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(TaskText.detail(task, store: store, skin: skin, me: me))
                            .font(skin.body(13))
                            .foregroundStyle(skin.text2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            action
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
    }

    @ViewBuilder var action: some View {
        switch task.column {
        case .open:
            Button("Claim") { store.run { try $0.claim(taskID: task.id, by: me) } }
                .buttonStyle(BlitzButtonStyle(kind: .accent, height: 40, fill: false))
        case .inProgress:
            if task.claimedBy == me || me.isParent {
                Button("Done") { store.run { try $0.markDone(taskID: task.id, by: me, now: .now) } }
                    .buttonStyle(BlitzButtonStyle(kind: .done, height: 40, fill: false))
            }
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Palette.done)
        }
    }
}

/// The small grey line under a chore's name.
enum TaskText {
    @MainActor
    static func detail(_ task: BlitzTask, store: HouseholdStore, skin: Skin, me: Person, steps: Bool = false) -> String {
        var parts: [String] = []
        if let who = task.claimedBy, who != me { parts.append(who.name) }
        parts.append(task.room)
        let game = store.state?.isGameMode ?? false
        if skin.arcade && game {
            parts.append("+\(max(task.minutes, 1)) XP")
        } else if store.showTimes {
            parts.append("\(task.minutes) min")
        }
        if steps && !task.steps.isEmpty {
            parts.append("\(task.steps.count) step\(task.steps.count == 1 ? "" : "s")")
        }
        // Reagen sees what an unfinished chore is worth in loot chests.
        if game && task.doneAt == nil && HouseholdState.spinners.contains(me) && (task.claimedBy == nil || task.claimedBy == me) {
            let n = HouseholdState.chests(forMinutes: task.minutes)
            parts.append("\(n) chest\(n == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
