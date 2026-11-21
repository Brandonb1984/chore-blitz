import ChoreKit
import SwiftUI
import UIKit

/// The living-room board. Read-only: everything is controlled from phones.
///
/// One grid shows every chore in list order. A chore doesn't move when it's
/// claimed or finished; it changes look in place, so the board stays calm.
/// The panel on the right has a lane for each person.
struct BoardView: View {
    @EnvironmentObject var store: HouseholdStore
    var game: Bool { store.state?.isGameMode ?? false }
    var running: Bool { store.state?.runningBlitz != nil }
    var musicOn: Bool { game && running && (store.state?.isMusicOn ?? true) }

    var body: some View {
        ZStack {
            if game {
                ArcadeBackground().ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(uiColor: Palette.hex(0x0A0F1C)), Color(uiColor: Palette.hex(0x141B30))],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            if let state = store.state, state.isGameMode {
                GameLayer(state: state)
            }
        }
        .foregroundStyle(.white)
        .environment(\.tvLook, TVLook(game: game))
        .onChange(of: musicOn, initial: true) { _, on in
            GameAudio.shared.setMusic(on)
        }
        .preferredColorScheme(.dark)
        .onChange(of: running, initial: true) { _, running in
            // Keep the TV awake while a list is going.
            UIApplication.shared.isIdleTimerDisabled = running
        }
    }

