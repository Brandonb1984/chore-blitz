import SwiftUI

struct ConnectView: View {
    @StateObject private var browser = MacBrowser()
    @State private var saved: [SavedMac] = Store.load()
    @State private var editing: SavedMac?
    @State private var active: SavedMac?
    @State private var activePassword = ""
    @State private var lastError: String?

    var body: some View {
        NavigationStack {
            List {
                if let lastError {
                    Section {
                        Label(lastError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Your Macs") {
                    if saved.isEmpty {
                        Text("Add your Mac below, or pick one found on your Wi‑Fi.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(saved) { mac in
                        Button {
                            connect(mac)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "laptopcomputer")
                                    .font(.title2)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mac.name).font(.headline)
                                    Text(mac.address.isEmpty ? "On this Wi‑Fi" : mac.address)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { delete(mac) }
                            Button("Edit") { editing = mac }.tint(.blue)
                        }
                    }
                }
                let unsaved = browser.found.filter { name in !saved.contains { $0.bonjourName == name } }
                if !unsaved.isEmpty {
                    Section("Found on this Wi‑Fi") {
                        ForEach(unsaved, id: \.self) { name in
                            Button {
                                editing = SavedMac(name: name, address: "", bonjourName: name, username: "")
                            } label: {
                                Label(name, systemImage: "wifi")
                            }
                        }
                    }
                }
                Section {
                    Button {
                        editing = SavedMac(name: "", address: "", username: "")
                    } label: {
                        Label("Add a Mac by address", systemImage: "plus")
                    }
                } footer: {
                    Text("Turn on Screen Sharing on the Mac (System Settings › General › Sharing). Away from home, use the Mac's Tailscale name as the address.")
                }
            }
            .navigationTitle("Mac Remote")
            .sheet(item: $editing) { mac in
                EditMacView(mac: mac) { updated, password in
                    if let i = saved.firstIndex(where: { $0.id == updated.id }) { saved[i] = updated }
                    else { saved.append(updated) }
                    Store.save(saved)
                    if !password.isEmpty { Keychain.setPassword(password, for: updated.id) }
                    editing = nil
                }
            }
            .fullScreenCover(item: $active) { mac in
                RemoteScreen(mac: mac, password: activePassword) { error in
                    lastError = error
                    active = nil
                }
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
            }
            .onAppear { browser.start() }
        }
    }

    private func connect(_ mac: SavedMac) {
        guard let pw = Keychain.password(for: mac.id) else { editing = mac; return }
        lastError = nil
        activePassword = pw
        active = mac
    }

    private func delete(_ mac: SavedMac) {
        saved.removeAll { $0.id == mac.id }
        Keychain.delete(for: mac.id)
        Store.save(saved)
    }
}

struct EditMacView: View {
    @State var mac: SavedMac
    @State private var password = ""
    let onSave: (SavedMac, String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(mac: SavedMac, onSave: @escaping (SavedMac, String) -> Void) {
        _mac = State(initialValue: mac)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $mac.name)
                    if mac.bonjourName == nil || !mac.address.isEmpty {
                        TextField("Address (e.g. brandons-macbook-pro or 100.x.x.x)", text: $mac.address)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }
                Section {
                    TextField("Mac username", text: $mac.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(Keychain.password(for: mac.id) == nil ? "Mac password" : "Password (saved)", text: $password)
                } footer: {
                    Text("The account you sign in to the Mac with. The password is kept in this phone's Keychain.")
                }
            }
            .navigationTitle(mac.name.isEmpty ? "Add Mac" : mac.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if mac.name.isEmpty { mac.name = mac.bonjourName ?? mac.address }
                        onSave(mac, password)
                    }
                    .disabled(mac.address.isEmpty && mac.bonjourName == nil)
                }
            }
        }
    }
}
