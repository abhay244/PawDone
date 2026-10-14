import SwiftUI

/// Adds a task, or edits one when `task` is set.
struct TaskEditorView: View {
    @Environment(PetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let task: PetTask?

    @State private var title: String
    @State private var category: TaskCategory
    @State private var time: Date
    @State private var weekdays: Weekdays
    @State private var reminderEnabled: Bool
    @State private var instructions: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(task: PetTask?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? .food)
        _time = State(initialValue: (task?.timeOfDay ?? TimeOfDay(hour: 8, minute: 0)).date)
        _weekdays = State(initialValue: task?.weekdays ?? .everyDay)
        _reminderEnabled = State(initialValue: task?.reminderEnabled ?? true)
        _instructions = State(initialValue: task?.instructions ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Morning food", text: $title)
                    Picker("Type", selection: $category) {
                        ForEach(TaskCategory.allCases) { category in
                            Label(category.label, systemImage: category.symbol).tag(category)
                        }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }

                Section("Repeat") {
                    Toggle("Every day", isOn: everyDay)
                    if weekdays != .everyDay {
                        WeekdayPicker(selection: $weekdays)
                    }
                }

                Section {
                    Toggle("Reminder", isOn: $reminderEnabled)
                } footer: {
                    Text("Sends a reminder at this time if the task isn't done yet.")
                }

                Section {
                    TextField("Optional, e.g. 1 cup of kibble", text: $instructions, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Shown to anyone marking this task, handy for family and helpers.")
                }
            }
            .navigationTitle(task == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .alert("Couldn't save the task", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= 60 && !weekdays.isEmpty && !isSaving
    }

    private var everyDay: Binding<Bool> {
        Binding(get: { weekdays == .everyDay }, set: { weekdays = $0 ? .everyDay : .workdays })
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        guard let petID = store.pet?.id else { return }
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = TaskFields(
            petID: petID,
            title: trimmedTitle,
            category: category,
            timeOfDay: TimeOfDay(date: time),
            weekdays: weekdays,
            reminderEnabled: reminderEnabled,
            instructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions
        )
        isSaving = true
        Task {
            do {
                try await store.saveTask(id: task?.id, fields: fields)
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isSaving = false
            }
        }
    }
}

/// Seven day buttons, Monday first. At least one day stays selected.
struct WeekdayPicker: View {
    @Binding var selection: Weekdays

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekdays.allDays, id: \.rawValue) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn, selection != day {
                        selection.remove(day)
                    } else {
                        selection.insert(day)
                    }
                } label: {
                    Text(day.shortName.prefix(2))
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.shortName)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
