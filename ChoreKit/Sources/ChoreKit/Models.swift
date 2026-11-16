import Foundation

public enum Person: String, Codable, CaseIterable, Identifiable, Sendable {
    case brandon, kira, braden, reagen

    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
    /// Parents create chores and start or end a blitz.
    public var isParent: Bool { self == .brandon || self == .kira }
}

public struct Chore: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var room: String
    public var minutes: Int
    public var steps: [String]

    public init(id: UUID = UUID(), name: String, room: String, minutes: Int, steps: [String]) {
        self.id = id
        self.name = name
        self.room = room
        self.minutes = minutes
        self.steps = steps
    }
}

public enum TaskColumn: String, CaseIterable, Sendable {
    case open, inProgress, done

    public var title: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In progress"
        case .done: return "Done"
        }
    }
}

/// A chore inside a running blitz. It copies the chore so editing the
/// library later doesn't change a blitz that's already going.
public struct BlitzTask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var choreID: UUID
    public var name: String
    public var room: String
    public var minutes: Int
    public var steps: [String]
    public var claimedBy: Person?
    public var doneAt: Date?
    /// Set when a parent assigned this chore as part of someone's reward.
    public var assignedTo: Person?

    public init(from chore: Chore) {
        id = UUID()
        choreID = chore.id
        name = chore.name
        room = chore.room
        minutes = chore.minutes
        steps = chore.steps
        claimedBy = nil
        doneAt = nil
        assignedTo = nil
    }

    public var column: TaskColumn {
        if doneAt != nil { return .done }
        if claimedBy != nil { return .inProgress }
        return .open
    }
}

public struct Blitz: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startedBy: Person
    public var startedAt: Date
    /// Nil when there's no timer. Blitz mode is optional.
    public var endsAt: Date?
    public var endedAt: Date?
    public var tasks: [BlitzTask]
    /// Optional so older saved blitzes (before rewards existed) still load.
    public var rewards: [Reward]?

    public init(id: UUID = UUID(), startedBy: Person, startedAt: Date, endsAt: Date?,
                tasks: [BlitzTask], rewards: [Reward] = []) {
        self.id = id
        self.startedBy = startedBy
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.endedAt = nil
        self.tasks = tasks
        self.rewards = rewards.isEmpty ? nil : rewards
    }

    public var allRewards: [Reward] { rewards ?? [] }

    public func reward(for person: Person) -> Reward? {
        allRewards.first { $0.person == person }
    }

    /// The chores a parent assigned to this person.
    public func assignedTasks(for person: Person) -> [BlitzTask] {
        tasks.filter { $0.assignedTo == person }
    }

    /// Earned once every assigned chore is done. No timer cutoff.
    public func hasEarned(_ reward: Reward) -> Bool {
        let mine = assignedTasks(for: reward.person)
        return !mine.isEmpty && mine.allSatisfy { $0.doneAt != nil }
    }

    /// Over when a parent ended it or every chore is done. Running past the
    /// timer does not end it.
    public var isOver: Bool {
        endedAt != nil || (!tasks.isEmpty && tasks.allSatisfy { $0.doneAt != nil })
    }

    public func tasks(in column: TaskColumn) -> [BlitzTask] {
        tasks.filter { $0.column == column }
    }

    /// Time left on the blitz timer, or nil when there's no timer.
    public func remaining(at now: Date) -> TimeInterval? {
        endsAt?.timeIntervalSince(now)
    }

    public var hasTimer: Bool { endsAt != nil }

    /// Finished chores per person, in family order, skipping people with none.
    public var doneByPerson: [PersonDone] {
        Person.allCases.compactMap { p in
            let mine = tasks.filter { $0.doneAt != nil && $0.claimedBy == p }
            return mine.isEmpty ? nil : PersonDone(person: p, tasks: mine)
        }
    }
}

/// "Finish your assigned chores and earn $20."
public struct Reward: Codable, Equatable, Sendable {
    public var person: Person
    /// Free text so it can be "$20", "pick dinner", etc.
    public var prize: String
    public var paidAt: Date?

    public init(person: Person, prize: String, paidAt: Date? = nil) {
        self.person = person
        self.prize = prize
        self.paidAt = paidAt
    }
}

/// Something in the prize pot. `weight` sets how likely it is relative to the others.
public struct Prize: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var weight: Int

    public init(id: UUID = UUID(), name: String, weight: Int) {
        self.id = id
        self.name = name
        self.weight = weight
    }

    /// "Nothing this time" style prizes don't need paying out.
    public var isPayable: Bool {
        let n = name.lowercased()
        return !(n.contains("nothing") || n.contains("try again"))
    }

    /// Small bonuses (Brandon, Nov 2026): mostly 50¢, sometimes $1.
    /// Starter pots from earlier builds; a saved copy of one is swapped for the current starter pot.
    static let legacyStarterNames: Set<Set<String>> = [
        ["$1", "$5", "Pick dinner", "Skip a chore", "$10", "$20 jackpot"],
        ["50¢", "$1"],
    ]

    /// Small bonuses (Brandon, Nov 2026): usually 5¢–$1, with a really rare $5.
    public static let starterPot: [Prize] = [
        Prize(name: "5¢", weight: 25),
        Prize(name: "10¢", weight: 25),
        Prize(name: "25¢", weight: 25),
        Prize(name: "50¢", weight: 15),
        Prize(name: "$1", weight: 9),
        Prize(name: "$5 jackpot", weight: 1),
    ]
}

