import SwiftUI

struct ScheduleView: View {
    @Environment(PetStore.self) private var store
    @State private var editing: EditorTarget?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if store.tasks.isEmpty {
                    ContentUnavailableView {
                        Label("No tasks yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Add feeding, walks, medicine and anything else your pet needs each day.")
                    } actions: {
                        if store.isOwner {
                            Button("Add task") { editing = .new }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.tasks) { task in
                            if store.isOwner {
                                Button {
                                    editing = .existing(task)
                                } label: {
                                    TaskRow(task: task)
                                }
                                .tint(.primary)
                                .swipeActions {
                                    Button("Remove", role: .destructive) { remove(task) }
                                }
                            } else {
                                TaskRow(task: task)
                            }
                        }
                    } footer: {
                        Text(store.isOwner
                            ? "Changes apply from today. Past days keep their history."
                            : "Only the owner can change the schedule.")
                    }
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                if store.isOwner {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add task", systemImage: "plus") { editing = .new }
                    }
                }
            }
            .sheet(item: $editing) { target in
                TaskEditorView(task: target.task)
            }
            .alert("Couldn't remove the task", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func remove(_ task: PetTask) {
        Task {
            do {
                try await store.removeTask(task)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

private enum EditorTarget: Identifiable {
    case new
    case existing(PetTask)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let task): task.id.uuidString
        }
    }

    var task: PetTask? {
        if case .existing(let task) = self { task } else { nil }
    }
}

private struct TaskRow: View {
    let task: PetTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.category.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.15), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body.weight(.medium))
                Text("\(task.timeOfDay.formatted) · \(task.weekdays.summary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !task.reminderEnabled {
                Image(systemName: "bell.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No reminder")
            }
        }
        .contentShape(.rect)
    }
}
