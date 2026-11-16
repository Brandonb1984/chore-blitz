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
        VStack(alignment: .leading, spacing: 36) {
            HStack(alignment: .firstTextBaseline) {
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
            HStack {
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
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            ForEach(tasks) { task in
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.name)
                            .font(compact ? .headline : .title3.weight(.semibold))
                            .strikethrough(column == .done)
                            .lineLimit(1)
                        if !compact {
                            Text(task.room).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let who = task.claimedBy {
                        HStack(spacing: 10) {
                            PersonBadge(person: who, size: compact ? 32 : 44)
                            if !compact { Text(who.name).font(.headline) }
                        }
                    }
                }
                .padding(compact ? 12 : 20)
                .background(RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(column == .done ? 0.05 : 0.10)))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(task.claimedBy?.color.opacity(column == .inProgress ? 0.9 : 0) ?? .clear, lineWidth: 3))
                .opacity(column == .done ? 0.7 : 1)
            }
        }
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
