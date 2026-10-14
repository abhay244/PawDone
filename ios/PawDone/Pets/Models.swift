import Foundation

// Rows from the database. Column names follow supabase/migrations.

nonisolated enum PetSpecies: String, Codable, CaseIterable, Identifiable, Sendable {
    case dog, cat, bird, rabbit, fish, other

    var id: Self { self }

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .dog: "dog.fill"
        case .cat: "cat.fill"
        case .bird: "bird.fill"
        case .rabbit: "hare.fill"
        case .fish: "fish.fill"
        case .other: "pawprint.fill"
        }
    }
}

nonisolated enum PetGender: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female, unknown

    var id: Self { self }

    var label: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .unknown: "Not sure"
        }
    }
}

nonisolated struct Pet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let ownerID: UUID
    var name: String
    var species: PetSpecies
    var breed: String?
    /// `yyyy-MM-dd`
    var birthDate: String?
    var gender: PetGender?
    var notes: String?
    /// IANA name, e.g. "Asia/Kolkata". Task times are in this timezone.
    var timezone: String

    var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    enum CodingKeys: String, CodingKey {
        case id, name, species, breed, gender, notes, timezone
        case ownerID = "owner_id"
        case birthDate = "birth_date"
    }
}

/// The editable parts of a pet, for insert and update.
nonisolated struct PetFields: Encodable, Equatable, Sendable {
    var name: String
    var species: PetSpecies
    var breed: String?
    var birthDate: String?
    var gender: PetGender?

    enum CodingKeys: String, CodingKey {
        case name, species, breed, gender
        case birthDate = "birth_date"
    }

    // Encode nils as null so an update can clear a field.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(species, forKey: .species)
        try container.encode(breed, forKey: .breed)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encode(gender, forKey: .gender)
    }
}

nonisolated enum TaskCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, water, walk, medicine, grooming, play, cleanup, other

    var id: Self { self }

    var label: String {
        switch self {
        case .food: "Food"
        case .water: "Water"
        case .walk: "Walk"
        case .medicine: "Medicine"
        case .grooming: "Grooming"
        case .play: "Play"
        case .cleanup: "Clean-up"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .water: "drop.fill"
        case .walk: "figure.walk"
        case .medicine: "pills.fill"
        case .grooming: "scissors"
        case .play: "tennisball.fill"
        case .cleanup: "sparkles"
        case .other: "pawprint.fill"
        }
    }
}

nonisolated struct PetTask: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    var title: String
    var category: TaskCategory
    var timeOfDay: TimeOfDay
    var weekdays: Weekdays
    var reminderEnabled: Bool
    var instructions: String?

    enum CodingKeys: String, CodingKey {
        case id, title, category, weekdays, instructions
        case petID = "pet_id"
        case timeOfDay = "time_of_day"
        case reminderEnabled = "reminder_enabled"
    }
}

/// The editable parts of a task, for insert and update.
nonisolated struct TaskFields: Encodable, Equatable, Sendable {
    var petID: UUID
    var title: String
    var category: TaskCategory
    var timeOfDay: TimeOfDay
    var weekdays: Weekdays
    var reminderEnabled: Bool
    var instructions: String?

    init(
        petID: UUID,
        title: String,
        category: TaskCategory,
        timeOfDay: TimeOfDay,
        weekdays: Weekdays = .everyDay,
        reminderEnabled: Bool = true,
        instructions: String? = nil
    ) {
        self.petID = petID
        self.title = title
        self.category = category
        self.timeOfDay = timeOfDay
        self.weekdays = weekdays
        self.reminderEnabled = reminderEnabled
        self.instructions = instructions
    }

    init(_ task: PetTask) {
        self.init(
            petID: task.petID, title: task.title, category: task.category, timeOfDay: task.timeOfDay,
            weekdays: task.weekdays, reminderEnabled: task.reminderEnabled, instructions: task.instructions
        )
    }

    enum CodingKeys: String, CodingKey {
        case title, category, weekdays, instructions
        case petID = "pet_id"
        case timeOfDay = "time_of_day"
        case reminderEnabled = "reminder_enabled"
    }

    // Encode nils as null so an update can clear instructions.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(petID, forKey: .petID)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(timeOfDay, forKey: .timeOfDay)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encode(reminderEnabled, forKey: .reminderEnabled)
        try container.encode(instructions, forKey: .instructions)
    }
}

