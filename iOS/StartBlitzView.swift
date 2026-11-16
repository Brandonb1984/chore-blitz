import ChoreKit
import SwiftUI

/// Parents pick chores, optionally assign some to a person with a reward,
/// optionally turn on Blitz mode (a timer), then start. One-off chores can
/// be added here without saving them to the library.
struct StartBlitzView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    var showTimes: Bool { store.showTimes }
    @Environment(\.dismiss) private var dismiss
    @State private var blitzMode = false
    @State private var minutes = 30
    @State private var assignments: [UUID: Person] = [:]
    @State private var prizes: [Person: String] = [:]
    @State private var picked: [UUID] = []
    @State private var oneOffs: [Chore] = []
    /// One-offs also being saved to the library; used as a fallback if that save hasn't landed yet.
    @State private var savedOneOffs: [Chore] = []
    @State private var addingOneOff = false
    @State private var starting = false

    var chores: [Chore] { store.state?.chores ?? [] }
    var rooms: [String] { store.state?.rooms ?? [] }
    var totalMinutes: Int {
        chores.filter { picked.contains($0.id) }.map(\.minutes).reduce(0, +) + oneOffs.map(\.minutes).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $blitzMode.animation()) {
                        VStack(alignment: .leading) {
                            Text("Blitz mode").font(.headline)
                            Text("Race the clock with a countdown on the TV").font(.caption).foregroundStyle(.secondary)
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
                    Text(showTimes ? "\(picked.count + oneOffs.count) chores picked · about \(totalMinutes) min of work"
                                   : "\(picked.count + oneOffs.count) chores picked")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !assignedPeople.isEmpty {
                    Section {
                        ForEach(assignedPeople) { p in
                            HStack {
                                PersonBadge(person: p)
                                TextField("Reward for \(p.name), like $20", text: prizeBinding(p))
                            }
                        }
                    } header: {
                        Text("Rewards")
                    } footer: {
                        Text("Earned when all of their assigned chores are done. Leave blank for no reward.")
                    }
                }
                Section {
                    Button { addingOneOff = true } label: {
                        Label("Add a one-off chore", systemImage: "plus.circle.fill")
                    }
                    ForEach(oneOffs) { c in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            Text(c.name)
                            Spacer()
                            assignMenu(c.id)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { assignments[oneOffs[i].id] = nil }
                        oneOffs.remove(atOffsets: offsets)
                    }
                }
                ForEach(rooms, id: \.self) { room in
                    Section(room) {
                        ForEach(chores.filter { $0.room == room }) { chore in
                            HStack {
                                Button { toggle(chore.id) } label: {
                                    HStack {
                                        Image(systemName: picked.contains(chore.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(picked.contains(chore.id) ? Color.accentColor : Color.secondary)
                                        Text(chore.name).foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                if picked.contains(chore.id) {
                                    assignMenu(chore.id)
                                } else if showTimes {
                                    Text("\(chore.minutes) min").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Start chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        starting = true
                        let ids = picked, extras = oneOffs, saved = savedOneOffs
                        let mins: Int? = blitzMode ? minutes : nil
                        let assigned = assignments, rewards = prizes
                        Task {
                            let ok = await store.apply { state in
                                let notYetSaved = saved.filter { c in !state.chores.contains { $0.id == c.id } }
                                try state.startBlitz(by: me, choreIDs: ids, oneOffs: extras + notYetSaved,
                                                     minutes: mins, now: .now,
                                                     assignments: assigned, prizes: rewards)
                            }
                            starting = false
                            if ok { dismiss() }
                        }
                    }
                    .bold()
                    .disabled(starting || (picked.isEmpty && oneOffs.isEmpty))
                }
            }
            .sheet(isPresented: $addingOneOff) {
                OneOffEditor(me: me, rooms: rooms) { chore, saveToLibrary in
                    if saveToLibrary {
                        store.run { try $0.addChore(chore, by: me) }
                        savedOneOffs.append(chore)
                        picked.append(chore.id)
                    } else {
                        oneOffs.append(chore)
                    }
                }
            }
        }
    }

    func toggle(_ id: UUID) {
        if let i = picked.firstIndex(of: id) {
            picked.remove(at: i)
            assignments[id] = nil
        } else {
            picked.append(id)
        }
    }

    /// People with at least one assigned chore, in family order.
    var assignedPeople: [Person] {
        Person.allCases.filter { p in assignments.values.contains(p) }
    }

    func prizeBinding(_ p: Person) -> Binding<String> {
        Binding(get: { prizes[p] ?? "" }, set: { prizes[p] = $0 })
    }

    /// "Anyone" or a specific person for a picked chore.
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

/// The chore editor plus a "save to the chore list too" switch.
struct OneOffEditor: View {
    let me: Person
    let rooms: [String]
    let done: (Chore, Bool) -> Void
    @State private var saveToLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            ChoreEditorView(title: "One-off chore",
                            chore: Chore(name: "", room: rooms.first ?? "Kitchen", minutes: 10, steps: [""]),
                            rooms: rooms, saveLabel: "Add") { chore in
                done(chore, saveToLibrary)
            }
            Toggle("Also save it to the chore list", isOn: $saveToLibrary)
                .padding()
                .background(.bar)
        }
    }
}
