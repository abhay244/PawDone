import SwiftUI

struct AccountView: View {
    @Environment(PetStore.self) private var store
    @Environment(SessionStore.self) private var session

    @State private var name = ""
    @State private var isSavingName = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let pet = store.pet {
                    Section("Pet") {
                        if store.isOwner {
                            NavigationLink {
                                PetEditView()
                            } label: {
                                PetSummaryRow(pet: pet)
                            }
                        } else {
                            PetSummaryRow(pet: pet)
                        }
                    }
                }

                if let pet = store.pet {
                    Section {
                        Toggle("Reminders for \(pet.name)", isOn: remindersEnabled)
                        if PushRegistrar.shared.authorizationStatus == .denied {
                            Button("Turn on notifications in Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    } header: {
                        Text("Notifications")
                    } footer: {
                        Text(PushRegistrar.shared.authorizationStatus == .denied
                            ? "Notifications are off for PawDone, so reminders can't reach this phone."
                            : "A notification when one of \(pet.name)'s tasks is due and not done yet.")
                    }
                }

                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                    if nameChanged {
                        Button("Save name", action: saveName)
                            .disabled(isSavingName)
                    }
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Shown to family and helpers when you mark tasks done.")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("Account")
            .onAppear { name = store.myName }
            .alert("Couldn't save", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var remindersEnabled: Binding<Bool> {
        Binding(
            get: { store.remindersEnabled },
            set: { enabled in
                Task {
                    do {
                        try await store.setRemindersEnabled(enabled)
                    } catch {
                        errorMessage = UserFacingError.message(for: error)
                    }
                }
            }
        )
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameChanged: Bool { !trimmedName.isEmpty && trimmedName != store.myName }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func saveName() {
        guard nameChanged else { return }
        isSavingName = true
        Task {
            do {
                try await store.saveName(trimmedName)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isSavingName = false
        }
    }
}

private struct PetSummaryRow: View {
    let pet: Pet

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pet.species.symbol)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(pet.name)
                    .font(.body.weight(.medium))
                Text([pet.species.label, pet.breed].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
