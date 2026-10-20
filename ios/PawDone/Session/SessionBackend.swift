import Foundation

/// What the sign-in logic needs from the server. `SupabaseSessionBackend` is the real
/// one; tests use a fake.
protocol SessionBackend: AnyObject {
    /// True when a signed-in session is stored on this device.
    var hasSession: Bool { get }
    /// True when the signed-in user used Sign in with Apple.
    var signedInWithApple: Bool { get }

    func signInWithApple(idToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String, accessToken: String) async throws
    func saveProfileNameIfMissing(_ name: String) async throws

    /// Activates this install for the account. See `register_device` in the database.
    func registerDevice(id: String, force: Bool) async throws -> DeviceRegistration
    func deviceStatus(id: String) async throws -> DeviceStatus

    /// Saves this phone's push token, or clears it with nil. `environment` is "sandbox" or "production".
    func setPushToken(_ token: String?, deviceID: String, environment: String) async throws

    /// Permanently deletes the signed-in user and all their data on the server.
    /// `appleAuthorizationCode` lets the server revoke Sign in with Apple, as Apple requires.
    func deleteAccount(appleAuthorizationCode: String?) async throws

    /// Signs out on this device only.
    func signOut() async

    /// Emits whenever the session ends, including when the server revokes it.
    func sessionEndedEvents() -> AsyncStream<Void>
}

enum DeviceRegistration: String {
    case registered = "ok"
    /// A Free account is already active on another phone.
    case conflict
}

enum DeviceStatus: String {
    case active
    /// The account was used on another phone since.
    case inactive
    /// This install hasn't been registered yet.
    case unknown
}
