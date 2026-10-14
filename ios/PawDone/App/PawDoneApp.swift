import SwiftUI

@main
struct PawDoneApp: App {
    @State private var services = AppServices.live()

    var body: some Scene {
        WindowGroup {
            RootView(petBackend: services.petBackend)
                .environment(services.session)
        }
    }
}
