import Foundation
import Testing
import UIKit
@testable import PawDone

struct InviteCodeTests {
    @Test func normalizesWhatPeopleType() {
        #expect(InviteCode.normalize(" k7p2-qx9m ") == "K7P2QX9M")
        #expect(InviteCode.normalize("K7P2 QX9M") == "K7P2QX9M")
    }

    @Test func displaysInTwoHalves() {
        #expect(InviteCode.display("k7p2qx9m") == "K7P2 QX9M")
        #expect(InviteCode.display("ABC") == "ABC")
    }

    @Test func decodesInviteRow() throws {
        let json = """
        {"id": "6f1c1d4e-3a6b-4c8e-9a51-1d2f3e4a5b6c", "owner_id": "9a8b7c6d-5e4f-4a3b-2c1d-0e9f8a7b6c5d",
         "token": "K7P2QX9M", "expires_at": "2026-10-22T10:00:00.123456+00:00",
         "accepted_by": null, "accepted_at": null, "created_at": "2026-10-15T10:00:00+00:00"}
        """
        let invite = try JSONDecoder().decode(Invite.self, from: Data(json.utf8))
        #expect(invite.code == "K7P2QX9M")
        #expect(invite.expiresAt.ISO8601Format() == "2026-10-22T10:00:00Z")
    }

    @Test func decodesMembershipAndPreview() throws {
        let membership = try JSONDecoder().decode(Membership.self, from: Data("""
        {"owner_id": "9a8b7c6d-5e4f-4a3b-2c1d-0e9f8a7b6c5d", "owner_name": "Asha",
         "pet_id": null, "pet_name": null, "active": false}
        """.utf8))
        #expect(membership.ownerName == "Asha")
        #expect(!membership.active)

        let preview = try JSONDecoder().decode(InvitePreview.self, from: Data("""
        {"owner_name": "Asha", "pet_name": "Bruno", "pet_species": "dog"}
        """.utf8))
        #expect(preview.petSpecies == .dog)
    }
}

@MainActor
struct HouseholdTests {
    let backend = FakePetBackend()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let photos = ProofPhotoStore(directory: .temporaryDirectory.appending(path: "HouseholdTests-\(UUID().uuidString)"))

    func makeStore() -> PetStore {
        PetStore(backend: backend, photos: photos, defaults: defaults)
    }

    // MARK: Pets the user helps with

    @Test func remembersTheChosenPet() async {
        let mine = Pet.make(owner: backend.currentUserID!)
        let theirs = Pet.make(owner: UUID())
        backend.pets = [mine, theirs]
        backend.memberships = [Membership(ownerID: theirs.ownerID, ownerName: "Asha", petID: theirs.id, petName: "Bruno", active: true)]

        let store = makeStore()
        await store.load()
        #expect(store.pet?.id == mine.id, "own pet first")

        await store.selectPet(theirs)
        #expect(!store.isOwner)
        #expect(store.ownerName(of: theirs) == "Asha")

        let reopened = makeStore()
        await reopened.load()
        #expect(reopened.pet?.id == theirs.id, "remembers the last pet shown")
    }

    @Test func joiningSwitchesToTheirPet() async throws {
        let theirs = Pet.make(owner: UUID())
        backend.invitePets["K7P2QX9M"] = theirs
        let store = makeStore()
        await store.load()
        #expect(store.phase == .needsOnboarding)

        try await store.joinHousehold(code: "k7p2 qx9m")

        #expect(backend.acceptedCodes == ["K7P2QX9M"], "sends the normalized code")
        #expect(store.phase == .ready)
        #expect(store.pet?.id == theirs.id)
        #expect(!store.isOwner)
    }

    @Test func leavingReloads() async throws {
        let theirs = Pet.make(owner: UUID())
        backend.pets = [theirs]
        let membership = Membership(ownerID: theirs.ownerID, ownerName: "Asha", petID: theirs.id, petName: "Bruno", active: true)
        backend.memberships = [membership]
        let store = makeStore()
        await store.load()

        try await store.leaveHousehold(membership)

        #expect(backend.leftOwnerIDs == [theirs.ownerID])
        #expect(store.phase == .needsOnboarding)
    }

