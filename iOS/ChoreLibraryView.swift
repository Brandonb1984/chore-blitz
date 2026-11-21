import ChoreKit
import SwiftUI

struct ChoreLibraryView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.skin) private var skin
    var showTimes: Bool { store.showTimes }
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
                            Label("New chore", systemImage: "plus")
                        }
                        .buttonStyle(BlitzButtonStyle(kind: .accent, height: 52))
                        if RoomScanner.canSeePhotos {
                            Button { scanning = true } label: {
                                Label("Scan a room for ideas", systemImage: "camera.viewfinder")
                            }
                            .buttonStyle(BlitzButtonStyle(kind: .quiet, height: 46))
                        }
                    } footer: {
                        if !RoomScanner.canSeePhotos {
                            Text("Scan a room needs iOS 27 on this phone.")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if chores.isEmpty {
                    Section {
                        Text(me.isParent ? "No saved chores yet. Add one above, or type chores straight into today's list."
                                         : "No saved chores yet.")
                            .font(skin.body(15))
                            .foregroundStyle(skin.text2)
                    }
                    .listRowBackground(skin.card)
                }
                ForEach(rooms, id: \.self) { room in
                    Section {
                        ForEach(chores.filter { $0.room == room }) { chore in
                            NavigationLink {
                                ChoreDetailView(me: me, chore: chore)
                            } label: {
                                HStack {
                                    Text(chore.name).font(skin.body(17, .bold)).foregroundStyle(skin.text)
                                    Spacer()
                                    if showTimes {
                                        Text("\(chore.minutes) min").font(skin.body(14)).foregroundStyle(skin.text2)
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
                    } header: {
                        Text(room)
                    }
                    .listRowBackground(skin.card)
                }
            }
            .skinnedList()
            .navigationTitle("Chores")
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
    @Environment(\.skin) private var skin
    var showTimes: Bool { store.showTimes }
    @State private var editing = false

    var current: Chore { store.state?.chores.first { $0.id == chore.id } ?? chore }

    var body: some View {
        List {
            Section {
                Text(showTimes ? "\(current.room) · about \(current.minutes) min" : current.room)
                    .font(skin.body(15))
                    .foregroundStyle(skin.text2)
            }
            .listRowBackground(skin.card)
            Section {
                if current.steps.isEmpty {
                    Text(me.isParent ? "No steps yet. Tap Edit to add them." : "No steps written for this one yet.")
                        .font(skin.body(15))
                        .foregroundStyle(skin.text2)
                }
                ForEach(Array(current.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(skin.accentText)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(skin.accentText, lineWidth: 2))
                        Text(step).font(skin.body(17)).foregroundStyle(skin.text)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("How to do it")
            }
            .listRowBackground(skin.card)
        }
        .skinnedList()
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
            .skinnedList()
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
