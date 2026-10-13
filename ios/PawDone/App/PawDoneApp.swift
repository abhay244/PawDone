import SwiftUI

@main
struct PawDoneApp: App {
    @State private var session = SessionStore.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
