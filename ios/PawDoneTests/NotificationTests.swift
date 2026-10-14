import Foundation
import Testing
@testable import PawDone

@MainActor
struct PushTokenTests {
    let backend = FakeSessionBackend()

    func signedInStore() async -> SessionStore {
        backend.hasSession = true
        let store = SessionStore(backend: backend, deviceID: "device-1", pushEnvironment: "sandbox")
        await store.start()
        return store
    }

    @Test func sendsTokenWhenSignedIn() async {
        let store = await signedInStore()
        await store.updatePushToken("abc123")

        #expect(backend.pushTokens.map(\.token) == ["abc123"])
        #expect(backend.pushTokens.map(\.environment) == ["sandbox"])
    }

    @Test func ignoresTokenWhenSignedOut() async {
        let store = SessionStore(backend: backend, deviceID: "device-1")
        await store.start()
        await store.updatePushToken("abc123")

        #expect(backend.pushTokens.isEmpty)
    }

    @Test func signingOutClearsTokenFirst() async {
        let store = await signedInStore()
        await store.signOut()

        #expect(backend.pushTokens.count == 1)
        #expect(backend.pushTokens.first?.token == nil)
        #expect(backend.pushTokens.first?.signedIn == true, "cleared while the session can still reach the server")
        #expect(store.state == .signedOut)
    }
}

@MainActor
struct ReminderPreferenceTests {
    let backend = FakePetBackend()

    func loadedStore() async -> (PetStore, Pet) {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        let store = PetStore(backend: backend)
        await store.load()
        return (store, pet)
    }

    @Test func remindersAreOnByDefault() async {
        let (store, _) = await loadedStore()
        #expect(store.remindersEnabled)
    }

    @Test func loadsSavedPreference() async {
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        backend.remindersEnabled[pet.id] = false
        let store = PetStore(backend: backend)
        await store.load()

        #expect(!store.remindersEnabled)
    }

    @Test func turningOffSaves() async throws {
        let (store, pet) = await loadedStore()
        try await store.setRemindersEnabled(false)

        #expect(!store.remindersEnabled)
        #expect(backend.remindersEnabled[pet.id] == false)
    }

    @Test func failedSaveRevertsTheSwitch() async {
        let (store, _) = await loadedStore()
        backend.failNextCall = true

        await #expect(throws: FakePetBackend.Failure.self) {
            try await store.setRemindersEnabled(false)
        }
        #expect(store.remindersEnabled)
    }
}
