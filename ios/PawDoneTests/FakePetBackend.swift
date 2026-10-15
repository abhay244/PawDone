import Foundation
@testable import PawDone

final class FakePetBackend: PetBackend {
    struct Failure: Error {}

    var currentUserID: UUID? = UUID()
    var myName = ""
    var pets: [Pet] = []
    var tasks: [PetTask] = []
    var occurrences: [Occurrence] = []
    var profileNames: [UUID: String] = [:]
    var failNextCall = false

    private(set) var createdTasks: [TaskFields] = []
    private(set) var archivedTaskIDs: [UUID] = []
    private(set) var requestedDates: [String] = []
    private(set) var completedNotes: [String?] = []

    private func checkFailure() throws {
        if failNextCall {
            failNextCall = false
            throw Failure()
        }
    }

    func fetchMyName() async throws -> String {
        try checkFailure()
        return myName
    }

    func saveMyName(_ name: String) async throws {
        try checkFailure()
        myName = name
    }

    func fetchProfileNames() async throws -> [UUID: String] {
        profileNames
    }

    func fetchPets() async throws -> [Pet] {
        try checkFailure()
        return pets
    }

    func createPet(_ fields: PetFields, timezone: String) async throws -> Pet {
        try checkFailure()
        let pet = Pet(
            id: UUID(), ownerID: currentUserID!, name: fields.name, species: fields.species,
            breed: fields.breed, birthDate: fields.birthDate, gender: fields.gender, timezone: timezone
        )
        pets.append(pet)
        return pet
    }

    func updatePet(id: UUID, fields: PetFields) async throws -> Pet {
        let index = pets.firstIndex { $0.id == id }!
        pets[index].name = fields.name
        pets[index].species = fields.species
        return pets[index]
    }

    var remindersEnabled: [UUID: Bool] = [:]

    func fetchRemindersEnabled(petID: UUID) async throws -> Bool {
        remindersEnabled[petID] ?? true
    }

    func setRemindersEnabled(_ enabled: Bool, petID: UUID) async throws {
        try checkFailure()
        remindersEnabled[petID] = enabled
    }

    func fetchTasks(petID: UUID) async throws -> [PetTask] {
        tasks.filter { $0.petID == petID }
    }

    func createTasks(_ newTasks: [TaskFields]) async throws {
        try checkFailure()
        createdTasks += newTasks
        tasks += newTasks.map {
            PetTask(
                id: UUID(), petID: $0.petID, title: $0.title, category: $0.category, timeOfDay: $0.timeOfDay,
                weekdays: $0.weekdays, reminderEnabled: $0.reminderEnabled, instructions: $0.instructions
            )
        }
    }

    func updateTask(id: UUID, fields: TaskFields) async throws {
        let index = tasks.firstIndex { $0.id == id }!
        tasks[index].title = fields.title
        tasks[index].timeOfDay = fields.timeOfDay
    }

    func archiveTask(id: UUID) async throws {
        archivedTaskIDs.append(id)
        tasks.removeAll { $0.id == id }
    }

    func fetchOccurrences(petID: UUID, date: String) async throws -> [Occurrence] {
        requestedDates.append(date)
        return occurrences.filter { $0.petID == petID && $0.date == date }
    }

    private(set) var requestedRanges: [ClosedRange<String>] = []

    func fetchOccurrences(petID: UUID, from: String, to: String) async throws -> [Occurrence] {
        try checkFailure()
        requestedRanges.append(from...to)
        return occurrences.filter { $0.petID == petID && (from...to).contains($0.date) }
    }

    private(set) var completedPhotoPaths: [String?] = []

    func completeOccurrence(id: UUID, note: String?, photoPath: String?) async throws -> Occurrence {
        try checkFailure()
        completedNotes.append(note)
        completedPhotoPaths.append(photoPath)
        let index = occurrences.firstIndex { $0.id == id }!
        occurrences[index].status = .done
        occurrences[index].completedBy = currentUserID
        occurrences[index].completedAt = .now
        occurrences[index].note = note
        occurrences[index].photoPath = photoPath
        var returned = occurrences[index]
        returned.instructions = nil // The RPC doesn't include the task's instructions.
        return returned
    }

