import SwiftUI

struct MarkDoneSheet: View {
    @Environment(PetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let occurrence: Occurrence

    @State private var photo: UIImage?
    @State private var note = ""
    @State private var showingCamera = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading) {
                            Text(occurrence.title)
                                .font(.headline)
                            Text("Due \(store.time(occurrence.scheduledAt))")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: occurrence.category.symbol)
                    }
                    if let instructions = occurrence.instructions, !instructions.isEmpty {
                        Text(instructions)
                    }
                }

                Section {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 12))
                        Button("Retake photo") { showingCamera = true }
                        Button("Remove photo", role: .destructive) { self.photo = nil }
                    } else if CameraPicker.isAvailable {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                    } else {
                        Label("This device doesn't have a camera", systemImage: "camera")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Photo proof")
                } footer: {
                    Text(store.hasPremium
                        ? "Optional. Everyone who looks after \(store.pet?.name ?? "your pet") can see it."
                        : "Optional. Photos are kept on this phone.")
                }

                Section("Note") {
                    TextField("Optional, e.g. ate half", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Mark as done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(isSaving)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $photo)
                    .ignoresSafeArea()
            }
            .alert("Couldn't mark this task", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await store.complete(occurrence, note: note, photo: photo)
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isSaving = false
            }
        }
    }
}
