import Testing
@testable import PawDone

@MainActor
struct SessionStoreTests {
    let backend = FakeSessionBackend()

    func makeStore(hasSession: Bool = false) -> SessionStore {
        backend.hasSession = hasSession
        return SessionStore(backend: backend, deviceID: "device-1")
    }

    // MARK: Launch

    @Test func withoutBackendShowsNotConfigured() async {
        let store = SessionStore(backend: nil, deviceID: "device-1")
        await store.start()
        #expect(store.state == .notConfigured)
    }

    @Test func withoutStoredSessionShowsSignIn() async {
        let store = makeStore()
        await store.start()
        #expect(store.state == .signedOut)
    }

    @Test func storedSessionOnActiveDeviceStaysSignedIn() async {
        let store = makeStore(hasSession: true)
        await store.start()
        #expect(store.state == .signedIn)
        #expect(backend.signOutCount == 0)
    }

    @Test func storedSessionOnReplacedDeviceIsSignedOut() async {
        backend.deviceStatusResult = .success(.inactive)
        let store = makeStore(hasSession: true)
        await store.start()
        #expect(store.state == .signedOutElsewhere)
        #expect(backend.signOutCount == 1)
    }

    @Test func offlineAtLaunchStaysSignedIn() async {
        backend.deviceStatusResult = .failure(FakeSessionBackend.Failure())
        let store = makeStore(hasSession: true)
        await store.start()
        #expect(store.state == .signedIn)
    }

    @Test func unregisteredDeviceRegistersAtLaunch() async {
        backend.deviceStatusResult = .success(.unknown)
        let store = makeStore(hasSession: true)
        await store.start()
        #expect(store.state == .signedIn)
        #expect(backend.registrations.map(\.force) == [false])
    }

    // MARK: Sign in

    @Test func signInRegistersThisDevice() async {
        let store = makeStore()
        await store.start()
        await store.signInWithApple(idToken: "token", nonce: "nonce", fullName: "Sam Lee")

        #expect(store.state == .signedIn)
        #expect(backend.registrations.map(\.id) == ["device-1"])
        #expect(backend.registrations.map(\.force) == [false])
        #expect(backend.savedName == "Sam Lee")
    }

    @Test func googleSignInRegistersThisDevice() async {
        let store = makeStore()
        await store.start()
        await store.signInWithGoogle(idToken: "id", accessToken: "access", fullName: "Sam Lee")

        #expect(store.state == .signedIn)
        #expect(backend.googleSignIns.map(\.idToken) == ["id"])
        #expect(backend.googleSignIns.map(\.accessToken) == ["access"])
        #expect(backend.registrations.map(\.force) == [false])
        #expect(backend.savedName == "Sam Lee")
    }

    @Test func signInFailureShowsError() async {
        backend.signInError = FakeSessionBackend.Failure()
        let store = makeStore()
        await store.start()
        await store.signInWithApple(idToken: "token", nonce: "nonce", fullName: nil)

        #expect(store.state == .signedOut)
        #expect(store.errorMessage != nil)
        #expect(backend.registrations.isEmpty)
    }

    @Test func registrationFailureSignsOutWithError() async {
        backend.registrationError = FakeSessionBackend.Failure()
        let store = makeStore()
        await store.start()
        await store.signInWithApple(idToken: "token", nonce: "nonce", fullName: nil)

        #expect(store.state == .signedOut)
        #expect(store.errorMessage != nil)
        #expect(backend.signOutCount == 1)
    }

    // MARK: Another phone already active

    @Test func conflictAsksBeforeTakingOver() async {
        backend.registrationResults = [.conflict, .registered]
        let store = makeStore()
        await store.start()
        await store.signInWithApple(idToken: "token", nonce: "nonce", fullName: nil)
        #expect(store.state == .confirmingDeviceSwitch)

        await store.confirmDeviceSwitch()
        #expect(store.state == .signedIn)
        #expect(backend.registrations.map(\.force) == [false, true])
    }

    @Test func cancellingTakeoverSignsOut() async {
        backend.registrationResults = [.conflict]
        let store = makeStore()
        await store.start()
        await store.signInWithApple(idToken: "token", nonce: "nonce", fullName: nil)
        await store.cancelDeviceSwitch()

        #expect(store.state == .signedOut)
        #expect(backend.signOutCount == 1)
    }

    // MARK: Signing out

    @Test func revokedSessionShowsSignedOutElsewhere() async throws {
        let store = makeStore(hasSession: true)
        await store.start()
        backend.revokeSession()

        try await waitUntil { store.state == .signedOutElsewhere }
    }

    @Test func ownSignOutDoesNotLookLikeAnotherPhone() async throws {
        let store = makeStore(hasSession: true)
        await store.start()
        await store.signOut()
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.state == .signedOut)
    }

    @Test func returningToAppChecksDevice() async {
        let store = makeStore(hasSession: true)
        await store.start()
        backend.deviceStatusResult = .success(.inactive)
        await store.appBecameActive()

        #expect(store.state == .signedOutElsewhere)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
