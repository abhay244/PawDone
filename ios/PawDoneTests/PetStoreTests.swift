import Foundation
import Testing
import UIKit
@testable import PawDone

@MainActor
struct PetStoreTests {
    let backend = FakePetBackend()
    let photos = ProofPhotoStore(directory: .temporaryDirectory.appending(path: "PetStoreTests-\(UUID().uuidString)"))

    /// 20:00 UTC on 13 Oct is already 14 Oct in India (UTC+5:30).
    let now = ServerDate.parse("2026-10-13T20:00:00Z")!

    func makeStore() -> PetStore {
        let now = now
        return PetStore(backend: backend, photos: photos, now: { now })
    }

    // MARK: Loading

    @Test func withoutPetNeedsOnboarding() async {
        let store = makeStore()
        await store.load()
        #expect(store.phase == .needsOnboarding)
    }

    @Test func loadsTodayInThePetsTimezone() async {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        backend.occurrences = [
            .make(petID: pet.id, date: "2026-10-14", scheduledAt: "2026-10-14T13:30:00+00:00"),
            .make(petID: pet.id, date: "2026-10-13", scheduledAt: "2026-10-13T13:30:00+00:00"),
        ]
        let store = makeStore()
        await store.load()

        #expect(store.phase == .ready)
        #expect(backend.requestedDates == ["2026-10-14"])
        #expect(store.today.count == 1)
        #expect(store.isOwner)
    }

    @Test func prefersOwnPetOverOneTheyHelpWith() async {
        let someoneElses = Pet.make(owner: UUID())
        let mine = Pet.make(owner: backend.currentUserID!)
        backend.pets = [someoneElses, mine]
        let store = makeStore()
        await store.load()

        #expect(store.pet?.id == mine.id)
    }

    @Test func helperIsNotOwner() async {
        backend.pets = [.make(owner: UUID())]
        let store = makeStore()
        await store.load()

        #expect(store.phase == .ready)
        #expect(!store.isOwner)
    }

    @Test func loadFailureShowsRetry() async {
        backend.failNextCall = true
        let store = makeStore()
        await store.load()

        guard case .failed = store.phase else {
            Issue.record("Expected failed, got \(store.phase)")
            return
        }
    }

    // MARK: First-run setup

    @Test func onboardingCreatesPetAndStarterTasks() async throws {
        let store = makeStore()
        await store.load()
        try await store.saveName("  Asha ")
        try await store.createPet(PetFields(name: "Bruno", species: .dog))
        #expect(store.phase == .needsOnboarding)

        let petID = try #require(store.pet?.id)
        try await store.finishOnboarding(addingTasks: [
            TaskFields(petID: petID, title: "Morning food", category: .food, timeOfDay: TimeOfDay(hour: 8, minute: 0)),
        ])

        #expect(store.phase == .ready)
        #expect(store.myName == "Asha")
        #expect(store.tasks.map(\.title) == ["Morning food"])
    }

    // MARK: Marking done

    @Test func completingSavesNoteAndPhoto() async throws {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        backend.occurrences = [
            .make(petID: pet.id, date: "2026-10-14", scheduledAt: "2026-10-14T13:30:00+00:00", instructions: "1 cup"),
        ]
        let store = makeStore()
        await store.load()
        let occurrence = try #require(store.today.first)

        try await store.complete(occurrence, note: "  ate it all  ", photo: Self.photo())

        let updated = try #require(store.today.first)
        #expect(updated.status == .done)
        #expect(backend.completedNotes == ["ate it all"])
        #expect(updated.instructions == "1 cup", "keeps the task's instructions")
        #expect(store.photos.hasPhoto(for: occurrence.id))
        #expect(store.doneCount == 1)
    }

    @Test func blankNoteIsSentAsNil() async throws {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        backend.occurrences = [.make(petID: pet.id, date: "2026-10-14", scheduledAt: "2026-10-14T13:30:00+00:00")]
        let store = makeStore()
        await store.load()

        try await store.complete(try #require(store.today.first), note: "   ", photo: nil)

        #expect(backend.completedNotes == [nil])
    }

    @Test func undoDeletesPhoto() async throws {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        backend.occurrences = [.make(petID: pet.id, date: "2026-10-14", scheduledAt: "2026-10-14T13:30:00+00:00")]
        let store = makeStore()
        await store.load()
        try await store.complete(try #require(store.today.first), note: nil, photo: Self.photo())

        try await store.undo(try #require(store.today.first))

        let occurrence = try #require(store.today.first)
        #expect(occurrence.status == .pending)
        #expect(!store.photos.hasPhoto(for: occurrence.id))
    }

    @Test func overdueOnlyWhenPendingAndPastDue() async throws {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        backend.occurrences = [
            .make(petID: pet.id, date: "2026-10-14", scheduledAt: "2026-10-13T19:00:00+00:00", title: "Past"),
            .make(petID: pet.id, date: "2026-10-14", scheduledAt: "2026-10-13T21:00:00+00:00", title: "Later"),
        ]
        let store = makeStore()
        await store.load()

        #expect(store.isOverdue(try #require(store.today.first { $0.title == "Past" })))
        #expect(!store.isOverdue(try #require(store.today.first { $0.title == "Later" })))
    }

    // MARK: Schedule

    @Test func removingTaskArchivesIt() async throws {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        let store = makeStore()
        await store.load()
        try await store.saveTask(id: nil, fields: TaskFields(petID: pet.id, title: "Walk", category: .walk, timeOfDay: TimeOfDay(hour: 7, minute: 30)))
        let task = try #require(store.tasks.first)

        try await store.removeTask(task)

        #expect(backend.archivedTaskIDs == [task.id])
        #expect(store.tasks.isEmpty)
    }

    // MARK: Names

    @Test func namesShowYouForSelfAndFallBackForUnknown() async {
        let helper = UUID()
        backend.pets = [.make(owner: backend.currentUserID!)]
        backend.profileNames = [helper: "Sam"]
        let store = makeStore()
        await store.load()

        #expect(store.name(for: backend.currentUserID) == "You")
        #expect(store.name(for: helper) == "Sam")
        #expect(store.name(for: UUID()) == "Someone")
    }

    private static func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }
}
