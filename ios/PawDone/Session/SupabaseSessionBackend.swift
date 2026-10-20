import Foundation
import GoogleSignIn
import Supabase

final class SupabaseSessionBackend: SessionBackend {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    var hasSession: Bool {
        client.auth.currentSession != nil
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken, accessToken: accessToken)
        )
    }

    func saveProfileNameIfMissing(_ name: String) async throws {
        guard let userID = client.auth.currentUser?.id else { return }
        try await client.from("profiles")
            .update(["name": name], returning: .minimal)
            .eq("id", value: userID.uuidString)
            .eq("name", value: "")
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

    func setPushToken(_ token: String?, deviceID: String, environment: String) async throws {
        try await client
            .rpc("set_push_token", params: SetPushTokenParams(deviceID: deviceID, token: token, environment: environment))
            .execute()
    }

    var signedInWithApple: Bool {
        client.auth.currentUser?.identities?.contains { $0.provider == "apple" } ?? false
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(body: DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode))
        )
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
        // Forget the Google account too, so the next sign-in can pick a different one.
        GIDSignIn.sharedInstance.signOut()
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

nonisolated private struct SetPushTokenParams: Encodable, Sendable {
    let deviceID: String
    let token: String?
    let environment: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case token = "p_token"
        case environment = "p_environment"
    }

    // Always send p_token, as null when clearing, so the call matches the function's signature.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(token, forKey: .token)
        try container.encode(environment, forKey: .environment)
    }
}

nonisolated private struct DeleteAccountBody: Encodable, Sendable {
    let appleAuthorizationCode: String?

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

nonisolated struct UnexpectedResponse: Error {
    let value: String
}
