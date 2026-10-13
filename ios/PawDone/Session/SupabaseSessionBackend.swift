import Foundation
import Supabase

final class SupabaseSessionBackend: SessionBackend {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Nil until the Supabase details are filled in in Config/Secrets.xcconfig.
    static func fromConfig() -> SupabaseSessionBackend? {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else { return nil }
        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        return SupabaseSessionBackend(client: client)
    }

    var hasSession: Bool {
        client.auth.currentSession != nil
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    func saveProfileName(_ name: String) async throws {
        guard let userID = client.auth.currentUser?.id else { return }
        try await client.from("profiles")
            .update(["name": name])
            .eq("id", value: userID.uuidString)
            .execute()
    }

    func registerDevice(id: String, force: Bool) async throws -> DeviceRegistration {
        let response: String = try await client
            .rpc("register_device", params: RegisterDeviceParams(deviceID: id, force: force))
            .execute()
            .value
        guard let registration = DeviceRegistration(rawValue: response) else {
            throw UnexpectedResponse(value: response)
        }
        return registration
    }

    func deviceStatus(id: String) async throws -> DeviceStatus {
        let response: String = try await client
            .rpc("device_status", params: ["p_device_id": id])
            .execute()
            .value
        guard let status = DeviceStatus(rawValue: response) else {
            throw UnexpectedResponse(value: response)
        }
        return status
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    func sessionEndedEvents() -> AsyncStream<Void> {
        let auth = client.auth
        return AsyncStream { continuation in
            let task = Task {
                for await change in auth.authStateChanges where change.event == .signedOut {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

nonisolated private struct RegisterDeviceParams: Encodable, Sendable {
    let deviceID: String
    let force: Bool

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case force = "p_force"
    }
}

nonisolated struct UnexpectedResponse: Error {
    let value: String
}
