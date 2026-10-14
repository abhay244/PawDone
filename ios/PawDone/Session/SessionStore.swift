import Foundation
import Observation

/// Owns the sign-in state and applies the one-phone-per-account rule on this device.
@Observable
final class SessionStore {
    enum State: Equatable {
        case loading
        /// Supabase details are missing from Config/Secrets.xcconfig.
        case notConfigured
        case signedOut
        /// Signed in, but the account is active on another phone. Waiting for the user to choose.
        case confirmingDeviceSwitch
        case signedIn
        /// This phone was signed out because the account was used on another phone.
        case signedOutElsewhere
    }

    private(set) var state: State = .loading
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let backend: (any SessionBackend)?
    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private var isEndingSession = false
    @ObservationIgnored private var isVerifyingDevice = false
    @ObservationIgnored private var sessionEndedTask: Task<Void, Never>?

    init(backend: (any SessionBackend)?, deviceID: String) {
        self.backend = backend
        self.deviceID = deviceID
    }

    func start() async {
        guard state == .loading else { return }
        guard let backend else {
            state = .notConfigured
            return
        }
        watchForSessionEnd(backend)

        if backend.hasSession {
            state = .signedIn
            await verifyDevice()
        } else {
            state = .signedOut
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
        guard let backend else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await backend.signInWithApple(idToken: idToken, nonce: nonce)
        } catch {
            errorMessage = "Couldn't sign in. Check your connection and try again."
            return
        }
        // Apple only shares the name on the first sign-in, so save it while we have it.
        if let fullName, !fullName.isEmpty {
            try? await backend.saveProfileName(fullName)
        }
        await registerDevice(force: false)
    }

    func showSignInError(_ message: String) {
        errorMessage = message
    }

    func confirmDeviceSwitch() async {
        isWorking = true
        defer { isWorking = false }
        await registerDevice(force: true)
    }

    func cancelDeviceSwitch() async {
        await endSession(then: .signedOut)
    }

    func signOut() async {
        await endSession(then: .signedOut)
    }

    func dismissSignedOutElsewhere() {
        state = .signedOut
    }

    /// Re-checks the device when the app comes back to the foreground.
    func appBecameActive() async {
        guard state == .signedIn else { return }
        await verifyDevice()
    }

    private func registerDevice(force: Bool) async {
        guard let backend else { return }
        do {
            switch try await backend.registerDevice(id: deviceID, force: force) {
            case .registered:
                state = .signedIn
            case .conflict:
                state = .confirmingDeviceSwitch
            }
        } catch {
            errorMessage = "Couldn't finish signing in. Check your connection and try again."
            await endSession(then: .signedOut)
        }
    }

    private func verifyDevice() async {
        guard let backend, !isVerifyingDevice else { return }
        isVerifyingDevice = true
        defer { isVerifyingDevice = false }

        do {
            switch try await backend.deviceStatus(id: deviceID) {
            case .active:
                break
            case .inactive:
                await endSession(then: .signedOutElsewhere)
            case .unknown:
                await registerDevice(force: false)
            }
        } catch {
            // Offline or a server problem: stay signed in and check again next time.
        }
    }

    private func endSession(then newState: State) async {
        isEndingSession = true
        await backend?.signOut()
        state = newState
        isEndingSession = false
    }

    /// Catches sessions revoked by the server, e.g. when another phone took over.
    private func watchForSessionEnd(_ backend: any SessionBackend) {
        sessionEndedTask = Task { [weak self] in
            for await _ in backend.sessionEndedEvents() {
                guard let self else { return }
                if state == .signedIn && !isEndingSession {
                    state = .signedOutElsewhere
                }
            }
        }
    }
}
