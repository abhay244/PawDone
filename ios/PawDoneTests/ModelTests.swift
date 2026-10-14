import Foundation
import Testing
import UIKit
@testable import PawDone

struct ServerDateTests {
    @Test(arguments: [
        ("2026-10-14T02:30:00+00:00", "2026-10-14T02:30:00Z"),
        ("2026-10-14T02:30:00.123456+00:00", "2026-10-14T02:30:00Z"),
        ("2026-10-14T08:00:00+05:30", "2026-10-14T02:30:00Z"),
        ("2026-10-14T02:30:00Z", "2026-10-14T02:30:00Z"),
    ])
    func parsesPostgresTimestampsWithOffsets(input: String, expectedUTC: String) throws {
        let date = try #require(ServerDate.parse(input))
        #expect(date.ISO8601Format() == expectedUTC)
    }

    @Test func dayStringUsesTimezone() throws {
        let date = try #require(ServerDate.parse("2026-10-13T20:00:00Z"))
        #expect(ServerDate.dayString(for: date, in: TimeZone(identifier: "Asia/Kolkata")!) == "2026-10-14")
        #expect(ServerDate.dayString(for: date, in: TimeZone(identifier: "America/New_York")!) == "2026-10-13")
    }
}

struct ModelDecodingTests {
    @Test func decodesOccurrenceFromPostgrest() throws {
        let json = """
        {
          "id": "6f1c1d4e-3a6b-4c8e-9a51-1d2f3e4a5b6c",
          "task_id": "0b7e2a4c-8d9f-4e1a-b2c3-d4e5f6a7b8c9",
          "pet_id": "9a8b7c6d-5e4f-4a3b-2c1d-0e9f8a7b6c5d",
          "date": "2026-10-14",
          "scheduled_at": "2026-10-14T13:30:00+00:00",
          "title": "Dinner",
          "category": "food",
          "status": "done",
          "completed_by": "1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e",
          "completed_at": "2026-10-14T13:35:12.481523+00:00",
          "note": "Ate half",
          "photo_path": null,
          "reminder_sent_at": null,
          "task": { "instructions": "1 cup of kibble" }
        }
        """
        let occurrence = try JSONDecoder().decode(Occurrence.self, from: Data(json.utf8))

        #expect(occurrence.status == .done)
        #expect(occurrence.category == .food)
        #expect(occurrence.instructions == "1 cup of kibble")
        #expect(occurrence.completedAt?.ISO8601Format() == "2026-10-14T13:35:12Z")
    }

    @Test func decodesTask() throws {
        let json = """
        {
          "id": "6f1c1d4e-3a6b-4c8e-9a51-1d2f3e4a5b6c",
          "pet_id": "9a8b7c6d-5e4f-4a3b-2c1d-0e9f8a7b6c5d",
          "title": "Bath",
          "category": "grooming",
          "time_of_day": "18:30:00",
          "weekdays": 96,
          "reminder_enabled": false,
          "instructions": null,
          "starts_at": "2026-10-14T00:00:00+00:00",
          "created_at": "2026-10-14T00:00:00+00:00",
          "archived_at": null
        }
        """
        let task = try JSONDecoder().decode(PetTask.self, from: Data(json.utf8))

        #expect(task.timeOfDay == TimeOfDay(hour: 18, minute: 30))
        #expect(task.weekdays == .weekend)
        #expect(!task.reminderEnabled)
    }

    @Test func taskFieldsEncodeForDatabase() throws {
        let petID = UUID()
        let fields = TaskFields(petID: petID, title: "Walk", category: .walk, timeOfDay: TimeOfDay(hour: 7, minute: 5))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fields)) as! [String: Any]

        #expect(json["time_of_day"] as? String == "07:05:00")
        #expect(json["weekdays"] as? Int == 127)
        #expect(json["pet_id"] as? String == petID.uuidString)
        #expect(json["instructions"] is NSNull, "nil is sent as null so edits can clear it")
    }
}

struct WeekdaysTests {
    @Test func bitsMatchDatabase() {
        // Database: Mon = 1, Tue = 2, … Sun = 64 (see generate_occurrences).
        #expect(Weekdays.monday.rawValue == 1)
        #expect(Weekdays.sunday.rawValue == 64)
        #expect(Weekdays.everyDay.rawValue == 127)
    }

    @Test func summaries() {
        #expect(Weekdays.everyDay.summary == "Every day")
        #expect(Weekdays.workdays.summary == "Weekdays")
        #expect(Weekdays.weekend.summary == "Weekends")
        #expect(Weekdays([.monday, .wednesday]).summary.split(separator: ",").count == 2)
    }
}

struct TimeOfDayTests {
    @Test func roundTripsDatabaseValue() {
        #expect(TimeOfDay(databaseValue: "08:30:00") == TimeOfDay(hour: 8, minute: 30))
        #expect(TimeOfDay(hour: 21, minute: 5).databaseValue == "21:05:00")
        #expect(TimeOfDay(databaseValue: "25:00:00") == nil)
    }

    @Test func roundTripsThroughDate() {
        let time = TimeOfDay(hour: 19, minute: 45)
        #expect(TimeOfDay(date: time.date) == time)
    }
}

struct ProofPhotoStoreTests {
    @Test func savesResizedPhotoAndDeletes() throws {
        let store = ProofPhotoStore(directory: .temporaryDirectory.appending(path: "ProofPhotoStoreTests-\(UUID().uuidString)"))
        let id = UUID()
        let large = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }

        try store.save(large, for: id)
        let saved = try #require(store.image(for: id))
        #expect(max(saved.size.width * saved.scale, saved.size.height * saved.scale) <= ProofPhotoStore.maxDimension)

        store.delete(for: id)
        #expect(!store.hasPhoto(for: id))
    }
}
