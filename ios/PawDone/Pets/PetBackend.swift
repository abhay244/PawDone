import Foundation

/// What the pet screens need from the server. `SupabasePetBackend` is the real one;
/// tests use a fake.
protocol PetBackend: AnyObject {
    var currentUserID: UUID? { get }

    func fetchMyName() async throws -> String
    func saveMyName(_ name: String) async throws
    /// Names of everyone whose profile the user can see (themselves and their household).
    func fetchProfileNames() async throws -> [UUID: String]

    /// Pets the user owns or helps with.
    func fetchPets() async throws -> [Pet]
    func createPet(_ fields: PetFields, timezone: String) async throws -> Pet
    func updatePet(id: UUID, fields: PetFields) async throws -> Pet

    /// Whether the user gets reminders for this pet. On unless they turned it off.
    func fetchRemindersEnabled(petID: UUID) async throws -> Bool
    func setRemindersEnabled(_ enabled: Bool, petID: UUID) async throws

    /// Active (not archived) tasks.
    func fetchTasks(petID: UUID) async throws -> [PetTask]
    func createTasks(_ tasks: [TaskFields]) async throws
    func updateTask(id: UUID, fields: TaskFields) async throws
    func archiveTask(id: UUID) async throws

    /// The pet's tasks for one day (`yyyy-MM-dd`), in time order.
    func fetchOccurrences(petID: UUID, date: String) async throws -> [Occurrence]
    /// The pet's tasks for a range of days (`yyyy-MM-dd`, inclusive), in time order.
    func fetchOccurrences(petID: UUID, from: String, to: String) async throws -> [Occurrence]
    /// `photoPath` is a Storage path for Premium households; Free plans keep photos on the phone.
    func completeOccurrence(id: UUID, note: String?, photoPath: String?) async throws -> Occurrence
    func undoOccurrence(id: UUID) async throws -> Occurrence

    // MARK: Households

    /// Whether the pet's household has Premium (sharing and cloud photos).
    func petHasPremium(petID: UUID) async throws -> Bool
    /// Open invites to the user's own household.
    func fetchInvites() async throws -> [Invite]
    func createInvite() async throws -> Invite
    func cancelInvite(id: UUID) async throws
    /// Nil when the code can't be used.
    func inviteDetails(code: String) async throws -> InvitePreview?
    /// Joins the household and returns its owner.
    func acceptInvite(code: String) async throws -> UUID
    /// Helpers in the user's own household.
    func fetchMemberIDs() async throws -> [UUID]
    func removeMember(_ memberID: UUID) async throws
    /// Households the user helps in.
    func fetchMemberships() async throws -> [Membership]
    func leaveHousehold(ownerID: UUID) async throws

    // MARK: Photo proof in the cloud (Premium)

    func uploadPhoto(_ data: Data, path: String) async throws
    func downloadPhoto(path: String) async throws -> Data
    func deletePhoto(path: String) async throws
}
