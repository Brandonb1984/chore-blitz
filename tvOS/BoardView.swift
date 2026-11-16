import ChoreKit
import SwiftUI
import UIKit

/// The living-room board. Read-only: everything is controlled from phones.
struct BoardView: View {
    @EnvironmentObject var store: HouseholdStore

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.10, green: 0.14, blue: 0.24)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            content
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .preferredColorScheme(.dark)
        .onChange(of: store.state?.runningBlitz != nil, initial: true) { _, running in
            // Keep the TV awake while a blitz is on.
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }

    @ViewBuilder var content: some View {
        if let state = store.state {
            if let blitz = state.runningBlitz {
                RunningBoard(blitz: blitz)
            } else if let last = state.blitz, last.isOver {
                FinishedBoard(blitz: last)
            } else {
                IdleBoard(choreCount: state.chores.count)
            }
        } else if store.isLoading {
            ProgressView()
        } else {
            VStack(spacing: 20) {
                Text("Chore Blitz").font(.system(size: 80, weight: .heavy, design: .rounded))
                Text(store.problem ?? "Open Chore Blitz on Brandon's or Kira's phone to set it up.")
                    .font(.title2).foregroundStyle(.secondary)
            }
        }
    }
}

struct IdleBoard: View {
    let choreCount: Int

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "sparkles").font(.system(size: 120)).foregroundStyle(.yellow)
            Text("Chore Blitz").font(.system(size: 96, weight: .heavy, design: .rounded))
            Text("Ready when you are. Start a blitz from your phone.")
                .font(.title2).foregroundStyle(.secondary)
            Text("\(choreCount) chores in the list").font(.headline).foregroundStyle(.tertiary)
        }
    }
}

struct RunningBoard: View {
    let blitz: Blitz

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                Text("Chore Blitz").font(.system(size: 56, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(blitz.tasks(in: .done).count) of \(blitz.tasks.count) done")
                    .font(.title2).foregroundStyle(.secondary)
                    .padding(.trailing, 40)
                if blitz.hasTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = blitz.remaining(at: ctx.date) ?? 0
                        Text(countdownText(left))
                            .font(.system(size: 110, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(left > 0 ? (left < 300 ? Color.yellow : Color.white) : Color.red)
                    }
                }
            }
            ProgressView(value: Double(blitz.tasks(in: .done).count), total: Double(max(blitz.tasks.count, 1)))
                .tint(.green)
                .scaleEffect(x: 1, y: 3, anchor: .center)
            if !blitz.allRewards.isEmpty {
                HStack(spacing: 24) {
                    ForEach(blitz.allRewards, id: \.person) { RewardPill(blitz: blitz, reward: $0) }
                }
            }
            GeometryReader { geo in
                let widths = columnWidths(total: geo.size.width)
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(Array(TaskColumn.allCases.enumerated()), id: \.element) { i, col in
                        BoardColumn(column: col, tasks: blitz.tasks(in: col))
                            .frame(width: widths[i])
                    }
                }
                .frame(height: geo.size.height, alignment: .top)
                .animation(.easeInOut(duration: 0.4), value: widths)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    static let columnSpacing: CGFloat = 40

    /// Every column gets a minimum width; the rest is shared by how many
    /// chores each holds, so a fresh blitz's long Open column gets room.
    func columnWidths(total: CGFloat) -> [CGFloat] {
        let counts = TaskColumn.allCases.map { CGFloat(blitz.tasks(in: $0).count) }
        let usable = total - Self.columnSpacing * CGFloat(counts.count - 1)
        let base = min(400, usable / CGFloat(counts.count))
        let extra = usable - base * CGFloat(counts.count)
        let sum = counts.reduce(0, +)
        return counts.map { base + (sum > 0 ? extra * $0 / sum : extra / CGFloat(counts.count)) }
    }
}

struct BoardColumn: View {
    let column: TaskColumn
    let tasks: [BlitzTask]

