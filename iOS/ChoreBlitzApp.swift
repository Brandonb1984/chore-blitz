import ChoreKit
import SwiftUI

@main
struct ChoreBlitzApp: App {
    @StateObject private var store = HouseholdStore(pollSeconds: 4)
    @AppStorage("me") private var meRaw = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let me = Person(rawValue: meRaw) {
                    RootView(me: me)
                } else {
                    WhoAreYouView { meRaw = $0.rawValue }
                }
            }
            .environmentObject(store)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { store.startPolling() } else { store.stopPolling() }
            }
        }
    }
}

struct WhoAreYouView: View {
    let pick: (Person) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Chore Blitz").font(.largeTitle.bold())
            Text("Who's using this phone?").font(.title3).foregroundStyle(.secondary)
            ForEach(Person.allCases) { p in
                Button { pick(p) } label: {
                    HStack(spacing: 16) {
                        PersonBadge(person: p, size: 44)
                        Text(p.name).font(.title2.weight(.semibold))
                        Spacer()
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(p.color.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
    }
}

struct RootView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore

    var body: some View {
        Group {
            if store.state != nil {
                TabView {
                    BlitzTab(me: me)
                        .tabItem { Label("Blitz", systemImage: "sparkles") }
                    ChoreLibraryView(me: me)
                        .tabItem { Label("Chores", systemImage: "list.bullet.rectangle") }
                }
            } else if store.isLoading {
                ProgressView("Loading…")
            } else {
                NotSetUpView(me: me)
            }
        }
        .safeAreaInset(edge: .top) {
            if let problem = store.problem {
                Text(problem)
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.yellow.opacity(0.3))
                    .onTapGesture { store.problem = nil }
            }
        }
    }
}

struct NotSetUpView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @State private var working = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 56))
            Text("Chore Blitz isn't set up yet").font(.title2.bold())
            if me.isParent {
                Text("This creates your family's chore list with 20 starter chores you can edit.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button {
                    working = true
                    Task { await store.setUp(by: me); working = false }
                } label: {
                    Text(working ? "Setting up…" : "Set up Chore Blitz").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(working)
            } else {
                Text("Ask Brandon or Kira to open the app first.").foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }
}

/// Small helper so views can run a rule and get the error shown for free.
extension HouseholdStore {
    func run(_ change: @escaping (inout HouseholdState) throws -> Void) {
        Task { await apply(change) }
    }
}