    func undoOccurrence(id: UUID) async throws -> Occurrence {
        let index = occurrences.firstIndex { $0.id == id }!
        occurrences[index].status = .pending
        occurrences[index].completedBy = nil
        occurrences[index].completedAt = nil
        occurrences[index].note = nil
        occurrences[index].photoPath = nil
        return occurrences[index]
    }

    // MARK: Premium

    var myEntitlement: MyEntitlement?
    private(set) var syncCount = 0

    func fetchMyEntitlement() async throws -> MyEntitlement? { myEntitlement }

    func syncPremium() async throws {
        syncCount += 1
    }

    // MARK: Households

    var premiumPetIDs: Set<UUID> = []
    var invites: [Invite] = []
    var invitePreviews: [String: InvitePreview] = [:]
    /// Code → the pet that joining makes visible.
    var invitePets: [String: Pet] = [:]
    var memberIDs: [UUID] = []
    var memberships: [Membership] = []
    private(set) var acceptedCodes: [String] = []
    private(set) var leftOwnerIDs: [UUID] = []

    func petHasPremium(petID: UUID) async throws -> Bool {
        premiumPetIDs.contains(petID)
    }

    func fetchInvites() async throws -> [Invite] { invites }

    func createInvite() async throws -> Invite {
        try checkFailure()
        let invite = Invite(id: UUID(), code: "K7P2QX9M", expiresAt: .now.addingTimeInterval(7 * 86_400))
        invites.append(invite)
        return invite
    }

    func cancelInvite(id: UUID) async throws {
        invites.removeAll { $0.id == id }
    }

    func inviteDetails(code: String) async throws -> InvitePreview? {
        invitePreviews[code]
    }

    func acceptInvite(code: String) async throws -> UUID {
        try checkFailure()
        acceptedCodes.append(code)
        guard let pet = invitePets[code] else { throw Failure() }
        pets.append(pet)
        memberships.append(Membership(ownerID: pet.ownerID, ownerName: "Asha", petID: pet.id, petName: pet.name, active: true))
        return pet.ownerID
    }

    func fetchMemberIDs() async throws -> [UUID] { memberIDs }

    func removeMember(_ memberID: UUID) async throws {
        memberIDs.removeAll { $0 == memberID }
    }

    func fetchMemberships() async throws -> [Membership] { memberships }

    func leaveHousehold(ownerID: UUID) async throws {
        leftOwnerIDs.append(ownerID)
        memberships.removeAll { $0.ownerID == ownerID }
        pets.removeAll { $0.ownerID == ownerID }
    }

    // MARK: Cloud photos

    var cloudPhotos: [String: Data] = [:]
    var failUploads = false

    func uploadPhoto(_ data: Data, path: String) async throws {
        if failUploads { throw Failure() }
        cloudPhotos[path] = data
    }

    func downloadPhoto(path: String) async throws -> Data {
        guard let data = cloudPhotos[path] else { throw Failure() }
        return data
    }

    func deletePhoto(path: String) async throws {
        cloudPhotos[path] = nil
    }
}

// MARK: - Test data

extension Pet {
    static func make(owner: UUID, timezone: String = "Asia/Kolkata") -> Pet {
        Pet(id: UUID(), ownerID: owner, name: "Bruno", species: .dog, timezone: timezone)
    }
}

extension Occurrence {
    /// Builds an occurrence the same way the app receives one: from server JSON.
    static func make(petID: UUID, date: String, scheduledAt: String, title: String = "Dinner", instructions: String? = nil) -> Occurrence {
        var json: [String: Any] = [
            "id": UUID().uuidString, "task_id": UUID().uuidString, "pet_id": petID.uuidString,
            "date": date, "scheduled_at": scheduledAt, "title": title, "category": "food", "status": "pending",
        ]
        if let instructions { json["task"] = ["instructions": instructions] }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Occurrence.self, from: data)
    }
}
