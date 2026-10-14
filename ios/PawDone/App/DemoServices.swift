#if DEBUG
import Foundation

// Demo mode: launch with `-PawDoneDemo` to use the app signed in, with in-memory data and
// no server. For checking screens in the simulator, where Sign in with Apple is unreliable,
// and for screenshots. Debug builds only.

extension AppServices {
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-PawDoneDemo") }

    static func demo() -> AppServices {
        AppServices(
            session: SessionStore(backend: DemoSessionBackend(), deviceID: "demo-device"),
            petBackend: DemoPetBackend()
        )
    }
}

private final class DemoSessionBackend: SessionBackend {
    var hasSession: Bool { true }
    func signInWithApple(idToken: String, nonce: String) async throws {}
    func saveProfileName(_ name: String) async throws {}
    func registerDevice(id: String, force: Bool) async throws -> DeviceRegistration { .registered }
    func deviceStatus(id: String) async throws -> DeviceStatus { .active }
    func signOut() async {}
    func sessionEndedEvents() -> AsyncStream<Void> { AsyncStream { _ in } }
}

private final class DemoPetBackend: PetBackend {
    let currentUserID: UUID? = UUID()
    private var myName = ""
    private var pets: [Pet] = []
    private var tasks: [PetTask] = []
    private var occurrences: [Occurrence] = []

    func fetchMyName() async throws -> String { myName }
    func saveMyName(_ name: String) async throws { myName = name }

    func fetchProfileNames() async throws -> [UUID: String] {
        currentUserID.map { [$0: myName] } ?? [:]
    }

    func fetchPets() async throws -> [Pet] { pets }

    func createPet(_ fields: PetFields, timezone: String) async throws -> Pet {
        let pet = Pet(
            id: UUID(), ownerID: currentUserID!, name: fields.name, species: fields.species,
            breed: fields.breed, birthDate: fields.birthDate, gender: fields.gender, timezone: timezone
        )
        pets = [pet]
        return pet
    }

    func updatePet(id: UUID, fields: PetFields) async throws -> Pet {
        pets[0].name = fields.name
        pets[0].species = fields.species
        pets[0].breed = fields.breed
        pets[0].birthDate = fields.birthDate
        pets[0].gender = fields.gender
        return pets[0]
    }

    func fetchTasks(petID: UUID) async throws -> [PetTask] {
        tasks.sorted { $0.timeOfDay < $1.timeOfDay }
    }

    func createTasks(_ newTasks: [TaskFields]) async throws {
        for fields in newTasks {
            let task = PetTask(
                id: UUID(), petID: fields.petID, title: fields.title, category: fields.category,
                timeOfDay: fields.timeOfDay, weekdays: fields.weekdays, reminderEnabled: fields.reminderEnabled,
                instructions: fields.instructions
            )
            tasks.append(task)
            occurrences.append(occurrence(for: task))
            addHistory(for: task, index: tasks.count)
        }
    }

    /// Four weeks of past days for reports, mostly done with a few misses.
    private func addHistory(for task: PetTask, index: Int) {
        for daysAgo in 1...28 {
            let missed = (daysAgo * 7 + index * 3) % 11 == 0 || (daysAgo == 3 && index <= 3)
            occurrences.append(occurrence(for: task, daysAgo: daysAgo, done: !missed))
        }
    }

    func updateTask(id: UUID, fields: TaskFields) async throws {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].title = fields.title
        tasks[index].category = fields.category
        tasks[index].timeOfDay = fields.timeOfDay
        tasks[index].weekdays = fields.weekdays
        tasks[index].reminderEnabled = fields.reminderEnabled
        tasks[index].instructions = fields.instructions
        occurrences.removeAll { $0.taskID == id && $0.status == .pending }
        occurrences.append(occurrence(for: tasks[index]))
    }

    func archiveTask(id: UUID) async throws {
        tasks.removeAll { $0.id == id }
        occurrences.removeAll { $0.taskID == id && $0.status == .pending }
    }

    func fetchOccurrences(petID: UUID, date: String) async throws -> [Occurrence] {
        occurrences.filter { $0.date == date }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func fetchOccurrences(petID: UUID, from: String, to: String) async throws -> [Occurrence] {
        occurrences.filter { (from...to).contains($0.date) }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func completeOccurrence(id: UUID, note: String?) async throws -> Occurrence {
        guard let index = occurrences.firstIndex(where: { $0.id == id }) else { throw NotSignedIn() }
        occurrences[index].status = .done
        occurrences[index].completedBy = currentUserID
        occurrences[index].completedAt = .now
        occurrences[index].note = note
        return occurrences[index]
    }

    func undoOccurrence(id: UUID) async throws -> Occurrence {
        guard let index = occurrences.firstIndex(where: { $0.id == id }) else { throw NotSignedIn() }
        occurrences[index].status = .pending
        occurrences[index].completedBy = nil
        occurrences[index].completedAt = nil
        occurrences[index].note = nil
        return occurrences[index]
    }

    /// An occurrence of a task, built the way the server would send it: pending today,
    /// or done or missed on a past day.
    private func occurrence(for task: PetTask, daysAgo: Int = 0, done: Bool = false) -> Occurrence {
        let timeZone = pets.first?.timeZone ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let scheduled = calendar.date(bySettingHour: task.timeOfDay.hour, minute: task.timeOfDay.minute, second: 0, of: day) ?? day
        var json: [String: Any] = [
            "id": UUID().uuidString, "task_id": task.id.uuidString, "pet_id": task.petID.uuidString,
            "date": ServerDate.dayString(for: day, in: timeZone), "scheduled_at": scheduled.ISO8601Format(),
            "title": task.title, "category": task.category.rawValue,
            "status": daysAgo == 0 ? "pending" : done ? "done" : "missed",
            "task": ["instructions": task.instructions.map { $0 as Any } ?? NSNull()],
        ]
        if daysAgo > 0, done, let currentUserID {
            json["completed_by"] = currentUserID.uuidString
            json["completed_at"] = scheduled.addingTimeInterval(8 * 60).ISO8601Format()
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Occurrence.self, from: data)
    }
}
#endif
