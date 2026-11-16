import ChoreKit
import PhotosUI
import SwiftUI
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// "Scan a room": take a photo, the phone's own Apple Intelligence suggests
// chores with steps, a parent picks which to add. Nothing leaves the phone.
//
// How it sees the photo: Vision labels what's in it (kitchen, dishes,
// laundry, ...), then the on-device language model turns those labels plus
// the room name into chore suggestions.

struct ChoreIdea: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var minutes: Int
    var steps: [String]
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedChore {
    @Guide(description: "Short chore name starting with a verb, like 'Clear the counter'")
    var name: String
    @Guide(description: "About how many minutes it takes one person", .range(2...45))
    var minutes: Int
    @Guide(description: "Short, concrete steps written for someone who has never done this chore", .count(2...5))
    var steps: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedChoreList {
    @Guide(description: "The most useful cleaning chores for this area, most important first", .count(1...6))
    var chores: [GeneratedChore]
}
#endif

enum RoomScanner {
    /// nil when Apple Intelligence is ready; otherwise a plain-English reason.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to use Scan a room."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading. Try again in a bit."
            case .unavailable(.deviceNotEligible):
                return "This iPhone doesn't support Apple Intelligence."
            case .unavailable:
                return "Apple Intelligence isn't available right now."
            }
        }
        #endif
        return "Scan a room needs iOS 26 or later with Apple Intelligence."
    }

    /// What Vision sees in the photo, most confident first.
    static func labels(for image: UIImage) async throws -> [String] {
        guard #available(iOS 18.0, *), let cg = image.cgImage else { return [] }
        let request = ClassifyImageRequest()
        let results = try await request.perform(on: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
        return results
            .filter { $0.confidence > 0.15 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(20)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    static func suggest(room: String, labels: [String], existing: [String]) async throws -> [ChoreIdea] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You help a family of four adults clean their house quickly. \
                Two of them are young men who don't know how to clean, so steps must be specific and practical. \
                Suggest only chores that make sense for the room and the things seen in the photo. \
                Don't suggest chores that are already on their list.
                """)
            let prompt = """
                Room: \(room)
                Things seen in the photo: \(labels.isEmpty ? "nothing clear" : labels.joined(separator: ", "))
                Chores already on our list: \(existing.joined(separator: "; "))
                Suggest cleaning chores for this area.
                """
            let response = try await session.respond(to: prompt, generating: GeneratedChoreList.self)
            return response.content.chores.map {
                ChoreIdea(name: $0.name, minutes: $0.minutes, steps: $0.steps)
            }
        }
        #endif
        throw ScanError.unavailable
    }

    enum ScanError: LocalizedError {
        case unavailable
        var errorDescription: String? { RoomScanner.unavailableReason ?? "Apple Intelligence isn't available." }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

struct RoomScanView: View {
    let me: Person
    @EnvironmentObject var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss

    @State private var room = ""
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var working = false
    @State private var seen: [String] = []
    @State private var ideas: [ChoreIdea] = []
    @State private var chosen: Set<UUID> = []
    @State private var editing: ChoreIdea?
    @State private var problem: String?

    var rooms: [String] { store.state?.rooms ?? [] }

    var body: some View {
        NavigationStack {
            List {
                if let reason = RoomScanner.unavailableReason {
                    Section { Label(reason, systemImage: "exclamationmark.triangle") }
                }
                Section("Which room?") {
                    Picker("Room", selection: $room) {
                        ForEach(rooms, id: \.self) { Text($0) }
                    }
                }
                Section {
                    if let image {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showingCamera = true } label: { Label("Take photo", systemImage: "camera.fill") }
                                .buttonStyle(.borderedProminent)
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                    }
                    if image != nil {
                        Button {
                            Task { await analyze() }
                        } label: {
                            HStack {
                                if working { ProgressView() }
                                Text(working ? "Looking…" : (ideas.isEmpty ? "Suggest chores" : "Try again"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(working || RoomScanner.unavailableReason != nil)
                    }
                } footer: {
                    Text("Runs on this iPhone with Apple Intelligence. The photo isn't saved or sent anywhere.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(.red) }
                }
                if !seen.isEmpty {
                    Section("What it noticed") {
                        Text(seen.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !ideas.isEmpty {
                    Section {
                        ForEach(ideas) { idea in
                            HStack(alignment: .top) {
                                Button { toggle(idea.id) } label: {
                                    Image(systemName: chosen.contains(idea.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(chosen.contains(idea.id) ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.borderless)
                                Button { editing = idea } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(idea.name).font(.headline).foregroundStyle(.primary)
                                        ForEach(Array(idea.steps.enumerated()), id: \.offset) { i, step in
                                            Text("\(i + 1). \(step)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        Text("Suggestions")
                    } footer: {
                        Text("Tap a suggestion to edit it before adding.")
                    }
                }
            }
            .navigationTitle("Scan a room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(chosen.count)") { addChosen() }
                        .disabled(chosen.isEmpty)
                }
            }
            .onAppear { if room.isEmpty { room = rooms.first ?? "Kitchen" } }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        setImage(img)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { setImage($0) }.ignoresSafeArea()
            }
            .sheet(item: $editing) { idea in
                ChoreEditorView(title: "Edit suggestion",
                                chore: Chore(name: idea.name, room: room, minutes: idea.minutes, steps: idea.steps),
                                rooms: rooms, saveLabel: "Done") { edited in
                    if let i = ideas.firstIndex(where: { $0.id == idea.id }) {
                        ideas[i].name = edited.name
                        ideas[i].minutes = edited.minutes
                        ideas[i].steps = edited.steps
                        chosen.insert(idea.id)
                    }
                }
            }
        }
    }

    func setImage(_ img: UIImage) {
        image = img
        ideas = []
        seen = []
        chosen = []
        problem = nil
        Task { await analyze() }
    }

    func toggle(_ id: UUID) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }

    func analyze() async {
        guard let image, RoomScanner.unavailableReason == nil else { return }
        working = true
        problem = nil
        defer { working = false }
        do {
            seen = try await RoomScanner.labels(for: image)
            let existing = (store.state?.chores ?? []).filter { $0.room == room }.map(\.name)
            ideas = try await RoomScanner.suggest(room: room, labels: seen, existing: existing)
            chosen = Set(ideas.map(\.id))
            if ideas.isEmpty { problem = "No suggestions this time. Try another angle." }
        } catch {
            problem = "Couldn't get suggestions: \(error.localizedDescription)"
        }
    }

    func addChosen() {
        let new = ideas.filter { chosen.contains($0.id) }.map {
            Chore(name: $0.name, room: room, minutes: $0.minutes, steps: $0.steps)
        }
        store.run { state in
            for chore in new { try state.addChore(chore, by: me) }
        }
        dismiss()
    }
}

/// Minimal camera wrapper.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
