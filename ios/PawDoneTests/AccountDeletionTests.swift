import Foundation
import Testing
@testable import PawDone

@MainActor
struct AccountDeletionTests {
    let backend = FakeSessionBackend()

    final class EraseCounter {
        var count = 0
    }

    func signedInStore(erase: EraseCounter) async -> SessionStore {
        backend.hasSession = true
        let store = SessionStore(backend: backend, deviceID: "device-1", eraseLocalData: { erase.count += 1 })
        await store.start()
        return store
    }

    @Test func deletingSignsOutAndErasesThisPhone() async throws {
        let erase = EraseCounter()
        let store = await signedInStore(erase: erase)

        try await store.deleteAccount()
        try await Task.sleep(for: .milliseconds(50)) // let the session-ended event arrive

        #expect(backend.deleteAccountCount == 1)
        #expect(erase.count == 1)
        #expect(store.state == .signedOut, "not mistaken for being signed in on another phone")
        #expect(store.notice != nil)
        #expect(backend.signOutCount == 1)
        #expect(!store.isWorking)
    }

    @Test func passesTheAppleCodeToTheServer() async throws {
        backend.signedInWithApple = true
        let store = await signedInStore(erase: EraseCounter())
        #expect(store.deletionNeedsAppleAuthorization)

        try await store.deleteAccount(appleAuthorizationCode: "c0de")

        #expect(backend.deletionAppleCodes == ["c0de"])
    }

    @Test func googleAccountsNeedNoAppleCode() async throws {
        let store = await signedInStore(erase: EraseCounter())
        #expect(!store.deletionNeedsAppleAuthorization)

        try await store.deleteAccount()

        #expect(backend.deletionAppleCodes == [nil])
    }

    @Test func failedDeletionKeepsEverything() async {
        let erase = EraseCounter()
        let store = await signedInStore(erase: erase)
        backend.deleteAccountError = FakeSessionBackend.Failure()

        await #expect(throws: FakeSessionBackend.Failure.self) {
            try await store.deleteAccount()
        }

        #expect(store.state == .signedIn)
        #expect(erase.count == 0)
        #expect(backend.signOutCount == 0)
        #expect(!store.isWorking)
    }

    @Test func signingInAgainClearsTheNotice() async throws {
        let store = await signedInStore(erase: EraseCounter())
        try await store.deleteAccount()

        await store.signInWithApple(idToken: "token", nonce: "nonce", fullName: nil)

        #expect(store.notice == nil)
        #expect(store.state == .signedIn)
    }

    @Test func deleteAllRemovesPhotos() throws {
        let photos = ProofPhotoStore(directory: .temporaryDirectory.appending(path: "EraseTests-\(UUID().uuidString)"))
        let id = UUID()
        try photos.save(Data([0xFF, 0xD8, 0xFF]), for: id)
        #expect(photos.hasPhoto(for: id))

        photos.deleteAll()

        #expect(!photos.hasPhoto(for: id))
    }
}
