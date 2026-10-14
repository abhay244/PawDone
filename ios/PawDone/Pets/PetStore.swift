import Foundation
import Observation
import UIKit

/// The signed-in user's pet, its schedule and today's tasks.
@Observable
final class PetStore {
    enum Phase: Equatable {
        case loading
        /// No pet yet, or the user is still in the first-run setup.
        case needsOnboarding
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var myName = ""
    private(set) var pet: Pet?
    private(set) var tasks: [PetTask] = []
    private(set) var today: [Occurrence] = []
    private(set) var names: [UUID: String] = [:]
    /// Whether this user gets reminders for the pet.
    private(set) var remindersEnabled = true

    @ObservationIgnored let photos: ProofPhotoStore
    @ObservationIgnored private let backend: any PetBackend
    @ObservationIgnored private let currentDate: () -> Date

    init(backend: any PetBackend, photos: ProofPhotoStore = ProofPhotoStore(), now: @escaping () -> Date = { .now }) {
        self.backend = backend
        self.photos = photos
        self.currentDate = now
    }

    var myUserID: UUID? { backend.currentUserID }

    /// Only the owner can change the pet and its schedule.
    var isOwner: Bool {
        guard let pet else { return false }
        return pet.ownerID == backend.currentUserID
    }

    var doneCount: Int { today.count { $0.status == .done } }

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

    func name(for userID: UUID?) -> String {
        guard let userID else { return "Someone" }
        if userID == myUserID { return "You" }
        return names[userID].flatMap { $0.isEmpty ? nil : $0 } ?? "Someone"
    }

    // MARK: Loading

    func load() async {
        do {
            myName = try await backend.fetchMyName()
            let pets = try await backend.fetchPets()
            // Prefer the user's own pet over one they help with.
            pet = pets.first { $0.ownerID == backend.currentUserID } ?? pets.first
            guard pet != nil else {
                phase = .needsOnboarding
                return
            }
            try await reloadPetData()
            if let pet {
                remindersEnabled = (try? await backend.fetchRemindersEnabled(petID: pet.id)) ?? true
            }
            phase = .ready
        } catch {
            _ = UserFacingError.message(for: error) // Logs the details.
            phase = .failed("Check your connection and try again.")
        }
    }

    /// Reloads today's tasks. Errors are ignored so a pull-to-refresh offline keeps what's shown.
    func refreshToday() async {
        guard let pet else { return }
        if let occurrences = try? await backend.fetchOccurrences(petID: pet.id, date: todayString) {
            today = occurrences
        }
    }

    private func reloadPetData() async throws {
        guard let pet else { return }
        tasks = try await backend.fetchTasks(petID: pet.id)
        today = try await backend.fetchOccurrences(petID: pet.id, date: todayString)
        names = try await backend.fetchProfileNames()
    }

    // MARK: First-run setup

    func saveName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await backend.saveMyName(trimmed)
        myName = trimmed
        if let myUserID { names[myUserID] = trimmed }
    }

    func createPet(_ fields: PetFields) async throws {
        pet = try await backend.createPet(fields, timezone: TimeZone.current.identifier)
    }

    /// Ends the first-run setup, optionally adding the chosen starter tasks.
    func finishOnboarding(addingTasks newTasks: [TaskFields]) async throws {
        try await backend.createTasks(newTasks)
        try await reloadPetData()
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

    // MARK: Pet and schedule (owner only)

    func updatePet(_ fields: PetFields) async throws {
        guard let pet else { return }
        self.pet = try await backend.updatePet(id: pet.id, fields: fields)
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

    func complete(_ occurrence: Occurrence, note: String?, photo: UIImage?) async throws {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = try await backend.completeOccurrence(
            id: occurrence.id,
            note: trimmedNote?.isEmpty == false ? trimmedNote : nil
        )
        updated.instructions = occurrence.instructions
        if let photo {
            // The task is already marked; a failed photo save shouldn't undo that.
            try? photos.save(photo, for: occurrence.id)
        }
        replace(updated)
    }

    func undo(_ occurrence: Occurrence) async throws {
        var updated = try await backend.undoOccurrence(id: occurrence.id)
        updated.instructions = occurrence.instructions
        photos.delete(for: occurrence.id)
        replace(updated)
    }

    private func replace(_ occurrence: Occurrence) {
        if let index = today.firstIndex(where: { $0.id == occurrence.id }) {
            today[index] = occurrence
        }
    }
}