    @ViewBuilder var content: some View {
        if let state = store.state {
            if let blitz = state.runningBlitz {
                RunningBoard(blitz: blitz, state: state)
            } else if let last = state.blitz, last.isOver {
                FinishedBoard(blitz: last, state: state)
            } else {
                IdleBoard(state: state)
            }
        } else if store.isLoading {
            ProgressView()
        } else {
            VStack(spacing: 28) {
                Wordmark(size: 96)
                Text(store.problem ?? "Open Chore Blitz on Brandon's or Kira's phone to set it up.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(TVLook.dim)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// How the TV draws itself: the normal look, or the arcade look in Game mode.
struct TVLook: Equatable {
    var game = false

    static let dim = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.38)

    var corner: CGFloat { game ? 8 : 24 }
    var accent: Color { game ? Palette.arcadeYellow : Palette.accent }

    func title(_ size: CGFloat) -> Font {
        game ? .system(size: size * 0.9, weight: .black, design: .monospaced)
             : .system(size: size, weight: .heavy, design: .rounded)
    }

    func text(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Big numbers: monospaced in Game mode, rounded otherwise.
    func number(_ size: CGFloat) -> Font {
        game ? .system(size: size, weight: .black, design: .monospaced)
             : .system(size: size, weight: .heavy, design: .rounded)
    }

    func name(_ person: Person) -> String { game ? person.name.uppercased() : person.name }
}

private struct TVLookKey: EnvironmentKey {
    static let defaultValue = TVLook()
}

extension EnvironmentValues {
    var tvLook: TVLook {
        get { self[TVLookKey.self] }
        set { self[TVLookKey.self] = newValue }
    }
}

/// The yellow bolt and the app's name.
struct Wordmark: View {
    @Environment(\.tvLook) private var look
    var size: CGFloat = 96

    var body: some View {
        HStack(spacing: size * 0.18) {
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.8, weight: .black))
                .foregroundStyle(look.accent)
            Text(look.game ? "CHORE BLITZ" : "Chore Blitz")
                .font(look.title(size))
        }
        .fixedSize()
    }
}

// MARK: Running

struct RunningBoard: View {
    let blitz: Blitz
    let state: HouseholdState
    @Environment(\.tvLook) private var look

    var doneCount: Int { blitz.tasks(in: .done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            header
            HStack(alignment: .top, spacing: 40) {
                ChoreGrid(tasks: blitz.tasks)
                PeoplePanel(blitz: blitz, state: state)
                    .frame(width: 580)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var header: some View {
        HStack(alignment: .center, spacing: 40) {
            if look.game {
                XPBar(blitz: blitz, size: 64)
                count(word: "cleared")
            } else {
                count(word: "done")
                SegmentedProgress(tasks: blitz.tasks, height: 24, track: Color.white.opacity(0.12))
            }
            if blitz.hasTimer {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = blitz.remaining(at: ctx.date) ?? 0
                    Text(countdownText(left))
                        .font(look.number(look.game ? 84 : 104))
                        .monospacedDigit()
                        .foregroundStyle(left > 0 ? (left < 300 ? look.accent : Color.white) : Palette.danger)
                        .fixedSize()
                }
            }
        }
        .frame(height: 110)
    }

    /// "5 of 12 done"
    func count(word: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text("\(doneCount)")
                .font(look.number(look.game ? 72 : 104))
                .contentTransition(.numericText())
            Text("of \(blitz.tasks.count) \(word)")
                .font(look.title(42))
                .foregroundStyle(TVLook.dim)
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.4), value: doneCount)
    }
}

/// Every chore on the list, in order, sized so the whole list always fits.
struct ChoreGrid: View {
    let tasks: [BlitzTask]

    static func columns(for count: Int) -> Int {
        if count <= 6 { return 1 }
        if count <= 16 { return 2 }
        return 3
    }

    var body: some View {
        GeometryReader { geo in
            let cols = Self.columns(for: tasks.count)
            let rows = max(1, Int((Double(tasks.count) / Double(cols)).rounded(.up)))
            let gap: CGFloat = rows > 8 ? 10 : 14
            let rowHeight = min(132, max(44, (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)))
            let chunks = stride(from: 0, to: tasks.count, by: rows).map { Array(tasks[$0..<min($0 + rows, tasks.count)]) }
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    VStack(spacing: gap) {
                        ForEach(chunk) { task in
                            ChoreCard(task: task, height: rowHeight, roomy: cols < 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

/// One chore on the board. Open is bright, in progress carries its person's
/// color, done fades back with a check.
struct ChoreCard: View {
    let task: BlitzTask
    let height: CGFloat
    /// Wide enough for extras (XP in Game mode).
    var roomy = true
    @Environment(\.tvLook) private var look

    var body: some View {
        let done = task.doneAt != nil
        let working = !done && task.claimedBy != nil
        let font = min(40, max(22, height * 0.31))
        let twoLines = height >= font * 2.7
        HStack(spacing: font * 0.5) {
            if let who = task.claimedBy {
                PersonBadge(person: who, size: min(58, height * 0.52))
                    .opacity(done ? 0.75 : 1)
            }
            Text(task.name)
                .font(look.text(font, .bold))
                .strikethrough(done, color: Color.white.opacity(0.5))
                .foregroundStyle(done ? Color.white.opacity(0.45) : Color.white)
                .lineLimit(twoLines ? 2 : 1)
                .minimumScaleFactor(0.65)
            Spacer(minLength: 0)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: font * 0.8, weight: .black))
                    .foregroundStyle(Palette.done)
            } else if look.game && roomy {
                Text("+\(max(task.minutes, 1)) XP")
                    .font(.system(size: font * 0.62, weight: .black, design: .monospaced))
                    .foregroundStyle(Palette.arcadeMint.opacity(working ? 1 : 0.7))
                    .fixedSize()
            }
        }
        .padding(.leading, font * 0.85)
        .padding(.trailing, font * 0.7)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background(Color.white.opacity(done ? 0.05 : (working ? 0.16 : 0.10)))
        .overlay(alignment: .leading) {
            if working, let who = task.claimedBy {
                Rectangle().fill(who.color).frame(width: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: min(look.corner, height * 0.3), style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: task.column)
    }
}

/// A lane per person: what they're on, and how much they've finished.
struct PeoplePanel: View {
    let blitz: Blitz
    let state: HouseholdState

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Person.allCases) { person in
                PersonLane(person: person, blitz: blitz, state: state)
            }
        }
    }
}

struct PersonLane: View {
    let person: Person
    let blitz: Blitz
    let state: HouseholdState
    @Environment(\.tvLook) private var look

    var body: some View {
        let mine = blitz.tasks.filter { $0.claimedBy == person }
        let working = mine.filter { $0.doneAt == nil }
        let done = mine.count - working.count
        HStack(spacing: 24) {
            PersonBadge(person: person, size: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(look.name(person))
                    .font(look.title(36))
                status(working: working)
                    .font(look.text(27))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let extra = extraLine {
                    Text(extra)
                        .font(look.text(25))
                        .foregroundStyle(look.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(look.game ? "\(personXP(person, blitz))" : "\(done)")
                    .font(look.number(60))
                    .foregroundStyle(look.game ? Palette.arcadeMint : Color.white)
                    .contentTransition(.numericText())
                Text(look.game ? "XP" : "done")
                    .font(look.text(22, .bold))
                    .foregroundStyle(TVLook.dim)
            }
            .fixedSize()
            .animation(.easeOut(duration: 0.4), value: done)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(working.isEmpty ? 0.07 : 0.11),
                    in: RoundedRectangle(cornerRadius: look.corner, style: .continuous))
    }

    /// "On Wash bedding", or what to do next when they have nothing going.
    func status(working: [BlitzTask]) -> Text {
        if let first = working.first {
            let more = working.count > 1 ? " +\(working.count - 1)" : ""
            return Text("On ").foregroundColor(TVLook.dim) + Text(first.name + more).foregroundColor(.white)
        }
        // Chores a parent assigned to someone else aren't theirs to grab.
        let open = blitz.tasks.contains { $0.column == .open && ($0.assignedTo == nil || $0.assignedTo == person) }
        return Text(open ? "Free to grab one" : "All caught up").foregroundColor(TVLook.dim)
    }

    /// Reward progress, or chests waiting to be opened in Game mode.
    var extraLine: String? {
        let chests = state.spinsLeft(for: person)
        if chests > 0 { return chests == 1 ? "1 chest to open" : "\(chests) chests to open" }
        guard let reward = blitz.reward(for: person) else { return nil }
        if blitz.hasEarned(reward) { return "Earned \(reward.prize)!" }
        let assigned = blitz.assignedTasks(for: person)
        let done = assigned.filter { $0.doneAt != nil }.count
        return "\(done) of \(assigned.count) toward \(reward.prize)"
    }
}

// MARK: Idle

struct IdleBoard: View {
    let state: HouseholdState
    @Environment(\.tvLook) private var look

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Wordmark(size: 120)
            Text("Start today's list from your phone")
                .font(look.text(40))
                .foregroundStyle(TVLook.dim)
                .padding(.top, 22)
            HStack(spacing: 28) {
                ForEach(Person.allCases) { person in
                    VStack(spacing: 12) {
                        PersonBadge(person: person, size: 96)
                        Text(look.name(person))
                            .font(look.text(26, .bold))
                            .foregroundStyle(TVLook.dim)
                    }
                    .frame(width: 170)
                }
            }
            .padding(.top, 64)
            if let waiting = chestsWaiting {
                Text(waiting)
                    .font(look.title(30))
                    .foregroundStyle(look.accent)
                    .padding(.top, 44)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 20)) { ctx in
                HStack(spacing: 20) {
                    Text(ctx.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .foregroundStyle(.white)
                }
                .font(look.text(34, .bold))
                .foregroundStyle(TVLook.faint)
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Reagen has 2 chests to open"
    var chestsWaiting: String? {
        for person in Person.allCases {
            let n = state.spinsLeft(for: person)
            if n > 0 { return "\(person.name) has \(n) chest\(n == 1 ? "" : "s") to open" }
        }
        return nil
    }
}

// MARK: Finished

struct FinishedBoard: View {
    let blitz: Blitz
    let state: HouseholdState
    @Environment(\.tvLook) private var look

    var body: some View {
        let done = blitz.tasks(in: .done).count
        let all = !blitz.tasks.isEmpty && done == blitz.tasks.count
        let people = blitz.doneByPerson
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 26) {
                if all {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 84, weight: .black))
                        .foregroundStyle(look.accent)
                }
                Text(look.game ? (all ? "ALL CLEARED!" : "THAT'S A WRAP") : (all ? "All done!" : "That's a wrap"))
                    .font(look.title(110))
            }
            Text("\(done) of \(blitz.tasks.count) chores done")
                .font(look.text(38))
                .foregroundStyle(TVLook.dim)
                .padding(.top, 8)
            SegmentedProgress(tasks: blitz.tasks, height: 22, track: Color.white.opacity(0.12))
                .frame(maxWidth: 1100)
                .padding(.top, 34)
            if !people.isEmpty {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(people, id: \.person) { entry in
                        tally(entry, columns: people.count)
                    }
                }
                .padding(.top, 50)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func tally(_ entry: PersonDone, columns: Int) -> some View {
        let shown = entry.tasks.prefix(5)
        let hidden = entry.tasks.count - shown.count
        return VStack(spacing: 10) {
            HStack(spacing: 18) {
                PersonBadge(person: entry.person, size: 76)
                VStack(alignment: .leading, spacing: 0) {
                    Text(look.name(entry.person)).font(look.title(34))
                    Text(look.game ? "\(personXP(entry.person, blitz)) XP · \(entry.tasks.count) done"
                                   : (entry.tasks.count == 1 ? "1 chore" : "\(entry.tasks.count) chores"))
                        .font(look.text(26, .bold))
                        .foregroundStyle(look.game ? Palette.arcadeMint : TVLook.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)
            ForEach(Array(shown)) { task in
                Text(task.name)
                    .font(look.text(25))
                    .foregroundStyle(TVLook.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hidden > 0 {
                Text("and \(hidden) more")
                    .font(look.text(25))
                    .foregroundStyle(TVLook.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The reward shows only once it's really earned.
            if let reward = blitz.reward(for: entry.person), blitz.hasEarned(reward) {
                HStack(spacing: 10) {
                    Image(systemName: reward.paidAt != nil ? "checkmark.seal.fill" : "star.fill")
                    Text(reward.paidAt != nil ? "\(reward.prize) paid" : "Earned \(reward.prize)!")
                }
                .font(look.text(26, .heavy))
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(look.accent, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            }
        }
        .padding(26)
        .frame(maxWidth: columns <= 2 ? 520 : 420, alignment: .top)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: look.corner, style: .continuous))
    }
}

/// Dark purple arcade backdrop with a faint pixel grid and twinkling pixel stars.
struct ArcadeBackground: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .linearGradient(Gradient(colors: [Palette.arcadeTop, Palette.arcadeBottom]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                let cell: CGFloat = 40
                var grid = Path()
                var x: CGFloat = 0
                while x < size.width { grid.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += cell }
                var y: CGFloat = 0
                while y < size.height { grid.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += cell }
                g.fill(grid, with: .color(.white.opacity(0.03)))
                let tick = Int(ctx.date.timeIntervalSince1970 * 2)
                var rng = SeededRNG(seed: 42)
                for i in 0..<60 {
                    let px = (CGFloat.random(in: 0..<size.width, using: &rng) / 8).rounded() * 8
                    let py = (CGFloat.random(in: 0..<size.height, using: &rng) / 8).rounded() * 8
                    let on = (i + tick) % 5 != 0
                    // Dim enough to stay background even behind text and cards.
                    g.fill(Path(CGRect(x: px, y: py, width: 5, height: 5)),
                           with: .color(.white.opacity(on ? 0.16 : 0.05)))
                }
            }
        }
    }
}
