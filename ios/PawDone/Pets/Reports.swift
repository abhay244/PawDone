import Foundation

extension Occurrence {
    /// Pending tasks on past days count as missed, even before the end-of-day job has
    /// marked them.
    nonisolated func effectiveStatus(today: String) -> Status {
        status == .pending && date < today ? .missed : status
    }
}

/// One day's results, for the calendar.
nonisolated struct DaySummary: Equatable, Sendable {
    enum Grade: Equatable, Sendable {
        /// Every task done.
        case allDone
        /// At least half done.
        case someMissed
        /// Less than half done.
        case mostlyMissed
        /// Today, with tasks still to do.
        case inProgress
        /// A future day.
        case upcoming
    }

    let date: String
    let total: Int
    let done: Int
    let missed: Int

    let grade: Grade

    init(date: String, occurrences: [Occurrence], today: String) {
        self.date = date
        total = occurrences.count
        done = occurrences.count { $0.effectiveStatus(today: today) == .done }
        missed = occurrences.count { $0.effectiveStatus(today: today) == .missed }

        if date > today {
            grade = .upcoming
        } else if done + missed < total {
            grade = .inProgress
        } else if missed == 0 {
            grade = .allDone
        } else if done * 2 >= total {
            grade = .someMissed
        } else {
            grade = .mostlyMissed
        }
    }
}

nonisolated enum Reports {
    /// Day summaries keyed by `yyyy-MM-dd`.
    static func summaries(for occurrences: [Occurrence], today: String) -> [String: DaySummary] {
        Dictionary(grouping: occurrences, by: \.date).mapValues { group in
            DaySummary(date: group[0].date, occurrences: group, today: today)
        }
    }

    /// Finished tasks in a period: done, missed, and the share done (nil when nothing has finished).
    static func totals(for occurrences: [Occurrence], today: String) -> (done: Int, missed: Int, rate: Double?) {
        let statuses = occurrences.map { $0.effectiveStatus(today: today) }
        let done = statuses.count(of: .done)
        let missed = statuses.count(of: .missed)
        let finished = done + missed
        return (done, missed, finished == 0 ? nil : Double(done) / Double(finished))
    }
}

private extension Array where Element: Equatable {
    nonisolated func count(of element: Element) -> Int {
        count { $0 == element }
    }
}

/// The days of one month laid out for a 7-column calendar, in the pet's timezone.
nonisolated struct MonthGrid: Equatable, Sendable {
    struct Cell: Identifiable, Equatable, Sendable {
        let id: Int
        /// Nil for the blank cells before the 1st.
        let day: Int?
        /// `yyyy-MM-dd`, nil for blank cells.
        let date: String?
    }

    let title: String
    let cells: [Cell]
    /// Very short weekday names in display order, e.g. M T W T F S S.
    let weekdaySymbols: [String]
    let firstDate: String
    let lastDate: String
    /// The first moment of the month, for moving between months.
    let start: Date

    init(containing date: Date, calendar: Calendar) {
        let timeZone = calendar.timeZone
        start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let leadingBlanks = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7

        var cells = (0..<leadingBlanks).map { Cell(id: -1 - $0, day: nil, date: nil) }
        for day in 1...dayCount {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: start) ?? start
            cells.append(Cell(id: day, day: day, date: ServerDate.dayString(for: dayDate, in: timeZone)))
        }
        self.cells = cells
        firstDate = cells.first { $0.date != nil }?.date ?? ""
        lastDate = cells.last?.date ?? ""

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        weekdaySymbols = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }

        var format = Date.FormatStyle(calendar: calendar, timeZone: timeZone).month(.wide).year()
        format.locale = calendar.locale ?? .current
        title = start.formatted(format)
    }

    func shifted(by months: Int, calendar: Calendar) -> MonthGrid {
        MonthGrid(containing: calendar.date(byAdding: .month, value: months, to: start) ?? start, calendar: calendar)
    }
}
