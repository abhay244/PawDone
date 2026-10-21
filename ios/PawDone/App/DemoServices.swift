#if DEBUG
import Foundation

// Demo mode: launch with `-PawDoneDemo` to use the app signed in, with in-memory data and
// no server. For checking screens in the simulator, where Sign in with Apple is unreliable.
// Launch with `-PawDoneScreenshots` instead to skip setup and start with a lived-in account,
// for App Store screenshots (see docs/APP_STORE.md). Add `-PawDoneFreePlan` to start that
// account without Premium, to show the paywall. Debug builds only.

extension AppServices {
    static var isDemo: Bool { isScreenshotDemo || ProcessInfo.processInfo.arguments.contains("-PawDoneDemo") }
    static var isScreenshotDemo: Bool { ProcessInfo.processInfo.arguments.contains("-PawDoneScreenshots") }
    static var isFreePlanDemo: Bool { ProcessInfo.processInfo.arguments.contains("-PawDoneFreePlan") }

    static func demo() -> AppServices {
        AppServices(
            session: SessionStore(backend: DemoSessionBackend(), deviceID: "demo-device"),
            petBackend: DemoPetBackend(seeded: isScreenshotDemo, freePlan: isFreePlanDemo),
            subscriptions: DemoSubscriptionService()
        )
    }
}

private final class DemoSessionBackend: SessionBackend {
    var hasSession: Bool { true }
    var signedInWithApple: Bool { false }
    func signInWithApple(idToken: String, nonce: String) async throws {}
    func signInWithGoogle(idToken: String, accessToken: String) async throws {}
    func saveProfileNameIfMissing(_ name: String) async throws {}
    func registerDevice(id: String, force: Bool) async throws -> DeviceRegistration { .registered }
    func deviceStatus(id: String) async throws -> DeviceStatus { .active }
    func setPushToken(_ token: String?, deviceID: String, environment: String) async throws {}
    func deleteAccount(appleAuthorizationCode: String?) async throws { try await Task.sleep(for: .seconds(1)) }
    func signOut() async {}
    func sessionEndedEvents() -> AsyncStream<Void> { AsyncStream { _ in } }
}

private final class DemoSubscriptionService: SubscriptionService {
    func start(userID: String) async {}

    func plans() async throws -> [PremiumPlan] {
        try await Task.sleep(for: .milliseconds(400))
        return [
            PremiumPlan(id: "demo.monthly", period: .monthly, price: "₹199.00", pricePerMonth: nil),
            PremiumPlan(id: "demo.quarterly", period: .threeMonths, price: "₹499.00", pricePerMonth: "₹166.33"),
        ]
    }

    func purchase(_ plan: PremiumPlan) async throws -> PurchaseOutcome {
        try await Task.sleep(for: .seconds(1))
        return .purchased(active: true)
    }

    func restore() async throws -> Bool { false }
}

private final class DemoPetBackend: PetBackend {
    let currentUserID: UUID? = UUID()
    private var myName = ""
    private var pets: [Pet] = []
    private var tasks: [PetTask] = []
    private var occurrences: [Occurrence] = []

    init(seeded: Bool, freePlan: Bool) {
        if seeded { seedForScreenshots(freePlan: freePlan) }
    }

    /// Maya's dog Bruno, with Premium and two helpers (or on the Free plan, on her own).
    /// Today's tasks up to now are done, shared between the household; the rest are still to do.
    private func seedForScreenshots(freePlan: Bool) {
        myName = "Maya"
        hasPremium = !freePlan
        memberIDs = freePlan ? [] : [samID, ashaID]
        pets = [Pet(
            id: UUID(), ownerID: currentUserID!, name: "Bruno", species: .dog, breed: "Golden Retriever",
            birthDate: "2023-03-14", gender: .male, timezone: TimeZone.current.identifier
        )]
        let schedule: [(String, TaskCategory, Int, Int, String?)] = [
            ("Morning walk", .walk, 7, 30, nil),
            ("Breakfast", .food, 8, 0, "One cup of kibble, soaked."),
            ("Fresh water", .water, 9, 0, nil),
            ("Play in the park", .play, 16, 0, nil),
            ("Evening walk", .walk, 18, 30, nil),
            ("Dinner", .food, 19, 0, "One cup of kibble."),
            ("Joint supplement", .medicine, 21, 0, "One chew after dinner."),
        ]
        let now = TimeOfDay(date: .now)
        for (index, (title, category, hour, minute, instructions)) in schedule.enumerated() {
            let task = PetTask(
                id: UUID(), petID: pets[0].id, title: title, category: category,
                timeOfDay: TimeOfDay(hour: hour, minute: minute), weekdays: .everyDay,
                reminderEnabled: true, instructions: instructions
            )
            tasks.append(task)
            occurrences.append(occurrence(for: task, done: task.timeOfDay < now, by: household[index % household.count]))
            addHistory(for: task, index: index + 1)
        }
    }

    /// Everyone who can mark tasks done: you, then your helpers.
    private var household: [UUID] { [currentUserID!] + memberIDs }

    func fetchMyName() async throws -> String { myName }
    func saveMyName(_ name: String) async throws { myName = name }

