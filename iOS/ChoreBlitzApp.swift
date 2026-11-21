import ChoreKit
import SwiftUI

@main
struct ChoreBlitzApp: App {
    @StateObject private var store = HouseholdStore(pollSeconds: 4)
    @AppStorage("me") private var meRaw = ""
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Navigation titles in the same rounded heavy type as the rest of the app.
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: rounded(34, .heavy)]
        UINavigationBar.appearance().titleTextAttributes = [.font: rounded(17, .bold)]
    }

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
            #if targetEnvironment(macCatalyst)
            .onAppear {
                // Mac window: keep it from being squeezed narrower than a phone screen.
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.sizeRestrictions?.minimumSize = CGSize(width: 480, height: 600)
                }
            }
            #endif
        }
    }
}

struct WhoAreYouView: View {
    let pick: (Person) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(Palette.accent)
            Text("Chore Blitz")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.text)
            Text(deviceQuestion)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text2)
                .padding(.bottom, 10)
            ForEach(Person.allCases) { p in
                Button { pick(p) } label: {
                    HStack(spacing: 16) {
                        PersonBadge(person: p, size: 46)
                        Text(p.name)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Palette.text2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}

/// Debug builds: launch with `-screen chores|settings|start|edit|detail|spin` to open
/// that screen directly (simulator screenshots can't tap). Always nil in Release.
var debugScreen: String? {
    #if DEBUG
    return UserDefaults.standard.string(forKey: "screen")
    #else
    return nil
    #endif
}

/// Whether this phone wears the arcade look while Game mode is on. Each
/// phone chooses for itself; until someone chooses, it's on for Reagen only.
enum ArcadeLook {
    static let key = "arcadeLook"

    static func isOn(choice: String, me: Person) -> Bool {
        if choice == "on" { return true }
        if choice == "off" { return false }
        return HouseholdState.spinners.contains(me)
    }
}

struct RootView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @AppStorage(ArcadeLook.key) private var arcadeChoice = ""
    @State private var tab = debugScreen == "chores" ? 1 : ((debugScreen == "settings" || debugScreen == "prizes") ? 2 : 0)

    var skin: Skin {
        let arcade = (store.state?.isGameMode ?? false) && ArcadeLook.isOn(choice: arcadeChoice, me: me)
        return arcade ? .arcadeSkin : .standard
    }

    var body: some View {
        Group {
            if store.state != nil {
                TabView(selection: $tab) {
                    BlitzTab(me: me)
                        .tabItem { Label("Today", systemImage: "bolt.fill") }
                        .tag(0)
                    ChoreLibraryView(me: me)
                        .tabItem { Label("Chores", systemImage: "list.bullet") }
                        .tag(1)
                    SettingsView(me: me)
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(2)
                }
            } else if store.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.bg.ignoresSafeArea())
            } else {
                NotSetUpView(me: me)
            }
        }
        .environment(\.skin, skin)
        .tint(skin.accentText)
        .preferredColorScheme(skin.arcade ? .dark : nil)
        .safeAreaInset(edge: .top) {
            if let problem = store.problem {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(problem).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "xmark").font(.footnote.weight(.bold))
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.onAccent)
                .padding(12)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
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
            Image(systemName: "bolt.fill")
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(Palette.accent)
            Text("Chore Blitz isn't set up yet")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            if me.isParent {
                Text("This creates your family's chore list with 20 starter chores you can edit.")
                    .multilineTextAlignment(.center).foregroundStyle(Palette.text2)
                Button {
                    working = true
                    Task { await store.setUp(by: me); working = false }
                } label: {
                    Text(working ? "Setting up…" : "Set up Chore Blitz")
                }
                .buttonStyle(BlitzButtonStyle(kind: .accent, height: 56))
                .disabled(working)
            } else {
                Text("Ask Brandon or Kira to open the app first.").foregroundStyle(Palette.text2)
            }
        }
        .foregroundStyle(Palette.text)
        .padding(32)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}

/// Small helper so views can run a rule and get the error shown for free.
extension HouseholdStore {
    func run(_ change: @escaping (inout HouseholdState) throws -> Void) {
        Task { await apply(change) }
    }
}

#if targetEnvironment(macCatalyst)
private let deviceQuestion = "Who's using this Mac?"
#else
private let deviceQuestion = "Who's using this phone?"
#endif
