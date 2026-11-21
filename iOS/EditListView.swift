import ChoreKit
import SwiftUI

/// Parents add or remove chores while a list is going. Changes save right away.
struct EditListView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.skin) private var skin
    @State private var newName = ""
    @State private var newRoom = ""
    @State private var showSaved = false
    @FocusState private var typing: Bool

    var tasks: [BlitzTask] { store.state?.runningBlitz?.tasks ?? [] }
    var saved: [Chore] { store.state?.chores ?? [] }
    var rooms: [String] { store.state?.rooms ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tasks) { task in
                        HStack {
                            Text(task.name)
                            Spacer()
                            if let who = task.claimedBy { PersonBadge(person: who, size: 22) }
                            if task.doneAt != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.done) }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { tasks[$0].id }
                        store.run { state in for id in ids { try state.removeTask(taskID: id, by: me) } }
                    }
                    HStack {
                        TextField("Add a chore…", text: $newName)
                            .focused($typing)
                            .submitLabel(.done)
                            .onSubmit(addTyped)
                        RoomChip(rooms: rooms, room: $newRoom)
                        Button(action: addTyped) { Image(systemName: "plus.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Today's list")
                } footer: {
                    Text("Swipe left on a chore to take it off.")
                }
                .listRowBackground(skin.card)
                Section {
                    DisclosureGroup("Add from saved chores", isExpanded: $showSaved) {
                        ForEach(saved.filter { c in !tasks.contains { $0.choreID == c.id } }) { chore in
                            Button {
                                store.run { try $0.addTasks([chore], by: me) }
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                                    Text(chore.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text(chore.room).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(skin.card)
            }
            .skinnedList()
            .navigationTitle("Edit list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { if newRoom.isEmpty { newRoom = rooms.first ?? "Kitchen" } }
        }
    }

    /// A typed name that matches a saved chore reuses it; otherwise it's a new
    /// chore, saved for next time too.
    func addTyped() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let existing = saved.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let chore = existing ?? Chore(name: name, room: newRoom.isEmpty ? "Around the house" : newRoom, minutes: 10, steps: [])
        store.run { state in
            if existing == nil { try state.addChore(chore, by: me) }
            try state.addTasks([chore], by: me)
        }
        newName = ""
        typing = true
    }
}
