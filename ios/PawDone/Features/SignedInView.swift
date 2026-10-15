import SwiftUI

/// Everything after sign-in: first-run setup, then the main tabs.
struct SignedInView: View {
    @State private var store: PetStore
    @State private var premium: PremiumStore
    @Environment(\.scenePhase) private var scenePhase

    init(backend: any PetBackend, subscriptions: (any SubscriptionService)?) {
        _store = State(initialValue: PetStore(backend: backend))
        _premium = State(initialValue: PremiumStore(service: subscriptions, backend: backend))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load your pet", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") {
                        Task { await store.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .needsOnboarding:
                OnboardingView()
            case .ready:
                MainTabView()
            }
        }
        .environment(store)
        .environment(premium)
        .task {
            await premium.start(userID: store.myUserID)
            await store.load()
        }
        // Ask for notifications once the pet is set up, so the prompt makes sense.
        .task(id: store.phase == .ready) {
            if store.phase == .ready {
                await PushRegistrar.shared.requestAuthorizationAndRegister()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.phase == .ready {
                Task {
                    await store.refreshToday()
                    await PushRegistrar.shared.refreshStatus()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushReceived)) { _ in
            Task { await store.refreshToday() }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar") }
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}