/// One task on one day.
nonisolated struct Occurrence: Decodable, Identifiable, Equatable, Sendable {
    enum Status: String, Decodable, Sendable {
        case pending, done, missed
    }

    let id: UUID
    let taskID: UUID
    let petID: UUID
    /// `yyyy-MM-dd` in the pet's timezone.
    let date: String
    let scheduledAt: Date
    let title: String
    let category: TaskCategory
    var status: Status
    var completedBy: UUID?
    var completedAt: Date?
    var note: String?
    var photoPath: String?
    /// From the task, when the query includes it.
    var instructions: String?

    enum CodingKeys: String, CodingKey {
        case id, date, title, category, status, note, task
        case taskID = "task_id"
        case petID = "pet_id"
        case scheduledAt = "scheduled_at"
        case completedBy = "completed_by"
        case completedAt = "completed_at"
        case photoPath = "photo_path"
    }

    private struct TaskDetails: Decodable {
        let instructions: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        taskID = try container.decode(UUID.self, forKey: .taskID)
        petID = try container.decode(UUID.self, forKey: .petID)
        date = try container.decode(String.self, forKey: .date)
        scheduledAt = try container.decodeServerDate(forKey: .scheduledAt)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(TaskCategory.self, forKey: .category)
        status = try container.decode(Status.self, forKey: .status)
        completedBy = try container.decodeIfPresent(UUID.self, forKey: .completedBy)
        completedAt = try container.decodeServerDateIfPresent(forKey: .completedAt)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        photoPath = try container.decodeIfPresent(String.self, forKey: .photoPath)
        instructions = try container.decodeIfPresent(TaskDetails.self, forKey: .task)?.instructions
    }
}

// MARK: - Value types

/// A time of day stored by Postgres as `HH:mm:ss`.
nonisolated struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init?(databaseValue: String) {
        let parts = databaseValue.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        self.init(hour: parts[0], minute: parts[1])
    }

    var databaseValue: String { String(format: "%02d:%02d:00", hour, minute) }

    /// A date on the reference day at this time, for `DatePicker` and formatting.
    var date: Date {
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) ?? .now
    }

    init(date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    var formatted: String { date.formatted(date: .omitted, time: .shortened) }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let time = TimeOfDay(databaseValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid time: \(value)")
        }
        self = time
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(databaseValue)
    }
}

/// Repeat days, matching the database bitmask: Mon = 1, Tue = 2, … Sun = 64.
nonisolated struct Weekdays: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let monday = Weekdays(rawValue: 1 << 0)
    static let tuesday = Weekdays(rawValue: 1 << 1)
    static let wednesday = Weekdays(rawValue: 1 << 2)
    static let thursday = Weekdays(rawValue: 1 << 3)
    static let friday = Weekdays(rawValue: 1 << 4)
    static let saturday = Weekdays(rawValue: 1 << 5)
    static let sunday = Weekdays(rawValue: 1 << 6)

    static let everyDay: Weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    static let workdays: Weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: Weekdays = [.saturday, .sunday]

    /// Monday first, as in the database.
    static let allDays: [Weekdays] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    /// Short name for a single day, e.g. "Mon".
    var shortName: String {
        guard let index = Self.allDays.firstIndex(of: self) else { return "" }
        // Calendar symbols start on Sunday.
        return Calendar.current.shortWeekdaySymbols[(index + 1) % 7]
    }

    var summary: String {
        switch self {
        case .everyDay: "Every day"
        case .workdays: "Weekdays"
        case .weekend: "Weekends"
        default: Self.allDays.filter(contains).map(\.shortName).joined(separator: ", ")
        }
    }

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Dates from the server

nonisolated enum ServerDate {
    /// Parses Postgres timestamps such as `2026-10-14T02:30:00.123456+00:00`, honouring the offset.
    static func parse(_ string: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
    }

    /// The calendar day of `date` in `timeZone`, as `yyyy-MM-dd`.
    static func dayString(for date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

nonisolated extension KeyedDecodingContainer {
    func decodeServerDate(forKey key: Key) throws -> Date {
        let value = try decode(String.self, forKey: key)
        guard let date = ServerDate.parse(value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid date: \(value)")
        }
        return date
    }

    func decodeServerDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = ServerDate.parse(value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid date: \(value)")
        }
        return date
    }
}
