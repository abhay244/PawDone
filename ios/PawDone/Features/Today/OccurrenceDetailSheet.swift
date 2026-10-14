import SwiftUI

/// A finished (or missed) task: who did it, when, the photo and the note.
struct OccurrenceDetailSheet: View {
    @Environment(PetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let occurrence: Occurrence

    @State private var confirmingUndo = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let photo = store.photos.image(for: occurrence.id) {
                    Section {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                }

                Section {
                    LabeledContent("Due", value: store.time(occurrence.scheduledAt))
                    if occurrence.status == .done {
                        LabeledContent("Done by", value: store.name(for: occurrence.completedBy))
                        if let completedAt = occurrence.completedAt {
                            LabeledContent("Done at", value: store.time(completedAt))
                        }
                    } else {
                        LabeledContent(
                            "Status",
                            value: occurrence.effectiveStatus(today: store.todayString) == .missed ? "Missed" : "Not done yet"
                        )
                    }
                }

                if let note = occurrence.note {
                    Section("Note") {
                        Text(note)
                    }
                }

                if canUndo {
                    Section {
                        Button("Undo check-off", role: .destructive) { confirmingUndo = true }
                            .disabled(isWorking)
                    } footer: {
                        Text("You can undo your own check-offs until the end of the day.")
                    }
                }
            }
            .navigationTitle(occurrence.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog("Undo this check-off?", isPresented: $confirmingUndo, titleVisibility: .visible) {
                Button("Undo", role: .destructive, action: undo)
            } message: {
                Text("The task will show as not done, and its photo will be deleted.")
            }
            .alert("Couldn't undo", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var canUndo: Bool {
        occurrence.status == .done
            && occurrence.completedBy == store.myUserID
            && occurrence.date == store.todayString
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func undo() {
        isWorking = true
        Task {
            do {
                try await store.undo(occurrence)
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isWorking = false
            }
        }
    }
}