    var accent: Color {
        switch column {
        case .open: return .gray
        case .inProgress: return .yellow
        case .done: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Circle().fill(accent).frame(width: 18, height: 18)
                Text(column.title).font(.title2.bold())
                Text("\(tasks.count)").font(.title2).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Use the roomiest card size that fits the column's real height;
            // long columns (a fresh blitz) fall back to single-line rows that
            // are sized to always fit.
            ViewThatFits(in: .vertical) {
                cards(.full)
                cards(.compact)
                TightCards(column: column, tasks: tasks)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    enum Density { case full, compact }

    func cards(_ density: Density) -> some View {
        let full = density == .full
        return VStack(alignment: .leading, spacing: full ? 14 : 10) {
            ForEach(tasks) { task in
                HStack(alignment: .center, spacing: 18) {
                    if let who = task.claimedBy {
                        PersonBadge(person: who, size: full ? 56 : 44)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name)
                            .font(full ? .title2.weight(.semibold) : .title3.weight(.semibold))
                            .foregroundStyle(column == .done ? Color.white.opacity(0.75) : Color.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        if full {
                            Text(BoardColumn.subtitle(task))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if column == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: full ? 40 : 34))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, full ? 20 : 16)
                .padding(.vertical, full ? 16 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(CardBackground(column: column, task: task))
            }
        }
    }

    static func subtitle(_ task: BlitzTask) -> String {
        if let who = task.claimedBy { return "\(who.name) · \(task.room)" }
        return task.room
    }
}

/// Rows sized from the space available so a long column is never cut off.
/// When the column is wide enough it splits into two sub-columns.
struct TightCards: View {
    let column: TaskColumn
    let tasks: [BlitzTask]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let split = tasks.count > 5 && geo.size.width >= 760
            let perCol = split ? (tasks.count + 1) / 2 : max(tasks.count, 1)
            let rows = CGFloat(perCol)
            let row = min(110, max(36, (geo.size.height - spacing * (rows - 1)) / rows))
            let font = min(38, max(22, row * 0.36))
            let twoLines = row >= font * 2.5
            let halves = split ? [Array(tasks.prefix(perCol)), Array(tasks.dropFirst(perCol))] : [tasks]
            HStack(alignment: .top, spacing: 14) {
                ForEach(halves.indices, id: \.self) { h in
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(halves[h]) { task in
                            card(task, height: row, font: font, lines: twoLines ? 2 : 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    func card(_ task: BlitzTask, height: CGFloat, font: CGFloat, lines: Int) -> some View {
        HStack(spacing: 14) {
            if let who = task.claimedBy {
                PersonBadge(person: who, size: min(56, font * 1.3))
            }
            Text(task.name)
                .font(.system(size: font, weight: .semibold))
                .foregroundStyle(column == .done ? Color.white.opacity(0.75) : Color.white)
                .lineLimit(lines)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if column == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: font))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .modifier(CardBackground(column: column, task: task, corner: 16))
    }
}

struct CardBackground: ViewModifier {
    let column: TaskColumn
    let task: BlitzTask
    var corner: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: corner)
                .fill(Color.white.opacity(column == .done ? 0.06 : 0.11)))
            .overlay(RoundedRectangle(cornerRadius: corner)
                .stroke(task.claimedBy?.color.opacity(column == .inProgress ? 0.9 : 0) ?? .clear, lineWidth: 4))
    }
}

struct FinishedBoard: View {
    let blitz: Blitz

    var body: some View {
        VStack(spacing: 40) {
            Text(blitz.tasks.allSatisfy { $0.doneAt != nil } ? "All done! 🎉" : "That's a wrap")
                .font(.system(size: 100, weight: .heavy, design: .rounded))
            Text("\(blitz.tasks(in: .done).count) of \(blitz.tasks.count) chores done")
                .font(.title).foregroundStyle(.secondary)
            if !blitz.allRewards.isEmpty {
                HStack(spacing: 24) {
                    ForEach(blitz.allRewards, id: \.person) { RewardPill(blitz: blitz, reward: $0) }
                }
            }
            HStack(alignment: .top, spacing: 40) {
                ForEach(blitz.doneByPerson, id: \.person) { entry in
                    VStack(spacing: 16) {
                        PersonBadge(person: entry.person, size: 90)
                        Text(entry.person.name).font(.title2.bold())
                        ForEach(entry.tasks) { t in
                            Text(t.name).font(.headline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 380)
                }
            }
        }
    }
}

/// "Reagen · 2 of 4 → $20", or "Reagen earned $20!" once his assigned chores are done.
struct RewardPill: View {
    let blitz: Blitz
    let reward: Reward

    var body: some View {
        let mine = blitz.assignedTasks(for: reward.person)
        let done = mine.filter { $0.doneAt != nil }.count
        let earned = blitz.hasEarned(reward)
        HStack(spacing: 14) {
            PersonBadge(person: reward.person, size: 44)
            if earned {
                Text("\(reward.person.name) earned \(reward.prize)!")
                    .font(.title3.bold())
                Image(systemName: reward.paidAt != nil ? "checkmark.seal.fill" : "star.fill")
                    .foregroundStyle(.yellow)
            } else {
                Text("\(reward.person.name) · \(done) of \(mine.count) → \(reward.prize)")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Capsule().fill(earned ? Color.yellow.opacity(0.25) : Color.white.opacity(0.10)))
        .overlay(Capsule().stroke(reward.person.color.opacity(0.8), lineWidth: 3))
    }
}
