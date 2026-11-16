# Chore Blitz Implementation Plan

> Execution: native (Claude writes the source; a Remote Control session on Brandon's MacBook generates, tests, builds and installs).

**Goal:** iPhone app + Apple TV board for 30–60 min family cleaning blitzes, synced through CloudKit.
**Architecture:** All shared state lives in ONE CloudKit public-database record (`Household` / `household-main`) holding JSON `HouseholdState`. Every change is fetch → pure mutation → save with `.ifServerRecordUnchanged`, retried on conflict, so two people can't claim the same chore. Pure logic lives in the `ChoreKit` Swift package (unit tested with `swift test`); the apps are thin SwiftUI layers.
**Tech stack:** Swift 5.9+, SwiftUI, CloudKit, XcodeGen, iOS 17 / tvOS 17.
**Spec:** design.md (same folder)

## Global constraints
- Team 85QS8LM6D3, automatic signing. Container `iCloud.com.brandonbourne.ChoreBlitz`.
- People are fixed: Brandon, Kira (parents), Braden, Reagen.
- Only parents add/edit/delete chores, start/end a blitz. Anyone claims, unclaims own, marks done.
- Timer choices 30 / 45 / 60 minutes. No points.
- Debug builds use CloudKit Development; Release (TestFlight/Ad Hoc/installs for family) uses Production.

## Review focus
1. Two people claim the same chore at once: second gets "Reagen already has this", not a silent overwrite. (ChoreKit test `testClaimTakenBySomeoneElse` + store conflict retry.)
2. Timer runs past zero: board shows "+m:ss" over time, blitz keeps going until done or a parent ends it. (`testCountdownOverTime`.)
3. Starting a blitz while one is running is refused; a finished one is replaced. (`testStartWhileRunning`, `testStartAfterFinished`.)
4. Boy taps Done on an open chore: it becomes his and done in one step. (`testDoneOnOpenTaskClaimsIt`.)
5. Phone not signed in to iCloud / no network: clear message, nothing lost on screen. (Store maps CKError codes to plain text.)

## Tasks
1. **ChoreKit models + rules** — `ChoreKit/Sources/ChoreKit/{Models,Rules,Format,SeedChores}.swift`, tests in `ChoreKit/Tests/ChoreKitTests`. Run `swift test` in ChoreKit → all pass.
2. **CloudKit store** — `Shared/HouseholdStore.swift` (`refresh()`, `setUp(by:)`, `apply(_:)`, polling). Verified by running the Debug iOS app in the simulator: set up creates the record.
3. **iPhone app** — `iOS/*.swift`: who-are-you, Blitz tab (live list, claim, steps, done, parent start/end), Chores tab (big "+ New chore", editor). Build for simulator, screenshot.
4. **Apple TV board** — `tvOS/*.swift`: idle / running (countdown + 3 columns) / finished summary. Build for tvOS simulator, screenshot.
5. **CloudKit schema** — after first Debug run: grant `_icloud` Read+Write on `Household`, deploy schema to Production (CloudKit Console).
6. **Ship** — Release install on Brandon's phone + Bedroom Apple TV; TestFlight to "Family" for Kira; Ad Hoc for Braden/Reagen when their UDIDs are registered.
