import SwiftUI

struct TodayView: View {
    @Environment(PetStore.self) private var store
    @State private var completing: Occurrence?
    @State private var viewing: Occurrence?

    var body: some View {
        NavigationStack {
            List {
                if let pet = store.pet {
                    Section {
                        TodayHeader(pet: pet, done: store.doneCount, total: store.today.count)
                    }
                }

                if store.today.isEmpty {
                    ContentUnavailableView(
                        "Nothing scheduled today",
                        systemImage: "calendar.badge.checkmark",
                        description: Text(store.isOwner
                            ? "Add feeding, walks and more in the Schedule tab."
                            : "The owner hasn't scheduled anything for today.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.today) { occurrence in
                            Button {
                                open(occurrence)
                            } label: {
                                OccurrenceRow(occurrence: occurrence)
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .refreshable { await store.refreshToday() }
            .sheet(item: $completing) { MarkDoneSheet(occurrence: $0) }
            .sheet(item: $viewing) { OccurrenceDetailSheet(occurrence: $0) }
        }
    }

    private func open(_ occurrence: Occurrence) {
        switch occurrence.status {
        case .pending:
            completing = occurrence
        case .done, .missed:
            viewing = occurrence
        }
    }
}

private struct TodayHeader: View {
    let pet: Pet
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: pet.species.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(pet.name)'s day")
                    .font(.headline)
                Text(Date.now.formatted(Date.FormatStyle(timeZone: pet.timeZone).weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                        .padding(.top, 4)
                    Text("\(done) of \(total) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct OccurrenceRow: View {
    @Environment(PetStore.self) private var store
    let occurrence: Occurrence

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: occurrence.category.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.15), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(isOverdue ? Color.orange : .secondary)
            }

            Spacer()

            if store.photos.hasPhoto(for: occurrence.id) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Has photo")
            }
            statusIcon
        }
        .contentShape(.rect)
    }

    private var status: Occurrence.Status { occurrence.effectiveStatus(today: store.todayString) }

    private var isOverdue: Bool { status == .pending && store.isOverdue(occurrence) }

    private var detail: String {
        switch status {
        case .done:
            let time = occurrence.completedAt.map { " at \(store.time($0))" } ?? ""
            return "\(store.name(for: occurrence.completedBy))\(time)"
        case .missed:
            return "Missed"
        case .pending:
            let due = store.time(occurrence.scheduledAt)
            return isOverdue ? "Overdue · was due \(due)" : "Due \(due)"
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityLabel("Done")
        case .missed:
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .accessibilityLabel("Missed")
        case .pending:
            Image(systemName: isOverdue ? "exclamationmark.circle" : "circle")
                .font(.title2)
                .foregroundStyle(isOverdue ? Color.orange : .secondary)
                .accessibilityLabel(isOverdue ? "Overdue" : "Not done yet")
        }
    }
}
