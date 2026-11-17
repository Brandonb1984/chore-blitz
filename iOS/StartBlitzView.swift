import ChoreKit
import SwiftUI

/// "Make today's list": starts empty. Type a chore and tap +, or pick from
/// saved chores. Assign to someone, set Reagen's reward, optionally turn on
/// Blitz mode, then Start. New chores are saved for next time automatically.
struct StartBlitzView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }
    @Environment(\.dismiss) private var dismiss

    @State private var items: [Chore] = []
    @State private var newName = ""
    @State private var newRoom = ""
    @State private var editing: Chore?
    @State private var showSaved = false
    @State private var blitzMode = false
    @State private var minutes = 30
    @State private var assignments: [UUID: Person] = [:]
    @State private var prizes: [Person: String] = [:]
    @State private var starting = false
    @FocusState private var typing: Bool

    var saved: [Chore] { store.state?.chores ?? [] }
    var rooms: [String] {
        var r = store.state?.rooms ?? []
        for c in items where !r.contains(c.room) { r.append(c.room) }
        return r.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty {
                        Text("Type the chores you want done today, or pick from your saved chores below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        HStack {
                            Button { editing = item } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).foregroundStyle(.primary)
                                    Text(item.steps.isEmpty ? "\(item.room) · tap to add steps" : item.room)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            assignMenu(item.id)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { assignments[items[i].id] = nil }
                        items.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("Add a chore…", text: $newName)
                            .focused($typing)
                            .submitLabel(.done)
                            .onSubmit(addTyped)
                        Menu {
                            ForEach(rooms, id: \.self) { r in Button(r) { newRoom = r } }
                        } label: {
                            Text(newRoom).font(.subheadline)
                        }
                        Button(action: addTyped) {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Today's list")
                }

                if rewardPeople.count > 0 {
                    Section {
                        ForEach(rewardPeople) { p in
                            HStack {
                                PersonBadge(person: p)
                                TextField("Reward for \(p.name), like $20", text: prizeBinding(p))
                            }
                        }
                    } header: {
                        Text("Reward")
                    } footer: {
                        Text("Earned when all of his assigned chores are done.")
                    }
                }

                Section {
                    Toggle(isOn: $blitzMode.animation()) {
                        VStack(alignment: .leading) {
                            Text("Blitz mode")
                            Text("Adds a countdown on the TV").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if blitzMode {
                        Picker("How long", selection: $minutes) {
                            Text("30 min").tag(30)
                            Text("45 min").tag(45)
                            Text("60 min").tag(60)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    DisclosureGroup("Pick from saved chores (\(saved.count))", isExpanded: $showSaved) {
                        ForEach(saved) { chore in
                            Button { toggleSaved(chore) } label: {
                                HStack {
                                    Image(systemName: isPicked(chore) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isPicked(chore) ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading) {
                                        Text(chore.name).foregroundStyle(.primary)
                                        Text(chore.room).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if showTimes { Text("\(chore.minutes) min").foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today's list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Text(items.isEmpty ? "Add chores to start" : "Start \(items.count) chore\(items.count == 1 ? "" : "s")")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(items.isEmpty || starting)
                .padding()
                .background(.bar)
            }
            .onAppear { if newRoom.isEmpty { newRoom = rooms.first ?? "Kitchen" } }
            .sheet(item: $editing) { item in
                ChoreEditorView(title: "Edit chore", chore: item, rooms: rooms, saveLabel: "Done") { edited in
                    if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = edited }
                }
            }
        }
    }

    /// Typing a name that matches a saved chore uses the saved one (with its steps).
    func addTyped() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let existing = saved.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if !isPicked(existing) { items.append(existing) }
        } else {
            items.append(Chore(name: name, room: newRoom.isEmpty ? "Around the house" : newRoom, minutes: 10, steps: []))
        }
        newName = ""
        typing = true
    }

    func isPicked(_ c: Chore) -> Bool { items.contains { $0.id == c.id } }

    func toggleSaved(_ c: Chore) {
        if let i = items.firstIndex(where: { $0.id == c.id }) {
            assignments[c.id] = nil
            items.remove(at: i)
        } else {
            items.append(c)
        }
    }

    /// Only Reagen gets paid; Braden is an adult.
    var rewardPeople: [Person] {
        [Person.reagen].filter { p in assignments.values.contains(p) }
    }

    func prizeBinding(_ p: Person) -> Binding<String> {
        Binding(get: { prizes[p] ?? "" }, set: { prizes[p] = $0 })
    }

    func start() {
        starting = true
        let list = items, assigned = assignments, rewards = prizes
        let mins: Int? = blitzMode ? minutes : nil
        Task {
            let ok = await store.apply { state in
                // Save new or edited chores so they're there next time.
                for c in list {
                    if state.chores.contains(where: { $0.id == c.id }) {
                        try state.updateChore(c, by: me)
                    } else {
                        try state.addChore(c, by: me)
                    }
                }
                try state.startBlitz(by: me, choreIDs: list.map(\.id), minutes: mins, now: .now,
                                     assignments: assigned, prizes: rewards)
            }
            starting = false
            if ok { dismiss() }
        }
    }

    func assignMenu(_ id: UUID) -> some View {
        Menu {
            Button("Anyone") { assignments[id] = nil }
            ForEach(Person.allCases) { p in
                Button(p.name) { assignments[id] = p }
            }
        } label: {
            HStack(spacing: 6) {
                if let p = assignments[id] {
                    PersonBadge(person: p, size: 22)
                    Text(p.name)
                } else {
                    Text("Anyone")
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline)
        }
    }
}
