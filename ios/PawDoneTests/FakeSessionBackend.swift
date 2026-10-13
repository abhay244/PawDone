import Foundation
@testable import PawDone

final class FakeSessionBackend: SessionBackend {
    struct Failure: Error {}

    var hasSession = false
    var signInError: Error?
    var registrationResults: [DeviceRegistration] = []
    var registrationError: Error?
    var deviceStatusResult: Result<DeviceStatus, Error> = .success(.active)

    private(set) var registrations: [(id: String, force: Bool)] = []
    private(set) var signOutCount = 0
    private(set) var savedName: String?

    private let events = AsyncStream<Void>.makeStream()

    func signInWithApple(idToken: String, nonce: String) async throws {
        if let signInError { throw signInError }
        hasSession = true
    }

    func saveProfileName(_ name: String) async throws {
        savedName = name
    }

    func registerDevice(id: String, force: Bool) async throws -> DeviceRegistration {
        registrations.append((id, force))
        if let registrationError { throw registrationError }
        return registrationResults.isEmpty ? .registered : registrationResults.removeFirst()
    }

    func deviceStatus(id: String) async throws -> DeviceStatus {
        try deviceStatusResult.get()
    }

    /// Like the Supabase SDK, signing out also emits a session-ended event.
    func signOut() async {
        signOutCount += 1
        hasSession = false
        events.continuation.yield()
    }

    func sessionEndedEvents() -> AsyncStream<Void> {
        events.stream
    }

    /// Simulates the server revoking this phone's session.
    func revokeSession() {
        hasSession = false
        events.continuation.yield()
    }
}
