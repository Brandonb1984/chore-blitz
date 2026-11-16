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

    public init(from chore: Chore) {
        id = UUID()
        choreID = chore.id
        name = chore.name
        room = chore.room
        minutes = chore.minutes
        steps = chore.steps
        claimedBy = nil
        doneAt = nil
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
    public var endsAt: Date
    public var endedAt: Date?
    public var tasks: [BlitzTask]

    public init(id: UUID = UUID(), startedBy: Person, startedAt: Date, endsAt: Date, tasks: [BlitzTask]) {
        self.id = id
        self.startedBy = startedBy
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.endedAt = nil
        self.tasks = tasks
    }

    /// Over when a parent ended it or every chore is done. Running past the
    /// timer does not end it.
    public var isOver: Bool {
        endedAt != nil || (!tasks.isEmpty && tasks.allSatisfy { $0.doneAt != nil })
    }

    public func tasks(in column: TaskColumn) -> [BlitzTask] {
        tasks.filter { $0.column == column }
    }

    public func remaining(at now: Date) -> TimeInterval {
        endsAt.timeIntervalSince(now)
    }

    /// Finished chores per person, in family order, skipping people with none.
    public var doneByPerson: [PersonDone] {
        Person.allCases.compactMap { p in
            let mine = tasks.filter { $0.doneAt != nil && $0.claimedBy == p }
            return mine.isEmpty ? nil : PersonDone(person: p, tasks: mine)
        }
    }
}

public struct PersonDone: Equatable, Sendable {
    public let person: Person
    public let tasks: [BlitzTask]
}

public struct HouseholdState: Codable, Equatable, Sendable {
    public var chores: [Chore]
    public var blitz: Blitz?

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
        }
    }
}
