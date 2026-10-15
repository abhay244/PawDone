import Foundation
import Observation
import UIKit

/// The pet the user is looking at (their own, or one they help with), its schedule,
/// today's tasks and its household.
@Observable
final class PetStore {
    enum Phase: Equatable {
        case loading
        /// No pet yet, or the user is still in the first-run setup.
        case needsOnboarding
        case ready
        case failed(String)
    }

    /// Helpers per household, counting open invites.
    static let householdLimit = 2

    private(set) var phase: Phase = .loading
    private(set) var myName = ""
    /// Every pet the user can see: their own and ones they help with.
    private(set) var pets: [Pet] = []
    /// The pet being shown.
    private(set) var pet: Pet?
    private(set) var tasks: [PetTask] = []
    private(set) var today: [Occurrence] = []
    private(set) var names: [UUID: String] = [:]
    /// Whether this user gets reminders for the pet.
    private(set) var remindersEnabled = true
    /// Whether the pet's household has Premium: helpers and cloud photos.
    private(set) var hasPremium = false
    /// The user's own subscription, whichever pet is shown.
    private(set) var myEntitlement: MyEntitlement?
    /// Helpers in the user's own household (when showing their own pet).
    private(set) var memberIDs: [UUID] = []
    /// Open invites to the user's own household.
    private(set) var invites: [Invite] = []
    /// Households the user helps in, including paused ones.
    private(set) var memberships: [Membership] = []

    @ObservationIgnored let photos: ProofPhotoStore
    @ObservationIgnored private let backend: any PetBackend
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentDate: () -> Date

    private static let selectedPetKey = "selectedPetID"

    init(
        backend: any PetBackend,
        photos: ProofPhotoStore = ProofPhotoStore(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now }
    ) {
        self.backend = backend
        self.photos = photos
        self.defaults = defaults
        self.currentDate = now
    }

    var myUserID: UUID? { backend.currentUserID }

    /// Only the owner can change the pet and its schedule.
    var isOwner: Bool {
        guard let pet else { return false }
        return pet.ownerID == backend.currentUserID
    }

    var doneCount: Int { today.count { $0.status == .done } }

    var canInviteMore: Bool { memberIDs.count + invites.count < Self.householdLimit }

    /// Whether the user has their own active Premium subscription.
    var iHavePremium: Bool { myEntitlement?.isActive(at: currentDate()) ?? false }

    /// Households hidden because their owner's Premium ended.
    var pausedMemberships: [Membership] { memberships.filter { !$0.active } }

    /// Today's date in the pet's timezone, as stored in the database.
    var todayString: String {
        ServerDate.dayString(for: currentDate(), in: pet?.timeZone ?? .current)
    }

