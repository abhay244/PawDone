import os
import UIKit
import UserNotifications

extension Notification.Name {
    /// A push notification arrived while the app was open.
    nonisolated static let pushReceived = Notification.Name("PawDonePushReceived")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let logger = Logger(subsystem: "com.abhaysingh.pawdone", category: "push")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Self.logger.error("Couldn't register for push: \(String(describing: error), privacy: .public)")
    }

    /// Shows notifications while the app is open too, and lets the screens refresh.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        NotificationCenter.default.post(name: .pushReceived, object: nil)
        return [.banner, .list, .sound]
    }
}
