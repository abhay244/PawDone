import SwiftUI

/// Enter an invite code, see whose household it is, then join.
struct JoinHouseholdView: View {
    @Environment(PetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var preview: InvitePreview?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .font(.title2.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) {
                            preview = nil
                            errorMessage = nil
                        }
                } footer: {
                    Text("Ask the pet's owner to send you an invite from PawDone. Codes work for 7 days.")
                }

                if let preview {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Join \(preview.ownerName)'s household?")
                                    .font(.headline)
                                Text(description(of: preview))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: preview.petSpecies?.symbol ?? "house.fill")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join a household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if preview == nil {
                        Button("Next", action: check)
                            .disabled(InviteCode.normalize(code).count != 8 || isWorking)
                    } else {
                        Button("Join", action: join)
                            .disabled(isWorking)
                    }
                }
            }
        }
    }

    private func description(of preview: InvitePreview) -> String {
        guard let petName = preview.petName else {
            return "They haven't added their pet yet."
        }
        return "You'll see \(petName)'s day and can mark tasks done. Only \(preview.ownerName) can change the schedule."
    }

    private func check() {
        isWorking = true
        Task {
            do {
                if let found = try await store.inviteDetails(code: code) {
                    preview = found
                } else {
                    errorMessage = "This code is invalid or has expired. Ask for a new one."
                }
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isWorking = false
        }
    }

    private func join() {
        isWorking = true
        Task {
            do {
                try await store.joinHousehold(code: code)
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isWorking = false
            }
        }
    }
}
