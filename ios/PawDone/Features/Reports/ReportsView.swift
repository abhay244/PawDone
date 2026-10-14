import SwiftUI

/// A month calendar of daily scores, with the selected day's tasks below.
struct ReportsView: View {
    @Environment(PetStore.self) private var store

    @State private var month: MonthGrid?
    @State private var occurrences: [Occurrence] = []
    @State private var selectedDate: String?
    @State private var loadFailed = false
    @State private var viewing: Occurrence?

    var body: some View {
        NavigationStack {
            List {
                if let month {
                    Section {
                        MonthHeader(
                            title: month.title,
                            canGoForward: month.lastDate < store.todayString,
                            onPrevious: { show(month.shifted(by: -1, calendar: store.calendar)) },
                            onNext: { show(month.shifted(by: 1, calendar: store.calendar)) }
                        )
                        MonthCalendar(
                            month: month,
                            summaries: summaries,
                            today: store.todayString,
                            selection: $selectedDate
                        )
                    } footer: {
                        if loadFailed {
                            Text("Couldn't load this month. Pull down to try again.")
                        } else {
                            MonthTotalsText(occurrences: occurrences, today: store.todayString)
                        }
                    }

                    dayDetail
                }
            }
            .navigationTitle("Reports")
            .refreshable { await load() }
            .onAppear {
                if month == nil {
                    month = MonthGrid(containing: store.now, calendar: store.calendar)
                    selectedDate = store.todayString
                }
                Task { await load() }
            }
            .sheet(item: $viewing, onDismiss: { Task { await load() } }) {
                OccurrenceDetailSheet(occurrence: $0)
            }
        }
    }

    private var summaries: [String: DaySummary] {
        Reports.summaries(for: occurrences, today: store.todayString)
    }

    @ViewBuilder private var dayDetail: some View {
        if let selectedDate {
            let dayOccurrences = occurrences.filter { $0.date == selectedDate }
            Section(dayTitle(for: selectedDate)) {
                if dayOccurrences.isEmpty {
                    Text("No tasks on this day.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dayOccurrences) { occurrence in
                        Button {
                            viewing = occurrence
                        } label: {
                            OccurrenceRow(occurrence: occurrence)
                        }
                        .tint(.primary)
                    }
                }
            }
        } else {
            Section {
                Text("Tap a day to see what was done and what was missed.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dayTitle(for date: String) -> String {
        if date == store.todayString { return "Today" }
        guard let day = Self.dayParser(store.calendar.timeZone).date(from: date) else { return date }
        return day.formatted(Date.FormatStyle(timeZone: store.calendar.timeZone).weekday(.wide).day().month(.wide))
    }

    private static func dayParser(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func show(_ newMonth: MonthGrid) {
        month = newMonth
        let today = store.todayString
        selectedDate = (newMonth.firstDate...newMonth.lastDate).contains(today) ? today : nil
        occurrences = []
        Task { await load() }
    }

    private func load() async {
        guard let month else { return }
        do {
            let loaded = try await store.occurrences(from: month.firstDate, to: month.lastDate)
            // Ignore results for a month the user has already moved away from.
            guard month == self.month else { return }
            occurrences = loaded
            loadFailed = false
        } catch {
            guard month == self.month, !(error is CancellationError) else { return }
            _ = UserFacingError.message(for: error) // Logs the details.
            loadFailed = true
        }
    }
}

private struct MonthHeader: View {
    let title: String
    let canGoForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(title)
                .font(.headline)
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}

private struct MonthCalendar: View {
    let month: MonthGrid
    let summaries: [String: DaySummary]
    let today: String
    @Binding var selection: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(month.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(month.cells) { cell in
                    if let day = cell.day, let date = cell.date {
                        DayCell(
                            day: day,
                            summary: summaries[date],
                            isToday: date == today,
                            isFuture: date > today,
                            isSelected: date == selection
                        ) {
                            selection = date
                        }
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DayCell: View {
    let day: Int
    let summary: DaySummary?
    let isToday: Bool
    let isFuture: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isFuture ? Color.secondary : Color.primary)
                if let summary, summary.total > 0, !isFuture {
                    Text("\(summary.done)/\(summary.total)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(gradeColor(summary.grade))
                } else {
                    Text(" ")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        var text = "\(day)"
        if isToday { text += ", today" }
        if let summary, summary.total > 0, !isFuture {
            text += ", \(summary.done) of \(summary.total) done"
        }
        return text
    }
}

func gradeColor(_ grade: DaySummary.Grade) -> Color {
    switch grade {
    case .allDone: .green
    case .someMissed: .orange
    case .mostlyMissed: .red
    case .inProgress, .upcoming: .secondary
    }
}

private struct MonthTotalsText: View {
    let occurrences: [Occurrence]
    let today: String

    var body: some View {
        let totals = Reports.totals(for: occurrences, today: today)
        if let rate = totals.rate {
            Text("\(rate.formatted(.percent.precision(.fractionLength(0)))) done this month · \(totals.missed) missed")
        } else {
            Text("No finished tasks this month yet.")
        }
    }
}
