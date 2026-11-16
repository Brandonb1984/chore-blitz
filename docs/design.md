# Chore Blitz — design (approved by Brandon 2026-11-16)

## Why
Brandon, Kira, Braden (21) and Reagen (~18) do quick 30–60 minute whole-house cleans. The boys "are clueless on how to help", so every chore carries a short step-by-step how-to. Success: Brandon says "give me half an hour", taps Start, and everyone knows exactly what to do.

## Goals
- Chore library: name, room, rough minutes, steps. ~20 seeded chores. Kira can add/edit/delete easily ("+ New chore" prominent), including a one-off chore while starting a blitz.
- Blitz: Brandon or Kira picks chores + 30/45/60 min timer. Everyone claims open chores on their phone, reads steps, taps Done.
- Apple TV board: big countdown, Open / In progress (who) / Done columns, finish screen with who did what.
- Each person picks their name once per phone. Only Brandon and Kira (parents) can create/edit chores or start/end a blitz.

## Non-goals / anti-goals
- No points, rewards, streaks. No server. No recurring weekly chores (maybe later).
- Failure even if it works: boys still don't know what to do (steps missing/vague), or the TV lags so claims collide.

## Approaches
1. **Native SwiftUI iOS + tvOS app, CloudKit public database (chosen).** No server, no invites, near-live updates.
2. Web app — needs an always-on host; Brandon prefers not to keep the PC on.
3. Firebase — extra account and outside dependency for no gain.

## Decided
- Single Xcode project, two targets (iOS 17+, tvOS 17+), shared model code, one CloudKit container `iCloud.<bundle prefix>.ChoreBlitz`, public database.
- Record types: Chore (name, room, minutes, steps, archived), Blitz (startedAt, endsAt, endedAt, startedBy), BlitzTask (blitz ref, choreName, room, steps, claimedBy, status, doneAt). Tasks snapshot the chore so edits don't change a running blitz.
- Sync: polling every 3 s on TV and every 5 s on phone while open (public DB does not support CKQuerySubscription push to tvOS reliably without notification setup; polling is simple and fast enough for 4 users). Claim uses record change tag so two people can't grab the same chore.
- Distribution: Kira via TestFlight "Family", boys Ad Hoc, Brandon's phone + "Bedroom" Apple TV direct install from the Mac. Paid team.

## Left to the builder
Visual styling, seed chore wording, exact layout of the TV columns.