    func fetchProfileNames() async throws -> [UUID: String] {
        var names = [samID: "Sam", ashaID: "Asha"]
        if let currentUserID { names[currentUserID] = myName }
        return names
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

    private var remindersEnabled = true

    func fetchRemindersEnabled(petID: UUID) async throws -> Bool { remindersEnabled }
    func setRemindersEnabled(_ enabled: Bool, petID: UUID) async throws { remindersEnabled = enabled }

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
            let person = household[(daysAgo + index) % household.count]
            occurrences.append(occurrence(for: task, daysAgo: daysAgo, done: !missed, by: person))
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

    func completeOccurrence(id: UUID, note: String?, photoPath: String?) async throws -> Occurrence {
        guard let index = occurrences.firstIndex(where: { $0.id == id }) else { throw NotSignedIn() }
        occurrences[index].status = .done
        occurrences[index].completedBy = currentUserID
        occurrences[index].completedAt = .now
        occurrences[index].note = note
        occurrences[index].photoPath = photoPath
        return occurrences[index]
    }

    func undoOccurrence(id: UUID) async throws -> Occurrence {
        guard let index = occurrences.firstIndex(where: { $0.id == id }) else { throw NotSignedIn() }
        occurrences[index].status = .pending
        occurrences[index].completedBy = nil
        occurrences[index].completedAt = nil
        occurrences[index].note = nil
        occurrences[index].photoPath = nil
        return occurrences[index]
    }

    // MARK: Premium and households. Starts on the Free plan; buying Premium in the demo
    // paywall unlocks it. Any 8-character code joins Asha's (Premium) household and its cat, Luna.

    private let samID = UUID()
    private let ashaID = UUID()
    private var memberIDs: [UUID] = []
    private var hasPremium = false

    func fetchMyEntitlement() async throws -> MyEntitlement? {
        hasPremium
            ? MyEntitlement(isPremium: true, productID: "demo.monthly", expiresAt: .now.addingTimeInterval(30 * 86_400))
            : nil
    }

    func syncPremium() async throws { hasPremium = true }
    private var invites: [Invite] = []
    private var memberships: [Membership] = []
    private var cloudPhotos: [String: Data] = [:]

    func petHasPremium(petID: UUID) async throws -> Bool {
        pets.first { $0.id == petID }?.ownerID == currentUserID ? hasPremium : true
    }
    func fetchInvites() async throws -> [Invite] { invites }

    func createInvite() async throws -> Invite {
        let code = String((0..<8).map { _ in "23456789ABCDEFGHJKLMNPQRSTUVWXYZ".randomElement()! })
        let invite = Invite(id: UUID(), code: code, expiresAt: .now.addingTimeInterval(7 * 86_400))
        invites.append(invite)
        return invite
    }

    func cancelInvite(id: UUID) async throws { invites.removeAll { $0.id == id } }

    func inviteDetails(code: String) async throws -> InvitePreview? {
        code.count == 8 ? InvitePreview(ownerName: "Asha", petName: "Luna", petSpecies: .cat) : nil
    }

    func acceptInvite(code: String) async throws -> UUID {
        let luna = Pet(id: UUID(), ownerID: ashaID, name: "Luna", species: .cat, timezone: TimeZone.current.identifier)
        pets.append(luna)
        memberships.append(Membership(ownerID: ashaID, ownerName: "Asha", petID: luna.id, petName: "Luna", active: true))
        return ashaID
    }

    func fetchMemberIDs() async throws -> [UUID] { memberIDs }
    func removeMember(_ memberID: UUID) async throws { memberIDs.removeAll { $0 == memberID } }
    func fetchMemberships() async throws -> [Membership] { memberships }

    func leaveHousehold(ownerID: UUID) async throws {
        memberships.removeAll { $0.ownerID == ownerID }
        pets.removeAll { $0.ownerID == ownerID }
    }

    func uploadPhoto(_ data: Data, path: String) async throws { cloudPhotos[path] = data }

    func downloadPhoto(path: String) async throws -> Data {
        guard let data = cloudPhotos[path] else { throw NotSignedIn() }
        return data
    }

    func deletePhoto(path: String) async throws { cloudPhotos[path] = nil }

    /// An occurrence of a task, built the way the server would send it: done by `person`,
    /// otherwise pending today or missed on a past day.
    private func occurrence(for task: PetTask, daysAgo: Int = 0, done: Bool = false, by person: UUID? = nil) -> Occurrence {
        let timeZone = pets.first?.timeZone ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let scheduled = calendar.date(bySettingHour: task.timeOfDay.hour, minute: task.timeOfDay.minute, second: 0, of: day) ?? day
        var json: [String: Any] = [
            "id": UUID().uuidString, "task_id": task.id.uuidString, "pet_id": task.petID.uuidString,
            "date": ServerDate.dayString(for: day, in: timeZone), "scheduled_at": scheduled.ISO8601Format(),
            "title": task.title, "category": task.category.rawValue,
            "status": done ? "done" : daysAgo == 0 ? "pending" : "missed",
            "task": ["instructions": task.instructions.map { $0 as Any } ?? NSNull()],
        ]
        if done, let completedBy = person ?? currentUserID {
            json["completed_by"] = completedBy.uuidString
            json["completed_at"] = scheduled.addingTimeInterval(8 * 60).ISO8601Format()
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Occurrence.self, from: data)
    }
}
#endif
