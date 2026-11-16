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

    mutating func endBlitz(by person: Person, now: Date) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
        guard blitz != nil else { throw ChoreError.noBlitz }
        if blitz?.endedAt == nil { blitz?.endedAt = now }
    }

    /// Clears a finished blitz so the TV goes back to its idle screen.
    mutating func clearBlitz(by person: Person) throws {
        guard person.isParent else { throw ChoreError.parentsOnly }
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
}
