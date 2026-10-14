import Observation
import UIKit
import UserNotifications

/// Asks for notification permission and passes the APNs device token on.
@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Called with each device token, as hex.
    @ObservationIgnored var onToken: ((String) -> Void)?

    /// The APNs environment for this build: Xcode debug builds get sandbox tokens.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Asks the first time (the system remembers the answer), then registers with APNs if allowed.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshStatus()
        if [.authorized, .provisional, .ephemeral].contains(authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func didRegister(deviceToken: Data) {
        onToken?(deviceToken.map { String(format: "%02x", $0) }.joined())
    }
}
