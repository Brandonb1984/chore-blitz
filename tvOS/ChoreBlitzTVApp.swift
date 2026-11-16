import ChoreKit
import SwiftUI

@main
struct ChoreBlitzTVApp: App {
    @StateObject private var store = HouseholdStore(pollSeconds: 3)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BoardView()
                .environmentObject(store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { store.startPolling() } else { store.stopPolling() }
                }
        }
    }
}