    @Test func pausedHouseholdsAreListed() async {
        backend.memberships = [Membership(ownerID: UUID(), ownerName: "Asha", petID: nil, petName: "Bruno", active: false)]
        let store = makeStore()
        await store.load()

        #expect(store.pausedMemberships.map(\.petName) == ["Bruno"])
    }

    // MARK: Owner's household

    @Test func invitesUpToTheLimit() async throws {
        let mine = Pet.make(owner: backend.currentUserID!)
        backend.pets = [mine]
        backend.premiumPetIDs = [mine.id]
        backend.memberIDs = [UUID()]
        let store = makeStore()
        await store.load()
        #expect(store.hasPremium)
        #expect(store.canInviteMore)

        let invite = try await store.createInvite()
        #expect(store.invites == [invite])
        #expect(!store.canInviteMore, "one helper plus one open invite fills the household")

        try await store.cancelInvite(invite)
        #expect(store.invites.isEmpty)
        #expect(store.canInviteMore)
    }

    @Test func removingAHelper() async throws {
        let helper = UUID()
        backend.pets = [Pet.make(owner: backend.currentUserID!)]
        backend.memberIDs = [helper]
        let store = makeStore()
        await store.load()

        try await store.removeMember(helper)

        #expect(store.memberIDs.isEmpty)
        #expect(backend.memberIDs.isEmpty)
    }

    // MARK: Photos in the cloud

    func loadedStore(premium: Bool) async throws -> (PetStore, Occurrence) {
        let pet = Pet.make(owner: backend.currentUserID!, timezone: TimeZone.current.identifier)
        backend.pets = [pet]
        if premium { backend.premiumPetIDs = [pet.id] }
        let today = ServerDate.dayString(for: .now, in: .current)
        backend.occurrences = [.make(petID: pet.id, date: today, scheduledAt: Date.now.ISO8601Format())]
        let store = makeStore()
        await store.load()
        return (store, try #require(store.today.first))
    }

    @Test func premiumPhotosGoToTheCloud() async throws {
        let (store, occurrence) = try await loadedStore(premium: true)
        try await store.complete(occurrence, note: nil, photo: Self.photo())

        let path = PetStore.photoPath(for: occurrence)
        #expect(path == "\(occurrence.petID.uuidString.lowercased())/\(occurrence.id.uuidString.lowercased()).jpg")
        #expect(backend.cloudPhotos[path] != nil)
        #expect(backend.completedPhotoPaths == [path])
        #expect(store.photos.hasPhoto(for: occurrence.id), "also kept on this phone")
    }

    @Test func freePhotosStayOnThePhone() async throws {
        let (store, occurrence) = try await loadedStore(premium: false)
        try await store.complete(occurrence, note: nil, photo: Self.photo())

        #expect(backend.cloudPhotos.isEmpty)
        #expect(backend.completedPhotoPaths == [nil])
        #expect(store.photos.hasPhoto(for: occurrence.id))
    }

    @Test func failedUploadStillMarksDone() async throws {
        let (store, occurrence) = try await loadedStore(premium: true)
        backend.failUploads = true
        try await store.complete(occurrence, note: nil, photo: Self.photo())

        #expect(store.today.first?.status == .done)
        #expect(backend.completedPhotoPaths == [nil])
    }

    @Test func undoDeletesTheCloudPhoto() async throws {
        let (store, occurrence) = try await loadedStore(premium: true)
        try await store.complete(occurrence, note: nil, photo: Self.photo())
        try await store.undo(try #require(store.today.first))

        #expect(backend.cloudPhotos.isEmpty)
    }

    @Test func helperDownloadsAndKeepsAPhoto() async throws {
        let (store, occurrence) = try await loadedStore(premium: true)
        let path = PetStore.photoPath(for: occurrence)
        backend.cloudPhotos[path] = ProofPhotoStore.jpegData(for: Self.photo())
        var uploadedByOthers = occurrence
        uploadedByOthers.photoPath = path

        #expect(store.hasPhoto(uploadedByOthers))
        let image = await store.photo(for: uploadedByOthers)

        #expect(image != nil)
        #expect(store.photos.hasPhoto(for: occurrence.id), "cached for next time")
    }

    private static func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }
}
