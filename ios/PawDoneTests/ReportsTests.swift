import Foundation
import Testing
@testable import PawDone

struct ReportsTests {
    let petID = UUID()

    func occurrence(_ date: String, _ status: String) -> Occurrence {
        let json: [String: Any] = [
            "id": UUID().uuidString, "task_id": UUID().uuidString, "pet_id": petID.uuidString,
            "date": date, "scheduled_at": "\(date)T08:00:00+00:00", "title": "Task", "category": "food", "status": status,
        ]
        return try! JSONDecoder().decode(Occurrence.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: Day summaries

    @Test func pendingOnPastDayCountsAsMissed() {
        let summary = DaySummary(
            date: "2026-10-13",
            occurrences: [occurrence("2026-10-13", "done"), occurrence("2026-10-13", "pending")],
            today: "2026-10-14"
        )
        #expect(summary.done == 1)
        #expect(summary.missed == 1)
        #expect(summary.grade == .someMissed)
    }

    @Test(arguments: [
        (["done", "done", "done"], DaySummary.Grade.allDone),
        (["done", "done", "missed"], .someMissed),
        (["done", "missed"], .someMissed),
        (["done", "missed", "missed"], .mostlyMissed),
    ])
    func gradesFinishedDays(statuses: [String], grade: DaySummary.Grade) {
        let summary = DaySummary(date: "2026-10-12", occurrences: statuses.map { occurrence("2026-10-12", $0) }, today: "2026-10-14")
        #expect(summary.grade == grade)
    }

    @Test func todayWithTasksLeftIsInProgress() {
        let summary = DaySummary(
            date: "2026-10-14",
            occurrences: [occurrence("2026-10-14", "done"), occurrence("2026-10-14", "pending")],
            today: "2026-10-14"
        )
        #expect(summary.grade == .inProgress)
        #expect(summary.missed == 0)
    }

    @Test func futureDayIsUpcoming() {
        let summary = DaySummary(date: "2026-10-15", occurrences: [occurrence("2026-10-15", "pending")], today: "2026-10-14")
        #expect(summary.grade == .upcoming)
    }

    @Test func summariesGroupByDay() {
        let summaries = Reports.summaries(
            for: [occurrence("2026-10-12", "done"), occurrence("2026-10-12", "missed"), occurrence("2026-10-13", "done")],
            today: "2026-10-14"
        )
        #expect(summaries["2026-10-12"]?.total == 2)
        #expect(summaries["2026-10-13"]?.grade == .allDone)
    }

    @Test func totalsIgnoreUnfinishedTasks() throws {
        let totals = Reports.totals(
            for: [
                occurrence("2026-10-12", "done"), occurrence("2026-10-12", "done"), occurrence("2026-10-12", "done"),
                occurrence("2026-10-13", "missed"),
                occurrence("2026-10-14", "pending"),
            ],
            today: "2026-10-14"
        )
        #expect(totals.done == 3)
        #expect(totals.missed == 1)
        #expect(try #require(totals.rate) == 0.75)
        #expect(Reports.totals(for: [], today: "2026-10-14").rate == nil)
    }

    // MARK: Month grid

    func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test func octoberStartingMonday() throws {
        let date = try #require(ServerDate.parse("2026-10-14T10:00:00+05:30"))
        let grid = MonthGrid(containing: date, calendar: calendar(firstWeekday: 2))

        // 1 October 2026 is a Thursday: three blanks (Mon–Wed) before it.
        #expect(grid.cells.prefix(4).map(\.day) == [nil, nil, nil, 1])
        #expect(grid.cells.compactMap(\.day).count == 31)
        #expect(grid.firstDate == "2026-10-01")
        #expect(grid.lastDate == "2026-10-31")
        #expect(grid.weekdaySymbols.first == "M")
        #expect(grid.title == "October 2026")
    }

    @Test func octoberStartingSunday() throws {
        let date = try #require(ServerDate.parse("2026-10-14T10:00:00+05:30"))
        let grid = MonthGrid(containing: date, calendar: calendar(firstWeekday: 1))

        #expect(grid.cells.prefix(5).map(\.day) == [nil, nil, nil, nil, 1])
        #expect(grid.weekdaySymbols.first == "S")
    }

    @Test func monthBoundaryUsesPetTimezone() throws {
        // 20:00 UTC on 31 Oct is already 1 Nov in India.
        let date = try #require(ServerDate.parse("2026-10-31T20:00:00Z"))
        let grid = MonthGrid(containing: date, calendar: calendar(firstWeekday: 2))

        #expect(grid.firstDate == "2026-11-01")
        #expect(grid.lastDate == "2026-11-30")
    }

    @Test func shiftingAcrossYear() throws {
        let date = try #require(ServerDate.parse("2026-01-10T10:00:00+05:30"))
        let calendar = calendar(firstWeekday: 2)
        let previous = MonthGrid(containing: date, calendar: calendar).shifted(by: -1, calendar: calendar)

        #expect(previous.firstDate == "2025-12-01")
        #expect(previous.lastDate == "2025-12-31")
    }
}

@MainActor
struct PetStoreReportTests {
    @Test func fetchesRangeForThePet() async throws {
        let backend = FakePetBackend()
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        backend.occurrences = [
            .make(petID: pet.id, date: "2026-10-01", scheduledAt: "2026-10-01T08:00:00+00:00"),
            .make(petID: pet.id, date: "2026-11-01", scheduledAt: "2026-11-01T08:00:00+00:00"),
        ]
        let store = PetStore(backend: backend)
        await store.load()

        let october = try await store.occurrences(from: "2026-10-01", to: "2026-10-31")

        #expect(october.map(\.date) == ["2026-10-01"])
        #expect(backend.requestedRanges == ["2026-10-01"..."2026-10-31"])
    }
}
