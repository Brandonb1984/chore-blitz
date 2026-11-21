import Foundation

/// Every change to the shared state goes through these, so the rules are the
/// same on every phone and can be tested without iCloud.
public extension HouseholdState {
    // MARK: Chore library (parents only)

    mutating func addChore(_ chore: Chore, by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        chores.append(chore)
    }

    mutating func updateChore(_ chore: Chore, by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard let i = chores.firstIndex(where: { $0.id == chore.id }) else { throw ChoreError.choreNotFound }
        chores[i] = chore
    }

    mutating func deleteChore(id: UUID, by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        chores.removeAll { $0.id == id }
    }

    /// Removes the built-in starter chores (matched by name), keeping the family's own.
    mutating func removeStarterChores(by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        let starterNames = Set(SeedChores.all.map(\.name))
        chores.removeAll { starterNames.contains($0.name) }
    }

    mutating func setShowTimes(_ show: Bool, by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        showTimes = show
    }

    // MARK: Blitz

    /// Starts a cleanup from library chores (in the order given) plus one-off
    /// chores that aren't saved to the library. `minutes` nil means no
    /// timer; a number turns on Blitz mode with that countdown.
    ///
    /// `assignments` maps a chore id to the person it's assigned to; those
    /// chores start out claimed by that person. `prizes` sets a reward per
    /// person, kept only if that person has at least one assigned chore.
    mutating func startBlitz(by person: Person, choreIDs: [UUID], oneOffs: [Chore] = [],
                             minutes: Int?, now: Date,
                             assignments: [UUID: Person] = [:], prizes: [Person: String] = [:]) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        if runningBlitz != nil { throw ChoreError.blitzAlreadyRunning }
        bankUnopenedChests()
        let picked = choreIDs.compactMap { id in chores.first { $0.id == id } } + oneOffs
        guard !picked.isEmpty else { throw ChoreError.noChoresPicked }
        let tasks: [BlitzTask] = picked.map { chore in
            var t = BlitzTask(from: chore)
            if let who = assignments[chore.id] {
                t.assignedTo = who
                t.claimedBy = who
            }
            return t
        }
        let rewards: [Reward] = Person.allCases.compactMap { p in
            let prize = (prizes[p] ?? "").trimmingCharacters(in: .whitespaces)
            guard !prize.isEmpty, tasks.contains(where: { $0.assignedTo == p }) else { return nil }
            return Reward(person: p, prize: prize)
        }
        blitz = Blitz(startedBy: person, startedAt: now,
                      endsAt: minutes.map { now.addingTimeInterval(TimeInterval($0 * 60)) },
                      tasks: tasks, rewards: rewards)
    }

    /// A parent marks an earned reward as paid. Works after the blitz is over.
    mutating func markRewardPaid(for earner: Person, by person: Person, now: Date) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard let b = blitz, let i = b.allRewards.firstIndex(where: { $0.person == earner }) else {
            throw ChoreError.noBlitz
        }
        guard b.hasEarned(b.allRewards[i]) else { throw ChoreError.rewardNotEarned }
        blitz!.rewards![i].paidAt = now
    }

    /// Parents add chores to a list that's already going.
    mutating func addTasks(_ new: [Chore], by person: Person, assignedTo: Person? = nil) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard runningBlitz != nil else { throw ChoreError.noBlitz }
        for chore in new {
            var t = BlitzTask(from: chore)
            if let who = assignedTo { t.assignedTo = who; t.claimedBy = who }
            blitz!.tasks.append(t)
        }
    }

    /// Parents take a chore off a list that's already going.
    mutating func removeTask(taskID: UUID, by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard runningBlitz != nil else { throw ChoreError.noBlitz }
        blitz!.tasks.removeAll { $0.id == taskID }
    }

    mutating func endBlitz(by person: Person, now: Date) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard blitz != nil else { throw ChoreError.noBlitz }
        if blitz?.endedAt == nil { blitz?.endedAt = now }
    }

    /// Clears a finished blitz so the TV goes back to its idle screen.
    mutating func clearBlitz(by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        bankUnopenedChests()
        blitz = nil
    }

    mutating func claim(taskID: UUID, by person: Person) throws {
        let i = try runningTaskIndex(taskID)
        if let owner = blitz!.tasks[i].claimedBy {
            if owner == person { return }
            throw ChoreError.alreadyClaimed(owner)
        }
        blitz!.tasks[i].claimedBy = person
    }

    /// The claimer can let go of an unfinished chore; a parent can free anyone's.
    mutating func unclaim(taskID: UUID, by person: Person) throws {
        let i = try runningTaskIndex(taskID)
        let task = blitz!.tasks[i]
        guard task.doneAt == nil else { return }
        if let owner = task.claimedBy, owner != person, !person.isParent {
            throw ChoreError.notYourTask(owner)
        }
        if task.assignedTo != nil && !person.isParent { throw ChoreError.assignedChore }
        blitz!.tasks[i].claimedBy = nil
        blitz!.tasks[i].assignedTo = nil
    }

    /// Done on an open chore claims it for you first. A parent can mark
    /// anyone's chore done; the credit stays with whoever claimed it.
    mutating func markDone(taskID: UUID, by person: Person, now: Date) throws {
        let i = try runningTaskIndex(taskID)
        let task = blitz!.tasks[i]
        if task.doneAt != nil { return }
        if let owner = task.claimedBy, owner != person, !person.isParent {
            throw ChoreError.notYourTask(owner)
        }
        if task.claimedBy == nil { blitz!.tasks[i].claimedBy = person }
        blitz!.tasks[i].doneAt = now
    }

    mutating func markNotDone(taskID: UUID, by person: Person) throws {
        guard let b = blitz, let i = b.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw ChoreError.taskNotFound
        }
        if let owner = b.tasks[i].claimedBy, owner != person, !person.isParent {
            throw ChoreError.notYourTask(owner)
        }
        blitz!.tasks[i].doneAt = nil
    }

    private func runningTaskIndex(_ taskID: UUID) throws -> Int {
        guard let b = runningBlitz else { throw ChoreError.noBlitz }
        guard let i = b.tasks.firstIndex(where: { $0.id == taskID }) else { throw ChoreError.taskNotFound }
        return i
    }

    // MARK: Game mode

    /// Who earns spins. Only Reagen gets paid prizes.
    static let spinners: Set<Person> = [.reagen]

    /// Parents, and Reagen himself (Brandon said he can), may flip Game mode.
    static func canSetGameMode(_ person: Person) -> Bool {
        person.isParent || spinners.contains(person)
    }

    mutating func setGameMode(_ on: Bool, by person: Person) throws {
        guard Self.canSetGameMode(person) else { throw ChoreError.parentsOnly }
        gameMode = on
    }

    mutating func setPrizePot(_ pot: [Prize], by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        prizePot = pot.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.weight > 0 }
    }

    mutating func setTVMusic(_ on: Bool, by person: Person) throws {
        guard Self.canSetGameMode(person) else { throw ChoreError.parentsOnly }
        tvMusic = on
    }

    /// When true, longer chores earn more loot chests (see `chests(forMinutes:)`),
    /// so grabbing only the quickest chores isn't the best deal.
    static let bigChoresEarnMore = true

    /// Loot chests a finished chore is worth: one per 10 minutes, at least 1, at most 3.
    static func chests(forMinutes minutes: Int) -> Int {
        guard bigChoresEarnMore else { return 1 }
        return min(3, max(1, (minutes + 5) / 10))
    }

    /// Spins logged against banked chests (not tied to a list) use this id.
    static let bankedSpinID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Chests earned on the current (or just finished) list and not opened yet.
    private func chestsLeftInList(for person: Person) -> Int {
        guard let b = blitz else { return 0 }
        let earned = b.tasks.filter { $0.doneAt != nil && $0.claimedBy == person }
            .reduce(0) { $0 + Self.chests(forMinutes: $1.minutes) }
        let used = allSpins.filter { $0.person == person && $0.blitzID == b.id }.count
        return max(0, earned - used)
    }

    /// Chests carried over from earlier lists.
    func bankedChests(for person: Person) -> Int {
        max(0, spinCredits?[person.rawValue] ?? 0)
    }

    /// Called before the current list goes away, so unopened chests carry over.
    private mutating func bankUnopenedChests() {
        guard isGameMode else { return }
        for p in Self.spinners {
            let left = chestsLeftInList(for: p)
            guard left > 0 else { continue }
            var credits = spinCredits ?? [:]
            credits[p.rawValue, default: 0] += left
            spinCredits = credits
        }
    }

    /// Loot chests this person can open now: the ones earned on the current
    /// (or just finished) list, plus any carried over from earlier lists.
    func spinsLeft(for person: Person) -> Int {
        guard isGameMode, Self.spinners.contains(person) else { return 0 }
        return chestsLeftInList(for: person) + bankedChests(for: person)
    }

    /// True for the pot's big prize: named "jackpot", or the top money prize
    /// when it comes up 5% of the time or less.
    func isJackpot(_ prize: Prize) -> Bool {
        if prize.name.lowercased().contains("jackpot") { return true }
        let pot = prizes
        let total = pot.reduce(0) { $0 + $1.weight }
        guard pot.count > 1, total > 0, let cents = prize.cents,
              let top = pot.compactMap(\.cents).max(), cents == top else { return false }
        return Double(prize.weight) / Double(total) <= 0.05
    }

    /// Picks a prize by weight. `roll` is in 0..<1 (random in the app, fixed in tests).
    static func pick(from pot: [Prize], roll: Double) -> Prize? {
        let total = pot.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var target = min(max(roll, 0), 0.999_999) * Double(total)
        for p in pot {
            target -= Double(p.weight)
            if target < 0 { return p }
        }
        return pot.last
    }

    @discardableResult
    mutating func spin(by person: Person, roll: Double, now: Date) throws -> Spin {
        guard isGameMode else { throw ChoreError.gameModeOff }
        guard Self.spinners.contains(person) else { throw ChoreError.notSpinner }
        let inList = chestsLeftInList(for: person)
        guard inList + bankedChests(for: person) > 0 else { throw ChoreError.noSpinsLeft }
        guard let prize = Self.pick(from: prizes, roll: roll) else { throw ChoreError.emptyPrizePot }
        let s: Spin
        if inList > 0, let b = blitz {
            s = Spin(person: person, prize: prize, blitzID: b.id, at: now)
        } else {
            // Open a chest carried over from an earlier list.
            var credits = spinCredits ?? [:]
            credits[person.rawValue] = bankedChests(for: person) - 1
            spinCredits = credits
            s = Spin(person: person, prize: prize, blitzID: Self.bankedSpinID, at: now)
        }
        spinLog = allSpins + [s]
        return s
    }

    mutating func markSpinPaid(_ spinID: UUID, by person: Person, now: Date) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard var log = spinLog, let i = log.firstIndex(where: { $0.id == spinID }) else { return }
        log[i].paidAt = now
        spinLog = log
    }

    /// A parent pays everything this person is owed from loot chests in one go.
    mutating func markAllSpinsPaid(for earner: Person, by person: Person, now: Date) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard var log = spinLog else { return }
        for i in log.indices where log[i].person == earner && log[i].paidAt == nil {
            log[i].paidAt = now
        }
        spinLog = log
    }
}
