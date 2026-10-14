import SwiftUI

/// First-run setup: your name, your pet, then starter tasks.
struct OnboardingView: View {
    @Environment(PetStore.self) private var store
    @State private var step: Step?

    enum Step {
        case name, pet, tasks
    }

    var body: some View {
        NavigationStack {
            switch currentStep {
            case .name:
                NameStep { step = .pet }
            case .pet:
                PetStep { step = .tasks }
            case .tasks:
                StarterTasksStep()
            }
        }
    }

    /// Resumes where the user left off if the app was closed mid-setup.
    private var currentStep: Step {
        if let step { return step }
        if store.pet != nil { return .tasks }
        return store.myName.isEmpty ? .name : .pet
    }
}

private struct NameStep: View {
    @Environment(PetStore.self) private var store
    let onContinue: () -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("Shown to family and helpers when you mark tasks done.")
            }
        }
        .navigationTitle("What's your name?")
        .safeAreaInset(edge: .bottom) {
            ContinueButton(title: "Continue", isEnabled: !trimmed.isEmpty && !isSaving, action: save)
        }
        .onAppear { name = store.myName }
        .alert("Couldn't save your name", isPresented: isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await store.saveName(trimmed)
                onContinue()
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isSaving = false
        }
    }
}

private struct PetStep: View {
    @Environment(PetStore.self) private var store
    let onContinue: () -> Void

    @State private var model = PetFormModel()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            PetFormSections(model: $model)
        }
        .navigationTitle("Add your pet")
        .safeAreaInset(edge: .bottom) {
            ContinueButton(title: "Continue", isEnabled: model.isValid && !isSaving, action: save)
        }
        .alert("Couldn't add your pet", isPresented: isShowingError) {
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
                try await store.createPet(model.fields)
                onContinue()
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isSaving = false
        }
    }
}

private struct StarterTasksStep: View {
    @Environment(PetStore.self) private var store

    @State private var suggestions: [StarterTask] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                ForEach($suggestions) { $suggestion in
                    HStack {
                        Toggle(isOn: $suggestion.isSelected) {
                            Label(suggestion.title, systemImage: suggestion.category.symbol)
                        }
                        DatePicker(
                            suggestion.title,
                            selection: $suggestion.time,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .disabled(!suggestion.isSelected)
                    }
                }
            } footer: {
                Text("Every day at these times. You can change them anytime in the Schedule tab.")
            }
        }
        .navigationTitle("Set up \(store.pet?.name ?? "your pet")'s day")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                ContinueButton(title: "Start", isEnabled: !isSaving) { finish(addingSuggestions: true) }
                Button("Skip for now") { finish(addingSuggestions: false) }
                    .disabled(isSaving)
                    .padding(.bottom, 8)
            }
            .background(.bar)
        }
        .onAppear {
            if suggestions.isEmpty, let species = store.pet?.species {
                suggestions = StarterTask.suggestions(for: species)
            }
        }
        .alert("Couldn't add the tasks", isPresented: isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func finish(addingSuggestions: Bool) {
        guard let petID = store.pet?.id else { return }
        let tasks = addingSuggestions
            ? suggestions.filter(\.isSelected).map {
                TaskFields(petID: petID, title: $0.title, category: $0.category, timeOfDay: TimeOfDay(date: $0.time))
            }
            : []
        isSaving = true
        Task {
            do {
                try await store.finishOnboarding(addingTasks: tasks)
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isSaving = false
            }
        }
    }
}

/// A suggested daily task in first-run setup.
struct StarterTask: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var category: TaskCategory
    var time: Date
    var isSelected: Bool

    init(_ title: String, _ category: TaskCategory, _ hour: Int, _ minute: Int = 0, selected: Bool = true) {
        self.title = title
        self.category = category
        self.time = TimeOfDay(hour: hour, minute: minute).date
        self.isSelected = selected
    }

    static func suggestions(for species: PetSpecies) -> [StarterTask] {
        switch species {
        case .dog:
            [
                StarterTask("Morning walk", .walk, 7, 30),
                StarterTask("Morning food", .food, 8),
                StarterTask("Fresh water", .water, 9),
                StarterTask("Evening walk", .walk, 18, 30),
                StarterTask("Evening food", .food, 19),
                StarterTask("Medicine", .medicine, 21, selected: false),
            ]
        case .cat:
            [
                StarterTask("Morning food", .food, 8),
                StarterTask("Fresh water", .water, 9),
                StarterTask("Clean litter box", .cleanup, 10),
                StarterTask("Play time", .play, 18, selected: false),
                StarterTask("Evening food", .food, 19),
                StarterTask("Medicine", .medicine, 21, selected: false),
            ]
        case .bird, .rabbit, .fish, .other:
            [
                StarterTask("Morning food", .food, 8),
                StarterTask("Fresh water", .water, 9),
                StarterTask("Clean-up", .cleanup, 10, selected: false),
                StarterTask("Evening food", .food, 19),
                StarterTask("Medicine", .medicine, 21, selected: false),
            ]
        }
    }
}

/// Full-width primary button pinned to the bottom of a setup step.
struct ContinueButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
