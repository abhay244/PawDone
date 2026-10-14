import SwiftUI

/// Editable pet details, shared by first-run setup and the edit screen.
struct PetFormModel: Equatable {
    var name = ""
    var species: PetSpecies = .dog
    var breed = ""
    var knowsBirthday = false
    var birthday = Date.now
    var gender: PetGender = .unknown

    init() {}

    init(pet: Pet) {
        name = pet.name
        species = pet.species
        breed = pet.breed ?? ""
        gender = pet.gender ?? .unknown
        if let birthDate = pet.birthDate, let date = Self.dayFormatter.date(from: birthDate) {
            knowsBirthday = true
            birthday = date
        }
    }

    var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 40
    }

    var fields: PetFields {
        let trimmedBreed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        return PetFields(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            species: species,
            breed: trimmedBreed.isEmpty ? nil : trimmedBreed,
            birthDate: knowsBirthday ? Self.dayFormatter.string(from: birthday) : nil,
            gender: gender
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct PetFormSections: View {
    @Binding var model: PetFormModel

    var body: some View {
        Section("Name") {
            TextField("e.g. Bruno", text: $model.name)
                .textInputAutocapitalization(.words)
        }

        Section("Type") {
            SpeciesPicker(selection: $model.species)
        }

        Section("Details (optional)") {
            TextField("Breed", text: $model.breed)
                .textInputAutocapitalization(.words)
            Picker("Gender", selection: $model.gender) {
                ForEach(PetGender.allCases) { gender in
                    Text(gender.label).tag(gender)
                }
            }
            Toggle("Birthday", isOn: $model.knowsBirthday)
            if model.knowsBirthday {
                DatePicker("Born on", selection: $model.birthday, in: ...Date.now, displayedComponents: .date)
            }
        }
    }
}

private struct SpeciesPicker: View {
    @Binding var selection: PetSpecies

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(PetSpecies.allCases) { species in
                let isSelected = selection == species
                Button {
                    selection = species
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: species.symbol)
                            .font(.title2)
                        Text(species.label)
                            .font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Edits the pet from the Account tab. Owner only.
struct PetEditView: View {
    @Environment(PetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var model = PetFormModel()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            PetFormSections(model: $model)
        }
        .navigationTitle("Edit pet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!model.isValid || isSaving)
            }
        }
        .onAppear {
            if let pet = store.pet { model = PetFormModel(pet: pet) }
        }
        .alert("Couldn't save", isPresented: isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await store.updatePet(model.fields)
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isSaving = false
            }
        }
    }
}