public extension Prize {
    /// Money in a prize name, in cents: "5¢" → 5, "$1" → 100, "$5 jackpot" → 500,
    /// "$0.50" → 50. nil when there's no amount (e.g. "Pick dinner").
    static func cents(in text: String) -> Int? {
        let dollars = try! Regex(#"\$\s*(\d+)(?:\.(\d{1,2}))?"#)
        if let m = text.firstMatch(of: dollars) {
            let whole = m.output[1].substring.flatMap { Int($0) } ?? 0
            var frac = m.output[2].substring.map(String.init) ?? "0"
            if frac.count == 1 { frac += "0" }
            return whole * 100 + (Int(frac) ?? 0)
        }
        let cents = try! Regex(#"(\d+)\s*(?:¢|c\b|cents?\b)"#).ignoresCase()
        if let m = text.firstMatch(of: cents) {
            return m.output[1].substring.flatMap { Int($0) }
        }
        return nil
    }

    var cents: Int? { Prize.cents(in: name) }

    /// 135 → "$1.35", 50 → "50¢", 500 → "$5".
    static func format(cents: Int) -> String {
        if cents < 100 { return "\(cents)¢" }
        return cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%d.%02d", cents / 100, cents % 100)
    }
}

/// What someone has won from prize spins.
public struct Earnings: Equatable, Sendable {
    public var owedCents: Int
    public var paidCents: Int
    public var spins: Int
    public var totalCents: Int { owedCents + paidCents }
}

public struct Spin: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var person: Person
    public var prize: Prize
    public var blitzID: UUID
    public var at: Date
    public var paidAt: Date?

    public init(id: UUID = UUID(), person: Person, prize: Prize, blitzID: UUID, at: Date) {
        self.id = id
        self.person = person
        self.prize = prize
        self.blitzID = blitzID
        self.at = at
        self.paidAt = nil
    }
}

public struct PersonDone: Equatable, Sendable {
    public let person: Person
    public let tasks: [BlitzTask]
}

public struct HouseholdState: Codable, Equatable, Sendable {
    public var chores: [Chore]
    public var blitz: Blitz?
    /// Parents can hide chore minutes everywhere. Optional so older saved
    /// state still loads; nil means shown.
    public var showTimes: Bool?

    public var timesVisible: Bool { showTimes ?? true }

    // Game mode (all optional so older saved state still loads).
    public var gameMode: Bool?
    public var prizePot: [Prize]?
    /// Every spin ever won, newest last, so parents can see what's owed.
    public var spinLog: [Spin]?

    public var isGameMode: Bool { gameMode ?? false }
    public var prizes: [Prize] {
        // The first Game mode build shipped a bigger starter pot. If that's
        // what's saved, use the new 50¢/$1 pot instead.
        guard let pot = prizePot, !Prize.legacyStarterNames.contains(Set(pot.map(\.name))) else {
            return Prize.starterPot
        }
        return pot
    }
    public var allSpins: [Spin] { spinLog ?? [] }
    public var unpaidSpins: [Spin] { allSpins.filter { $0.paidAt == nil && $0.prize.isPayable } }

    /// Money won from spins: still owed, already paid, and the total.
    public func earnings(for person: Person) -> Earnings {
        let mine = allSpins.filter { $0.person == person }
        var e = Earnings(owedCents: 0, paidCents: 0, spins: mine.count)
        for s in mine {
            let c = s.prize.cents ?? 0
            if s.paidAt == nil { e.owedCents += c } else { e.paidCents += c }
        }
        return e
    }

    public init(chores: [Chore], blitz: Blitz? = nil) {
        self.chores = chores
        self.blitz = blitz
    }

    public static func starter() -> HouseholdState {
        HouseholdState(chores: SeedChores.all)
    }

    /// Rooms in the library, sorted, for pickers.
    public var rooms: [String] {
        Array(Set(chores.map(\.room))).sorted()
    }

    public var runningBlitz: Blitz? {
        guard let b = blitz, !b.isOver else { return nil }
        return b
    }
}

public enum ChoreError: Error, Equatable, LocalizedError {
    case parentsOnly
    case blitzAlreadyRunning
    case noBlitz
    case noChoresPicked
    case taskNotFound
    case choreNotFound
    case alreadyClaimed(Person)
    case notYourTask(Person)
    case assignedChore
    case rewardNotEarned
    case gameModeOff
    case noSpinsLeft
    case emptyPrizePot
    case notSpinner

    public var errorDescription: String? {
        switch self {
        case .parentsOnly: return "Only Brandon and Kira can do that."
        case .blitzAlreadyRunning: return "A blitz is already running."
        case .noBlitz: return "There's no blitz running."
        case .noChoresPicked: return "Pick at least one chore."
        case .taskNotFound: return "That chore isn't in this blitz anymore."
        case .choreNotFound: return "That chore was deleted."
        case .alreadyClaimed(let p): return "\(p.name) already has this one."
        case .notYourTask(let p): return "That's \(p.name)'s chore."
        case .assignedChore: return "This one was assigned to you. Ask Brandon or Kira to swap it."
        case .rewardNotEarned: return "Not earned yet. Some assigned chores aren't done."
        case .gameModeOff: return "Game mode is off."
        case .noSpinsLeft: return "No spins left. Finish another chore to earn one!"
        case .emptyPrizePot: return "The prize pot is empty. Ask Brandon or Kira to add prizes."
        case .notSpinner: return "Spins are just for Reagen."
        }
    }
}
