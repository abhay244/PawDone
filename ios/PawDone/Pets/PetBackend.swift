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

    /// Active (not archived) tasks.
    func fetchTasks(petID: UUID) async throws -> [PetTask]
    func createTasks(_ tasks: [TaskFields]) async throws
    func updateTask(id: UUID, fields: TaskFields) async throws
    func archiveTask(id: UUID) async throws

    /// The pet's tasks for one day (`yyyy-MM-dd`), in time order.
    func fetchOccurrences(petID: UUID, date: String) async throws -> [Occurrence]
    func completeOccurrence(id: UUID, note: String?) async throws -> Occurrence
    func undoOccurrence(id: UUID) async throws -> Occurrence
}
