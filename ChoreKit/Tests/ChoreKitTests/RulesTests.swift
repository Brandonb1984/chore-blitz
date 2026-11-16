import XCTest
@testable import ChoreKit

final class RulesTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let dishes = Chore(name: "Dishes", room: "Kitchen", minutes: 10, steps: ["Load"])
    let trash = Chore(name: "Trash", room: "Kitchen", minutes: 5, steps: ["Take out"])

    func running() throws -> HouseholdState {
        var s = HouseholdState(chores: [dishes, trash])
        try s.startBlitz(by: .kira, choreIDs: [dishes.id, trash.id], minutes: 30, now: t0)
        return s
    }

    func testSeedChoresAllHaveSteps() {
        XCTAssertGreaterThanOrEqual(SeedChores.all.count, 20)
        XCTAssertTrue(SeedChores.all.allSatisfy { !$0.steps.isEmpty && !$0.name.isEmpty })
    }

    func testOnlyParentsEditLibrary() {
        var s = HouseholdState(chores: [])
        XCTAssertThrowsError(try s.addChore(dishes, by: .braden)) { XCTAssertEqual($0 as? ChoreError, .parentsOnly) }
        XCTAssertNoThrow(try s.addChore(dishes, by: .kira))
        var edited = dishes; edited.name = "Do the dishes"
        XCTAssertNoThrow(try s.updateChore(edited, by: .brandon))
        XCTAssertEqual(s.chores.first?.name, "Do the dishes")
        XCTAssertThrowsError(try s.deleteChore(id: dishes.id, by: .reagen))
        XCTAssertNoThrow(try s.deleteChore(id: dishes.id, by: .kira))
        XCTAssertTrue(s.chores.isEmpty)
    }

    func testStartBlitzSetsTimerAndTasks() throws {
        let s = try running()
        XCTAssertEqual(s.blitz?.endsAt, t0.addingTimeInterval(1800))
        XCTAssertEqual(s.blitz?.tasks.map(\.name), ["Dishes", "Trash"])
        XCTAssertEqual(s.blitz?.tasks(in: .open).count, 2)
    }

    func testNoTimerByDefaultOption() throws {
        var s = HouseholdState(chores: [dishes])
        try s.startBlitz(by: .kira, choreIDs: [dishes.id], minutes: nil, now: t0)
        XCTAssertNil(s.blitz?.endsAt)
        XCTAssertNil(s.blitz?.remaining(at: t0))
        XCTAssertEqual(s.blitz?.hasTimer, false)
        XCTAssertNotNil(s.runningBlitz, "without a timer it runs until done or ended")
    }

    func testStartBlitzRules() throws {
        var s = HouseholdState(chores: [dishes])
        XCTAssertThrowsError(try s.startBlitz(by: .braden, choreIDs: [dishes.id], minutes: 30, now: t0))
        XCTAssertThrowsError(try s.startBlitz(by: .kira, choreIDs: [], minutes: 30, now: t0)) {
            XCTAssertEqual($0 as? ChoreError, .noChoresPicked)
        }
        let oneOff = Chore(name: "Clean the grill", room: "Outside", minutes: 15, steps: ["Scrape"])
        try s.startBlitz(by: .kira, choreIDs: [], oneOffs: [oneOff], minutes: 45, now: t0)
        XCTAssertEqual(s.blitz?.tasks.map(\.name), ["Clean the grill"])
        XCTAssertEqual(s.chores.count, 1, "one-offs aren't added to the library")
    }

    func testStartWhileRunning() throws {
        var s = try running()
        XCTAssertThrowsError(try s.startBlitz(by: .brandon, choreIDs: [dishes.id], minutes: 30, now: t0)) {
            XCTAssertEqual($0 as? ChoreError, .blitzAlreadyRunning)
        }
    }

    func testStartAfterFinished() throws {
        var s = try running()
        try s.endBlitz(by: .brandon, now: t0.addingTimeInterval(600))
        XCTAssertNil(s.runningBlitz)
        XCTAssertNoThrow(try s.startBlitz(by: .brandon, choreIDs: [trash.id], minutes: 60, now: t0))
        XCTAssertEqual(s.blitz?.tasks.count, 1)
    }

    func testClaimTakenBySomeoneElse() throws {
        var s = try running()
        let id = s.blitz!.tasks[0].id
        try s.claim(taskID: id, by: .braden)
        XCTAssertThrowsError(try s.claim(taskID: id, by: .reagen)) {
            XCTAssertEqual($0 as? ChoreError, .alreadyClaimed(.braden))
        }
        XCTAssertNoThrow(try s.claim(taskID: id, by: .braden), "claiming your own again is fine")
        XCTAssertEqual(s.blitz?.tasks[0].column, .inProgress)
    }

    func testUnclaim() throws {
        var s = try running()
        let id = s.blitz!.tasks[0].id
        try s.claim(taskID: id, by: .braden)
        XCTAssertThrowsError(try s.unclaim(taskID: id, by: .reagen))
        try s.unclaim(taskID: id, by: .braden)
        XCTAssertNil(s.blitz?.tasks[0].claimedBy)
        try s.claim(taskID: id, by: .reagen)
        try s.unclaim(taskID: id, by: .kira)
        XCTAssertNil(s.blitz?.tasks[0].claimedBy, "parents can free a chore")
    }

    func testDoneOnOpenTaskClaimsIt() throws {
        var s = try running()
        let id = s.blitz!.tasks[1].id
        try s.markDone(taskID: id, by: .reagen, now: t0.addingTimeInterval(60))
        XCTAssertEqual(s.blitz?.tasks[1].claimedBy, .reagen)
        XCTAssertEqual(s.blitz?.tasks[1].column, .done)
    }

    func testDoneOnSomeoneElsesTask() throws {
        var s = try running()
        let id = s.blitz!.tasks[0].id
        try s.claim(taskID: id, by: .braden)
        XCTAssertThrowsError(try s.markDone(taskID: id, by: .reagen, now: t0)) {
            XCTAssertEqual($0 as? ChoreError, .notYourTask(.braden))
        }
        try s.markDone(taskID: id, by: .kira, now: t0)
        XCTAssertEqual(s.blitz?.tasks[0].claimedBy, .braden, "credit stays with Braden")
    }

    func testAllDoneEndsBlitzAndSummarizes() throws {
        var s = try running()
        let ids = s.blitz!.tasks.map(\.id)
        try s.markDone(taskID: ids[0], by: .braden, now: t0)
        XCTAssertNotNil(s.runningBlitz)
        try s.markDone(taskID: ids[1], by: .reagen, now: t0)
        XCTAssertNil(s.runningBlitz)
        XCTAssertEqual(s.blitz?.isOver, true)
        XCTAssertEqual(s.blitz?.doneByPerson.map(\.person), [.braden, .reagen])
        XCTAssertThrowsError(try s.claim(taskID: ids[0], by: .kira)) {
            XCTAssertEqual($0 as? ChoreError, .noBlitz)
        }
    }

    func testMarkNotDone() throws {
        var s = try running()
        let id = s.blitz!.tasks[0].id
        try s.markDone(taskID: id, by: .braden, now: t0)
        try s.markNotDone(taskID: id, by: .braden)
        XCTAssertEqual(s.blitz?.tasks[0].column, .inProgress)
    }

    func testCodableRoundTrip() throws {
        var s = try running()
        try s.claim(taskID: s.blitz!.tasks[0].id, by: .reagen)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(HouseholdState.self, from: data), s)
    }

    func testCountdown() {
        XCTAssertEqual(countdownText(1800), "30:00")
        XCTAssertEqual(countdownText(245), "4:05")
        XCTAssertEqual(countdownText(0.2), "0:01")
    }

    func testCountdownOverTime() {
        XCTAssertEqual(countdownText(0), "+0:00")
        XCTAssertEqual(countdownText(-90), "+1:30")
        XCTAssertEqual(countdownText(-3725), "+62:05")
    }

    // MARK: Rewards

    func rewardBlitz() throws -> HouseholdState {
        var s = HouseholdState(chores: [dishes, trash])
        try s.startBlitz(by: .brandon, choreIDs: [dishes.id, trash.id], minutes: 45, now: t0,
                         assignments: [dishes.id: .reagen, trash.id: .reagen], prizes: [.reagen: " $20 "])
        return s
    }

    func testAssignedChoresStartClaimedWithReward() throws {
        let s = try rewardBlitz()
        let b = s.blitz!
        XCTAssertEqual(b.tasks.map(\.claimedBy), [.reagen, .reagen])
        XCTAssertEqual(b.assignedTasks(for: .reagen).count, 2)
        XCTAssertEqual(b.reward(for: .reagen)?.prize, "$20")
        XCTAssertFalse(b.hasEarned(b.reward(for: .reagen)!))
    }

    func testPrizeWithoutAssignedChoresIsDropped() throws {
        var s = HouseholdState(chores: [dishes])
        try s.startBlitz(by: .kira, choreIDs: [dishes.id], minutes: 30, now: t0, prizes: [.braden: "$20"])
        XCTAssertNil(s.blitz?.reward(for: .braden))
    }

    func testEarnedWhenAllAssignedDoneEvenPastTimer() throws {
        var s = try rewardBlitz()
        let ids = s.blitz!.tasks.map(\.id)
        try s.markDone(taskID: ids[0], by: .reagen, now: t0)
        XCTAssertFalse(s.blitz!.hasEarned(s.blitz!.reward(for: .reagen)!))
        try s.markDone(taskID: ids[1], by: .reagen, now: t0.addingTimeInterval(3 * 3600))
        XCTAssertTrue(s.blitz!.hasEarned(s.blitz!.reward(for: .reagen)!))
    }

    func testOnlyAssignedChoresCount() throws {
        var s = HouseholdState(chores: [dishes, trash])
        try s.startBlitz(by: .brandon, choreIDs: [dishes.id, trash.id], minutes: 30, now: t0,
                         assignments: [dishes.id: .reagen], prizes: [.reagen: "$20"])
        let ids = s.blitz!.tasks.map(\.id)
        try s.markDone(taskID: ids[1], by: .reagen, now: t0) // an extra chore he grabbed
        XCTAssertFalse(s.blitz!.hasEarned(s.blitz!.reward(for: .reagen)!))
    }

    func testCantGiveBackAssignedChore() throws {
        var s = try rewardBlitz()
        let id = s.blitz!.tasks[0].id
        XCTAssertThrowsError(try s.unclaim(taskID: id, by: .reagen)) {
            XCTAssertEqual($0 as? ChoreError, .assignedChore)
        }
        try s.unclaim(taskID: id, by: .kira)
        XCTAssertNil(s.blitz?.tasks[0].assignedTo)
    }

    func testMarkRewardPaid() throws {
        var s = try rewardBlitz()
        XCTAssertThrowsError(try s.markRewardPaid(for: .reagen, by: .brandon, now: t0)) {
            XCTAssertEqual($0 as? ChoreError, .rewardNotEarned)
        }
        for id in s.blitz!.tasks.map(\.id) { try s.markDone(taskID: id, by: .reagen, now: t0) }
        XCTAssertThrowsError(try s.markRewardPaid(for: .reagen, by: .reagen, now: t0))
        try s.markRewardPaid(for: .reagen, by: .brandon, now: t0)
        XCTAssertEqual(s.blitz?.reward(for: .reagen)?.paidAt, t0)
    }

    func testOldSavedStateWithoutRewardsStillLoads() throws {
        var s = try running()
        s.blitz?.rewards = nil
        var json = String(data: try JSONEncoder().encode(s), encoding: .utf8)!
        json = json.replacingOccurrences(of: ",\"rewards\":null", with: "")
        let back = try JSONDecoder().decode(HouseholdState.self, from: Data(json.utf8))
        XCTAssertEqual(back.blitz?.allRewards, [])
    }

    func testShowTimesToggle() throws {
        var s = HouseholdState(chores: [])
        XCTAssertTrue(s.timesVisible)
        XCTAssertThrowsError(try s.setShowTimes(false, by: .reagen))
        try s.setShowTimes(false, by: .kira)
        XCTAssertFalse(s.timesVisible)
    }

    func testRemoveStarterChoresKeepsOwn() throws {
        var s = HouseholdState.starter()
        let mine = Chore(name: "Wipe the high chair", room: "Kitchen", minutes: 5, steps: ["Wipe tray"])
        try s.addChore(mine, by: .kira)
        XCTAssertThrowsError(try s.removeStarterChores(by: .reagen))
        try s.removeStarterChores(by: .kira)
        XCTAssertEqual(s.chores, [mine])
    }

    func testEditListAfterStart() throws {
        var s = try running()
        let fridge = Chore(name: "Clean the refrigerator", room: "Kitchen", minutes: 20, steps: ["Toss old food"])
        XCTAssertThrowsError(try s.addTasks([fridge], by: .reagen))
        try s.addTasks([fridge], by: .kira)
        XCTAssertEqual(s.blitz?.tasks.last?.name, "Clean the refrigerator")
        let id = s.blitz!.tasks.last!.id
        try s.claim(taskID: id, by: .brandon)
        XCTAssertEqual(s.blitz?.tasks.last?.claimedBy, .brandon)
        XCTAssertThrowsError(try s.removeTask(taskID: id, by: .braden))
        try s.removeTask(taskID: id, by: .kira)
        XCTAssertEqual(s.blitz?.tasks.count, 2)
    }

    // MARK: Game mode

    func gameBlitz() throws -> HouseholdState {
        var s = try running()
        try s.setGameMode(true, by: .kira)
        try s.setPrizePot([Prize(name: "$1", weight: 3), Prize(name: "$20", weight: 1)], by: .kira)
        return s
    }

    func testPickByWeight() {
        let pot = [Prize(name: "a", weight: 3), Prize(name: "b", weight: 1)]
        XCTAssertEqual(HouseholdState.pick(from: pot, roll: 0.0)?.name, "a")
        XCTAssertEqual(HouseholdState.pick(from: pot, roll: 0.74)?.name, "a")
        XCTAssertEqual(HouseholdState.pick(from: pot, roll: 0.75)?.name, "b")
        XCTAssertEqual(HouseholdState.pick(from: pot, roll: 1.0)?.name, "b")
        XCTAssertNil(HouseholdState.pick(from: [], roll: 0.5))
    }

    func testSpinsEarnedPerFinishedChore() throws {
        var s = try gameBlitz()
        XCTAssertEqual(s.spinsLeft(for: .reagen), 0)
        XCTAssertThrowsError(try s.spin(by: .reagen, roll: 0.1, now: t0)) {
            XCTAssertEqual($0 as? ChoreError, .noSpinsLeft)
        }
        let ids = s.blitz!.tasks.map(\.id)
        try s.markDone(taskID: ids[0], by: .reagen, now: t0)
        try s.markDone(taskID: ids[1], by: .reagen, now: t0)
        XCTAssertEqual(s.spinsLeft(for: .reagen), 2)
        let first = try s.spin(by: .reagen, roll: 0.9, now: t0)
        XCTAssertEqual(first.prize.name, "$20")
        XCTAssertEqual(s.spinsLeft(for: .reagen), 1)
        _ = try s.spin(by: .reagen, roll: 0.1, now: t0)
        XCTAssertEqual(s.spinsLeft(for: .reagen), 0)
        XCTAssertEqual(s.unpaidSpins.count, 2)
    }

    func testOnlyReagenSpinsAndOnlyInGameMode() throws {
        var s = try running()
        try s.markDone(taskID: s.blitz!.tasks[0].id, by: .reagen, now: t0)
        XCTAssertThrowsError(try s.spin(by: .reagen, roll: 0.1, now: t0)) {
            XCTAssertEqual($0 as? ChoreError, .gameModeOff)
        }
        try s.setGameMode(true, by: .brandon)
        try s.markDone(taskID: s.blitz!.tasks[1].id, by: .braden, now: t0)
        XCTAssertEqual(s.spinsLeft(for: .braden), 0)
        XCTAssertThrowsError(try s.spin(by: .braden, roll: 0.1, now: t0)) {
            XCTAssertEqual($0 as? ChoreError, .notSpinner)
        }
        XCTAssertThrowsError(try s.setGameMode(false, by: .braden))
        try s.setGameMode(false, by: .reagen)
        XCTAssertFalse(s.isGameMode)
    }

    func testSpinsStillUsableAfterListFinishes() throws {
        var s = try gameBlitz()
        for id in s.blitz!.tasks.map(\.id) { try s.markDone(taskID: id, by: .reagen, now: t0) }
        XCTAssertNil(s.runningBlitz)
        XCTAssertEqual(s.spinsLeft(for: .reagen), 2)
    }

    func testMarkSpinPaid() throws {
        var s = try gameBlitz()
        try s.markDone(taskID: s.blitz!.tasks[0].id, by: .reagen, now: t0)
        let spin = try s.spin(by: .reagen, roll: 0.1, now: t0)
        XCTAssertThrowsError(try s.markSpinPaid(spin.id, by: .reagen, now: t0))
        try s.markSpinPaid(spin.id, by: .kira, now: t0)
        XCTAssertTrue(s.unpaidSpins.isEmpty)
    }

    func testOldStarterPotIsReplacedByBonuses() throws {
        var s = HouseholdState.starter()
        let old = ["$1", "$5", "Pick dinner", "Skip a chore", "$10", "$20 jackpot"].map { Prize(name: $0, weight: 1) }
        try s.setPrizePot(old, by: .kira)
        XCTAssertEqual(s.prizes.map(\.name), Prize.starterPot.map(\.name))
        try s.setPrizePot([Prize(name: "50¢", weight: 60), Prize(name: "$1", weight: 40)], by: .kira)
        XCTAssertEqual(s.prizes.map(\.name), Prize.starterPot.map(\.name))
        XCTAssertEqual(Prize.starterPot.last?.name, "$5 jackpot")
        try s.setPrizePot([Prize(name: "$2", weight: 1)], by: .kira)
        XCTAssertEqual(s.prizes.map(\.name), ["$2"])
    }
}
