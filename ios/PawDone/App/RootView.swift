import SwiftUI

/// Shows the right screen for the current sign-in state.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .notConfigured, .signedOut:
                SignInView()
            case .confirmingDeviceSwitch:
                DeviceSwitchView()
            case .signedOutElsewhere:
                SignedOutElsewhereView()
            case .signedIn:
                HomeView()
            }
        }
        .task { await session.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.appBecameActive() }
            }
        }
    }
}
