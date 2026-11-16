import ChoreKit
import SwiftUI

/// Parents pick chores and a time, then start. One-off chores can be
/// added here without saving them to the library.
struct StartBlitzView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30
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
                    Picker("How long", selection: $minutes) {
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.segmented)
                    Text("\(picked.count + oneOffs.count) chores picked · about \(totalMinutes) min of work")
                        .font(.footnote).foregroundStyle(.secondary)
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
                            Text("just this time").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { oneOffs.remove(atOffsets: $0) }
                }
                ForEach(rooms, id: \.self) { room in
                    Section(room) {
                        ForEach(chores.filter { $0.room == room }) { chore in
                            Button { toggle(chore.id) } label: {
                                HStack {
                                    Image(systemName: picked.contains(chore.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(chore.id) ? Color.accentColor : Color.secondary)
                                    Text(chore.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(chore.minutes) min").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Start a blitz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        starting = true
                        let ids = picked, extras = oneOffs, saved = savedOneOffs, mins = minutes
                        Task {
                            let ok = await store.apply { state in
                                let notYetSaved = saved.filter { c in !state.chores.contains { $0.id == c.id } }
                                try state.startBlitz(by: me, choreIDs: ids, oneOffs: extras + notYetSaved,
                                                     minutes: mins, now: .now)
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
        if let i = picked.firstIndex(of: id) { picked.remove(at: i) } else { picked.append(id) }
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
