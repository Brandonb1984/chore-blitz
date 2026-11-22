import SwiftUI
import Network
import Security

@main
struct DuoRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Saved Macs

struct SavedMac: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var address: String       // hostname, IP, Tailscale name, or "" when found with Bonjour
    var bonjourName: String?  // Bonjour service name when found on the network
    var username: String
}

enum Store {
    private static let key = "savedMacs"

    static func load() -> [SavedMac] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SavedMac].self, from: d) else { return [] }
        return list
    }

    static func save(_ list: [SavedMac]) {
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key) }
    }
}

enum Keychain {
    private static let service = "com.brandonbourne.DuoRemote"

    static func password(for id: UUID) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: id.uuidString,
                                kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func setPassword(_ pw: String, for id: UUID) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: id.uuidString]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(pw.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(for id: UUID) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: id.uuidString]
        SecItemDelete(base as CFDictionary)
    }
}

// MARK: - Bonjour

/// Finds Macs with Screen Sharing turned on (they advertise _rfb._tcp).
final class MacBrowser: ObservableObject {
    @Published var found: [String] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { r -> String? in
                if case let .service(name, _, _, _) = r.endpoint { return name }
                return nil
            }
            DispatchQueue.main.async { self?.found = Array(Set(names)).sorted() }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

// MARK: - Remote screen bridge

struct RemoteScreen: UIViewControllerRepresentable {
    let mac: SavedMac
    let password: String
    let onClose: (String?) -> Void

    func makeUIViewController(context: Context) -> RemoteViewController {
        let endpoint: NWEndpoint
        if let bonjour = mac.bonjourName, mac.address.isEmpty {
            endpoint = .service(name: bonjour, type: "_rfb._tcp", domain: "local.", interface: nil)
        } else {
            var host = mac.address.trimmingCharacters(in: .whitespaces)
            var port: UInt16 = 5900
            if let colon = host.lastIndex(of: ":"), !host.contains("::"), let p = UInt16(host[host.index(after: colon)...]) {
                port = p
                host = String(host[..<colon])
            }
            endpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        }
        let vc = RemoteViewController(endpoint: endpoint,
                                      credentials: .init(username: mac.username, password: password),
                                      title: mac.name)
        vc.onClose = onClose
        return vc
    }

    func updateUIViewController(_ vc: RemoteViewController, context: Context) {}
}
