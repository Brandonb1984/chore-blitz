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
}
