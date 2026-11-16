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
    public static let starterPot: [Prize] = [
        Prize(name: "50¢", weight: 60),
        Prize(name: "$1", weight: 40),
    ]
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
    public var prizes: [Prize] { prizePot ?? Prize.starterPot }
    public var allSpins: [Spin] { spinLog ?? [] }
    public var unpaidSpins: [Spin] { allSpins.filter { $0.paidAt == nil && $0.prize.isPayable } }

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
