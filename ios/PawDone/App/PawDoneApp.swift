import GoogleSignIn
import SwiftUI

@main
struct PawDoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices.live()

    var body: some Scene {
        WindowGroup {
            RootView(petBackend: services.petBackend, subscriptions: services.subscriptions)
                .environment(services.session)
                // Google's sign-in returns to the app through this URL.
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
