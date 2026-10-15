import Foundation
import Supabase

final class SupabasePetBackend: PetBackend {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func fetchMyName() async throws -> String {
        guard let userID = currentUserID else { return "" }
        let row: ProfileRow = try await client.from("profiles")
            .select("id,name")
            .eq("id", value: userID.uuidString)
            .single()
            .execute()
            .value
        return row.name
    }

    func saveMyName(_ name: String) async throws {
        guard let userID = currentUserID else { return }
        try await client.from("profiles")
            .update(["name": name], returning: .minimal)
            .eq("id", value: userID.uuidString)
            .execute()
    }

    func fetchProfileNames() async throws -> [UUID: String] {
        let rows: [ProfileRow] = try await client.from("profiles").select("id,name").execute().value
        return Dictionary(rows.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    func fetchPets() async throws -> [Pet] {
        try await client.from("pets").select().order("created_at").execute().value
    }

    func createPet(_ fields: PetFields, timezone: String) async throws -> Pet {
        guard let userID = currentUserID else { throw NotSignedIn() }
        return try await client.from("pets")
            .insert(NewPet(ownerID: userID, timezone: timezone, fields: fields))
            .select()
            .single()
            .execute()
            .value
    }

    func updatePet(id: UUID, fields: PetFields) async throws -> Pet {
        try await client.from("pets")
            .update(fields)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func fetchRemindersEnabled(petID: UUID) async throws -> Bool {
        guard let userID = currentUserID else { return true }
        let rows: [NotificationPreference] = try await client.from("notification_prefs")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("pet_id", value: petID.uuidString)
            .execute()
            .value
        return rows.first?.remindersEnabled ?? true
    }

    func setRemindersEnabled(_ enabled: Bool, petID: UUID) async throws {
        guard let userID = currentUserID else { throw NotSignedIn() }
        try await client.from("notification_prefs")
            .upsert(
                NotificationPreference(userID: userID, petID: petID, remindersEnabled: enabled),
                onConflict: "user_id,pet_id",
                returning: .minimal
            )
            .execute()
    }

    func fetchTasks(petID: UUID) async throws -> [PetTask] {
        try await client.from("tasks")
            .select()
            .eq("pet_id", value: petID.uuidString)
            .is("archived_at", value: nil)
            .order("time_of_day")
            .execute()
            .value
    }

    func createTasks(_ tasks: [TaskFields]) async throws {
        guard !tasks.isEmpty else { return }
        try await client.from("tasks").insert(tasks, returning: .minimal).execute()
    }

    func updateTask(id: UUID, fields: TaskFields) async throws {
        try await client.from("tasks")
            .update(fields, returning: .minimal)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func archiveTask(id: UUID) async throws {
        try await client.from("tasks")
            .update(["archived_at": Date.now.ISO8601Format()], returning: .minimal)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func fetchOccurrences(petID: UUID, date: String) async throws -> [Occurrence] {
        try await client.from("task_occurrences")
            .select("*,task:tasks(instructions)")
            .eq("pet_id", value: petID.uuidString)
            .eq("date", value: date)
            .order("scheduled_at")
            .execute()
            .value
    }

    func fetchOccurrences(petID: UUID, from: String, to: String) async throws -> [Occurrence] {
        try await client.from("task_occurrences")
            .select("*,task:tasks(instructions)")
            .eq("pet_id", value: petID.uuidString)
            .gte("date", value: from)
            .lte("date", value: to)
            .order("scheduled_at")
            .execute()
            .value
    }

    func completeOccurrence(id: UUID, note: String?, photoPath: String?) async throws -> Occurrence {
        try await client
            .rpc("complete_occurrence", params: CompleteParams(occurrenceID: id, note: note, photoPath: photoPath))
            .execute()
            .value
    }

    func undoOccurrence(id: UUID) async throws -> Occurrence {
        try await client
            .rpc("undo_occurrence", params: ["p_occurrence_id": id.uuidString])
            .execute()
            .value
    }

    // MARK: Households

    func petHasPremium(petID: UUID) async throws -> Bool {
        try await client.rpc("pet_has_premium", params: ["p_pet_id": petID.uuidString]).execute().value
    }

    func fetchInvites() async throws -> [Invite] {
        guard let userID = currentUserID else { return [] }
        return try await client.from("invites")
            .select("id,token,expires_at")
            .eq("owner_id", value: userID.uuidString)
            .is("accepted_at", value: nil)
            .gt("expires_at", value: Date.now.ISO8601Format())
            .order("created_at")
            .execute()
            .value
    }

    func createInvite() async throws -> Invite {
        try await client.rpc("create_invite").execute().value
    }

    func cancelInvite(id: UUID) async throws {
        try await client.from("invites").delete(returning: .minimal).eq("id", value: id.uuidString).execute()
    }

    func inviteDetails(code: String) async throws -> InvitePreview? {
        let previews: [InvitePreview] = try await client
            .rpc("invite_details", params: ["p_code": code])
            .execute()
            .value
        return previews.first
    }

    func acceptInvite(code: String) async throws -> UUID {
        try await client.rpc("accept_invite", params: ["p_token": code]).execute().value
    }

    func fetchMemberIDs() async throws -> [UUID] {
        guard let userID = currentUserID else { return [] }
        let rows: [MemberRow] = try await client.from("household_members")
            .select("member_id")
            .eq("owner_id", value: userID.uuidString)
            .order("joined_at")
            .execute()
            .value
        return rows.map(\.memberID)
    }

    func removeMember(_ memberID: UUID) async throws {
        guard let userID = currentUserID else { throw NotSignedIn() }
        try await client.from("household_members")
            .delete(returning: .minimal)
            .eq("owner_id", value: userID.uuidString)
            .eq("member_id", value: memberID.uuidString)
            .execute()
    }

    func fetchMemberships() async throws -> [Membership] {
        try await client.rpc("my_households").execute().value
    }

    func leaveHousehold(ownerID: UUID) async throws {
        guard let userID = currentUserID else { throw NotSignedIn() }
        try await client.from("household_members")
            .delete(returning: .minimal)
            .eq("owner_id", value: ownerID.uuidString)
            .eq("member_id", value: userID.uuidString)
            .execute()
    }

    // MARK: Photo proof in the cloud

    private var photos: StorageFileApi { client.storage.from("proof-photos") }

    func uploadPhoto(_ data: Data, path: String) async throws {
        _ = try await photos.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    func downloadPhoto(path: String) async throws -> Data {
        try await photos.download(path: path)
    }

    func deletePhoto(path: String) async throws {
        _ = try await photos.remove(paths: [path])
    }
}

nonisolated private struct ProfileRow: Decodable {
    let id: UUID
    let name: String
}

nonisolated private struct NewPet: Encodable {
    let ownerID: UUID
    let name: String
    let species: PetSpecies
    let breed: String?
    let birthDate: String?
    let gender: PetGender?
    let timezone: String

    init(ownerID: UUID, timezone: String, fields: PetFields) {
        self.ownerID = ownerID
        self.timezone = timezone
        name = fields.name
        species = fields.species
        breed = fields.breed
        birthDate = fields.birthDate
        gender = fields.gender
    }

    enum CodingKeys: String, CodingKey {
        case name, species, breed, gender, timezone
        case ownerID = "owner_id"
        case birthDate = "birth_date"
    }
}

nonisolated private struct NotificationPreference: Codable {
    let userID: UUID
    let petID: UUID
    let remindersEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case petID = "pet_id"
        case remindersEnabled = "reminders_enabled"
    }
}

// Nil values are left out, so the function's defaults (null) apply.
nonisolated private struct CompleteParams: Encodable {
    let occurrenceID: UUID
    let note: String?
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case occurrenceID = "p_occurrence_id"
        case note = "p_note"
        case photoPath = "p_photo_path"
    }
}

nonisolated private struct MemberRow: Decodable {
    let memberID: UUID

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
    }
}

nonisolated struct NotSignedIn: LocalizedError {
    var errorDescription: String? { "You're signed out. Sign in again to continue." }
}
