import SwiftUI

@main
struct PawDoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices.live()

    var body: some Scene {
        WindowGroup {
            RootView(petBackend: services.petBackend)
                .environment(services.session)
        }
    }
}
