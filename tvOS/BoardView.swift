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
                .padding(60)
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
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = blitz.remaining(at: ctx.date)
                    Text(countdownText(left))
                        .font(.system(size: 110, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(left > 0 ? (left < 300 ? Color.yellow : Color.white) : Color.red)
                }
            }
            ProgressView(value: Double(blitz.tasks(in: .done).count), total: Double(max(blitz.tasks.count, 1)))
                .tint(.green)
                .scaleEffect(x: 1, y: 3, anchor: .center)
            HStack(alignment: .top, spacing: 40) {
                ForEach(TaskColumn.allCases, id: \.self) { col in
                    BoardColumn(column: col, tasks: blitz.tasks(in: col))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            // Shrink cards if a column gets long so everything still fits.
            ViewThatFits(in: .vertical) {
                cards(compact: false)
                cards(compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func cards(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            ForEach(tasks) { task in
                HStack(alignment: .center, spacing: 18) {
                    if let who = task.claimedBy {
                        PersonBadge(person: who, size: compact ? 40 : 56)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.name)
                            .font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                            .foregroundStyle(column == .done ? Color.white.opacity(0.75) : Color.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        if !compact {
                            Text(subtitle(task))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if column == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: compact ? 32 : 40))
                            .foregroundStyle(.green)
                    }
                }
                .padding(compact ? 14 : 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(column == .done ? 0.06 : 0.11)))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(task.claimedBy?.color.opacity(column == .inProgress ? 0.9 : 0) ?? .clear, lineWidth: 4))
            }
        }
    }

    func subtitle(_ task: BlitzTask) -> String {
        if let who = task.claimedBy { return "\(who.name) · \(task.room)" }
        return task.room
    }
}

struct FinishedBoard: View {
    let blitz: Blitz

    var body: some View {
        VStack(spacing: 40) {
            Text(blitz.tasks.allSatisfy { $0.doneAt != nil } ? "All done! 🎉" : "Blitz over")
                .font(.system(size: 100, weight: .heavy, design: .rounded))
            Text("\(blitz.tasks(in: .done).count) of \(blitz.tasks.count) chores done")
                .font(.title).foregroundStyle(.secondary)
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
