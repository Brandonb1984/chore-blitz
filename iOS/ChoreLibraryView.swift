import ChoreKit
import SwiftUI

struct ChoreLibraryView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }
    @AppStorage("me") private var meRaw = ""
    @State private var editing: Chore?
    @State private var adding = false
    @State private var scanning = false

    var chores: [Chore] { store.state?.chores ?? [] }
    var rooms: [String] { store.state?.rooms ?? [] }

    var body: some View {
        NavigationStack {
            List {
                if me.isParent {
                    Section {
                        Button { adding = true } label: {
                            Label("New chore", systemImage: "plus.circle.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                        if RoomScanner.canSeePhotos {
                            Button { scanning = true } label: {
                                Label("Scan a room", systemImage: "camera.viewfinder")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Label("Update to iOS 27 to use Scan a room", systemImage: "camera.viewfinder")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(rooms, id: \.self) { room in
                    Section(room) {
                        ForEach(chores.filter { $0.room == room }) { chore in
                            NavigationLink {
                                ChoreDetailView(me: me, chore: chore)
                            } label: {
                                HStack {
                                    Text(chore.name)
                                    Spacer()
                                    if showTimes {
                                        Text("\(chore.minutes) min").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                if me.isParent {
                                    Button("Delete", role: .destructive) {
                                        store.run { try $0.deleteChore(id: chore.id, by: me) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chores")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Text("Using as \(me.name)")
                        if me.isParent {
                            Toggle("Show chore times", isOn: Binding(
                                get: { showTimes },
                                set: { v in store.run { try $0.setShowTimes(v, by: me) } }))
                        }
                        Button("Switch person") { meRaw = "" }
                    } label: { PersonBadge(person: me) }
                }
            }
            .sheet(isPresented: $scanning) { RoomScanView(me: me) }
            .sheet(isPresented: $adding) {
                ChoreEditorView(title: "New chore", chore: Chore(name: "", room: rooms.first ?? "Kitchen", minutes: 10, steps: [""]),
                                rooms: rooms) { new in
                    store.run { try $0.addChore(new, by: me) }
                }
            }
        }
    }
}

struct ChoreDetailView: View {
    let me: Person
    let chore: Chore
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }
    @State private var editing = false

    var current: Chore { store.state?.chores.first { $0.id == chore.id } ?? chore }

    var body: some View {
        List {
            Section {
                Text(showTimes ? "\(current.room) · about \(current.minutes) min" : current.room)
                    .foregroundStyle(.secondary)
            }
            Section("How to do it") {
                ForEach(Array(current.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "\(i + 1).circle").foregroundStyle(Color.accentColor)
                        Text(step)
                    }
                }
            }
        }
        .navigationTitle(current.name)
        .toolbar {
            if me.isParent {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            ChoreEditorView(title: "Edit chore", chore: current, rooms: store.state?.rooms ?? []) { updated in
                store.run { try $0.updateChore(updated, by: me) }
            }
        }
    }
}

/// Add or edit a chore: name, room, minutes, and the steps.
struct ChoreEditorView: View {
    let title: String
    @State var chore: Chore
    let rooms: [String]
    var saveLabel = "Save"
    let save: (Chore) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newRoom = ""
    @FocusState private var focusedStep: Int?

    init(title: String, chore: Chore, rooms: [String], saveLabel: String = "Save", save: @escaping (Chore) -> Void) {
        self.title = title
        _chore = State(initialValue: chore)
        self.rooms = rooms
        self.saveLabel = saveLabel
        self.save = save
    }

    var cleaned: Chore {
        var c = chore
        c.name = c.name.trimmingCharacters(in: .whitespaces)
        c.room = c.room.trimmingCharacters(in: .whitespaces)
        c.steps = c.steps.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return c
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Chore name, like \"Wipe the fridge\"", text: $chore.name)
                        .font(.title3)
                    Stepper("About \(chore.minutes) min", value: $chore.minutes, in: 1...120, step: chore.minutes < 10 ? 1 : 5)
                }
                Section("Room") {
                    Picker("Room", selection: $chore.room) {
                        ForEach(roomChoices, id: \.self) { Text($0) }
                    }
                    HStack {
                        TextField("Or add a new room", text: $newRoom)
                        Button("Add") {
                            let r = newRoom.trimmingCharacters(in: .whitespaces)
                            guard !r.isEmpty else { return }
                            chore.room = r
                            newRoom = ""
                        }
                    }
                }
                Section {
                    ForEach(chore.steps.indices, id: \.self) { i in
                        HStack(alignment: .top) {
                            Text("\(i + 1).").foregroundStyle(.secondary)
                            TextField("Step", text: stepBinding(i), axis: .vertical)
                                .focused($focusedStep, equals: i)
                        }
                    }
                    .onDelete { chore.steps.remove(atOffsets: $0) }
                    .onMove { chore.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        chore.steps.append("")
                        focusedStep = chore.steps.count - 1
                    } label: { Label("Add a step", systemImage: "plus") }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Write it like you're explaining it to someone who's never done it.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        save(cleaned)
                        dismiss()
                    }
                    .disabled(cleaned.name.isEmpty || cleaned.room.isEmpty)
                }
            }
        }
    }

    /// Index-safe binding so deleting a step can't crash the editor.
    func stepBinding(_ i: Int) -> Binding<String> {
        Binding(get: { i < chore.steps.count ? chore.steps[i] : "" },
                set: { if i < chore.steps.count { chore.steps[i] = $0 } })
    }

    var roomChoices: [String] {
        var all = rooms
        if !chore.room.isEmpty, !all.contains(chore.room) { all.append(chore.room) }
        return all.sorted()
    }
}