    /// A calendar in the pet's timezone, for reports.
    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = pet?.timeZone ?? .current
        return calendar
    }

    var now: Date { currentDate() }

    /// Tasks for a range of days (`yyyy-MM-dd`, inclusive), for reports.
    func occurrences(from: String, to: String) async throws -> [Occurrence] {
        guard let pet else { return [] }
        return try await backend.fetchOccurrences(petID: pet.id, from: from, to: to)
    }

    /// A time of day as the pet experiences it, e.g. "8:00 AM".
    func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: pet?.timeZone ?? .current))
    }

    func isOverdue(_ occurrence: Occurrence) -> Bool {
        occurrence.status == .pending && occurrence.scheduledAt < currentDate()
    }

    /// The owner's name for a pet the user helps with; nil for their own pet.
    func ownerName(of pet: Pet) -> String? {
        guard pet.ownerID != myUserID else { return nil }
        return memberships.first { $0.ownerID == pet.ownerID }?.ownerName ?? names[pet.ownerID] ?? "Someone"
    }

    func name(for userID: UUID?) -> String {
        guard let userID else { return "Someone" }
        if userID == myUserID { return "You" }
        return names[userID].flatMap { $0.isEmpty ? nil : $0 } ?? "Someone"
    }

    // MARK: Loading

    func load() async {
        do {
            myName = try await backend.fetchMyName()
            pets = try await backend.fetchPets()
            memberships = (try? await backend.fetchMemberships()) ?? []
            show(preferredPet())
            guard pet != nil else {
                phase = .needsOnboarding
                return
            }
            try await reloadPetData()
            await reloadPetSettings()
            phase = .ready
        } catch {
            _ = UserFacingError.message(for: error) // Logs the details.
            phase = .failed("Check your connection and try again.")
        }
    }

    /// Switches to another pet the user owns or helps with.
    func selectPet(_ newPet: Pet) async {
        guard newPet.id != pet?.id else { return }
        show(newPet)
        tasks = []
        today = []
        try? await reloadPetData()
        await reloadPetSettings()
    }

    /// Reloads today's tasks. Errors are ignored so a pull-to-refresh offline keeps what's shown.
    func refreshToday() async {
        guard let pet else { return }
        if let occurrences = try? await backend.fetchOccurrences(petID: pet.id, date: todayString) {
            today = occurrences
        }
    }

    /// The last pet shown, else the user's own, else the first they help with.
    private func preferredPet(ownedBy ownerID: UUID? = nil) -> Pet? {
        if let ownerID, let match = pets.first(where: { $0.ownerID == ownerID }) {
            return match
        }
        if let saved = defaults.string(forKey: Self.selectedPetKey),
           let match = pets.first(where: { $0.id.uuidString == saved }) {
            return match
        }
        return pets.first { $0.ownerID == backend.currentUserID } ?? pets.first
    }

    private func show(_ newPet: Pet?) {
        pet = newPet
        if let newPet {
            defaults.set(newPet.id.uuidString, forKey: Self.selectedPetKey)
        }
    }

    private func reloadPetData() async throws {
        guard let pet else { return }
        tasks = try await backend.fetchTasks(petID: pet.id)
        today = try await backend.fetchOccurrences(petID: pet.id, date: todayString)
        names = try await backend.fetchProfileNames()
    }

    /// Re-reads Premium after a purchase or restore.
    func refreshPremium() async {
        await reloadPetSettings()
    }

    /// Settings that can fall back to defaults if they fail to load.
    private func reloadPetSettings() async {
        myEntitlement = try? await backend.fetchMyEntitlement()
        guard let pet else { return }
        remindersEnabled = (try? await backend.fetchRemindersEnabled(petID: pet.id)) ?? true
        hasPremium = (try? await backend.petHasPremium(petID: pet.id)) ?? false
        if isOwner {
            memberIDs = (try? await backend.fetchMemberIDs()) ?? []
            invites = (try? await backend.fetchInvites()) ?? []
        } else {
            memberIDs = []
            invites = []
        }
    }

    // MARK: First-run setup

    func saveName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await backend.saveMyName(trimmed)
        myName = trimmed
        if let myUserID { names[myUserID] = trimmed }
    }

    func createPet(_ fields: PetFields) async throws {
        let newPet = try await backend.createPet(fields, timezone: TimeZone.current.identifier)
        pets.append(newPet)
        show(newPet)
    }

    /// Ends the first-run setup, optionally adding the chosen starter tasks.
    func finishOnboarding(addingTasks newTasks: [TaskFields]) async throws {
        try await backend.createTasks(newTasks)
        try await reloadPetData()
        await reloadPetSettings()
        phase = .ready
    }

    // MARK: Notifications

    func setRemindersEnabled(_ enabled: Bool) async throws {
        guard let pet else { return }
        remindersEnabled = enabled
        do {
            try await backend.setRemindersEnabled(enabled, petID: pet.id)
        } catch {
            remindersEnabled = !enabled
            throw error
        }
    }

    // MARK: Household (owner)

    func createInvite() async throws -> Invite {
        let invite = try await backend.createInvite()
        invites.append(invite)
        return invite
    }

    func cancelInvite(_ invite: Invite) async throws {
        try await backend.cancelInvite(id: invite.id)
        invites.removeAll { $0.id == invite.id }
    }

    func removeMember(_ memberID: UUID) async throws {
        try await backend.removeMember(memberID)
        memberIDs.removeAll { $0 == memberID }
    }

    // MARK: Joining and leaving (helper)

    /// Nil when the code can't be used.
    func inviteDetails(code: String) async throws -> InvitePreview? {
        try await backend.inviteDetails(code: InviteCode.normalize(code))
    }

    /// Joins a household and switches to its pet.
    func joinHousehold(code: String) async throws {
        let ownerID = try await backend.acceptInvite(code: InviteCode.normalize(code))
        pets = try await backend.fetchPets()
        memberships = (try? await backend.fetchMemberships()) ?? []
        show(preferredPet(ownedBy: ownerID))
        guard pet != nil else {
            // The owner hasn't added their pet yet.
            phase = .needsOnboarding
            return
        }
        try await reloadPetData()
        await reloadPetSettings()
        phase = .ready
    }

    func leaveHousehold(_ membership: Membership) async throws {
        try await backend.leaveHousehold(ownerID: membership.ownerID)
        await load()
    }

    // MARK: Pet and schedule (owner only)

    func updatePet(_ fields: PetFields) async throws {
        guard let pet else { return }
        let updated = try await backend.updatePet(id: pet.id, fields: fields)
        self.pet = updated
        if let index = pets.firstIndex(where: { $0.id == updated.id }) {
            pets[index] = updated
        }
    }

    /// Adds a task when `id` is nil, otherwise updates it.
    func saveTask(id: PetTask.ID?, fields: TaskFields) async throws {
        if let id {
            try await backend.updateTask(id: id, fields: fields)
        } else {
            try await backend.createTasks([fields])
        }
        try await reloadPetData()
    }

    func removeTask(_ task: PetTask) async throws {
        try await backend.archiveTask(id: task.id)
        try await reloadPetData()
    }

    // MARK: Marking tasks done

    /// Where an occurrence's photo lives in cloud storage: `<pet id>/<occurrence id>.jpg`.
    static func photoPath(for occurrence: Occurrence) -> String {
        "\(occurrence.petID.uuidString.lowercased())/\(occurrence.id.uuidString.lowercased()).jpg"
    }

    func complete(_ occurrence: Occurrence, note: String?, photo: UIImage?) async throws {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = photo.flatMap(ProofPhotoStore.jpegData(for:))

        // Premium households share photos through the cloud; the Free plan keeps them on this phone.
        var photoPath: String?
        if let data, hasPremium {
            let path = Self.photoPath(for: occurrence)
            do {
                try await backend.uploadPhoto(data, path: path)
                photoPath = path
            } catch {
                // Still mark the task; the photo stays on this phone.
                _ = UserFacingError.message(for: error)
            }
        }

        var updated = try await backend.completeOccurrence(
            id: occurrence.id,
            note: trimmedNote?.isEmpty == false ? trimmedNote : nil,
            photoPath: photoPath
        )
        updated.instructions = occurrence.instructions
        if let data {
            // The task is already marked; a failed photo save shouldn't undo that.
            try? photos.save(data, for: occurrence.id)
        }
        replace(updated)
    }

    func undo(_ occurrence: Occurrence) async throws {
        var updated = try await backend.undoOccurrence(id: occurrence.id)
        updated.instructions = occurrence.instructions
        photos.delete(for: occurrence.id)
        if let path = occurrence.photoPath {
            try? await backend.deletePhoto(path: path)
        }
        replace(updated)
    }

    func hasPhoto(_ occurrence: Occurrence) -> Bool {
        occurrence.photoPath != nil || photos.hasPhoto(for: occurrence.id)
    }

    /// The photo from this phone, or from the household's cloud storage (then kept on this phone).
    func photo(for occurrence: Occurrence) async -> UIImage? {
        if let local = photos.image(for: occurrence.id) {
            return local
        }
        guard let path = occurrence.photoPath,
              let data = try? await backend.downloadPhoto(path: path)
        else { return nil }
        try? photos.save(data, for: occurrence.id)
        return UIImage(data: data)
    }

    private func replace(_ occurrence: Occurrence) {
        if let index = today.firstIndex(where: { $0.id == occurrence.id }) {
            today[index] = occurrence
        }
    }
}
