import CloudKit
import ChoreKit
import SwiftUI

/// Keeps the whole household in one CloudKit public-database record.
/// Every change re-fetches the record, applies a ChoreKit rule, and saves
/// only if nobody else saved in between (otherwise it retries), so two
/// people can't both claim the same chore.
@MainActor
final class HouseholdStore: ObservableObject {
    static let containerID = "iCloud.com.brandonbourne.ChoreBlitz"

    @Published private(set) var state: HouseholdState?
    @Published private(set) var isLoading = true
    /// Plain-English problem to show, or nil when everything's fine.
    @Published var problem: String?

    /// Lazy so `-demo` runs never touch CloudKit (unsigned simulator builds
    /// have no iCloud entitlement and CKContainer traps at init).
    private lazy var db = CKContainer(identifier: HouseholdStore.containerID).publicCloudDatabase
    private let recordID = CKRecord.ID(recordName: "household-main")
    private let recordType = "Household"
    private let pollSeconds: Double
    private var pollTask: Task<Void, Never>?

    /// Launch with `-demo` to use a local sample blitz instead of iCloud
    /// (for simulator screenshots).
    /// `-demoFresh`: a just-started 12-chore blitz with nothing claimed.
    private let demoFresh = ProcessInfo.processInfo.arguments.contains("-demoFresh")
    private var demo: Bool { demoFresh || ProcessInfo.processInfo.arguments.contains("-demo") }

    init(pollSeconds: Double) {
        self.pollSeconds = pollSeconds
        if demo {
            state = demoFresh ? Self.freshDemoState() : Self.demoState()
            isLoading = false
        }
    }

    func startPolling() {
        if demo { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(self?.pollSeconds ?? 5))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        do {
            let rec = try await db.record(for: recordID)
            let fresh = try Self.decode(rec)
            if fresh != state { state = fresh }
            problem = nil
        } catch let e as CKError where e.code == .unknownItem {
            state = nil
            problem = nil
        } catch {
            problem = Self.describe(error)
        }
        isLoading = false
    }

    /// First launch: a parent creates the shared record with the starter chores.
    func setUp(by person: Person) async {
        guard person.isParent else { return }
        let rec = CKRecord(recordType: recordType, recordID: recordID)
        let starter = HouseholdState.starter()
        do {
            rec["state"] = try Self.encode(starter)
            _ = try await db.save(rec)
            state = starter
            problem = nil
        } catch let e as CKError where e.code == .serverRecordChanged {
            await refresh() // someone else set it up first
        } catch {
            problem = Self.describe(error)
        }
    }

    /// Applies a change and saves it. Returns false and sets `problem` if it failed.
    @discardableResult
    func apply(_ change: (inout HouseholdState) throws -> Void) async -> Bool {
        if demo, var next = state {
            do { try change(&next); state = next; return true }
            catch { problem = Self.describe(error); return false }
        }
        do {
            for _ in 0..<4 {
                let rec = try await db.record(for: recordID)
                var next = try Self.decode(rec)
                try change(&next)
                rec["state"] = try Self.encode(next)
                do {
                    let (results, _) = try await db.modifyRecords(
                        saving: [rec], deleting: [],
                        savePolicy: .ifServerRecordUnchanged, atomically: false)
                    _ = try results[recordID]?.get()
                    state = next
                    problem = nil
                    return true
                } catch let e as CKError where e.code == .serverRecordChanged {
                    continue // someone saved first; re-read and try again
                }
            }
            problem = "Too many people changed things at once. Try again."
        } catch {
            problem = Self.describe(error)
            await refresh()
        }
        return false
    }

    private static func demoState() -> HouseholdState {
        var s = HouseholdState.starter()
        let ids = s.chores.prefix(9).map(\.id)
        let now = Date()
        // No timer (the default), with Reagen assigned 2 chores for $20.
        let noTimer = ProcessInfo.processInfo.arguments.contains("-demoNoTimer")
        try? s.startBlitz(by: .kira, choreIDs: Array(ids), minutes: noTimer ? nil : 30,
                          now: now.addingTimeInterval(-11 * 60),
                          assignments: [ids[2]: .reagen, ids[4]: .reagen], prizes: [.reagen: "$20"])
        let t = s.blitz!.tasks.map(\.id)
        try? s.claim(taskID: t[0], by: .braden)
        try? s.claim(taskID: t[2], by: .reagen)
        try? s.claim(taskID: t[6], by: .kira)
        try? s.markDone(taskID: t[1], by: .braden, now: now)
        try? s.markDone(taskID: t[4], by: .reagen, now: now)
        try? s.markDone(taskID: t[8], by: .brandon, now: now)
        return s
    }

    private static func freshDemoState() -> HouseholdState {
        var s = HouseholdState.starter()
        let ids = s.chores.prefix(12).map(\.id)
        try? s.startBlitz(by: .kira, choreIDs: Array(ids), minutes: 45, now: Date().addingTimeInterval(-60))
        return s
    }

    /// Whether chore minutes should be shown (a parent can turn this off).
    var showTimes: Bool { state?.timesVisible ?? true }

    // MARK: Encoding

    private static func encode(_ s: HouseholdState) throws -> CKRecordValue {
        try JSONEncoder().encode(s) as NSData
    }

    private static func decode(_ rec: CKRecord) throws -> HouseholdState {
        guard let data = rec["state"] as? Data else { return .starter() }
        return try JSONDecoder().decode(HouseholdState.self, from: data)
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? ChoreError { return e.localizedDescription }
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to make changes."
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "Can't reach iCloud right now. Check Wi-Fi; it'll catch up."
        case .permissionFailure:
            return "iCloud won't let this account edit the chore list yet. Brandon needs to finish the iCloud setup."
        default:
            return "iCloud error: \(ck.localizedDescription)"
        }
    }
}
