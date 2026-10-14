import SwiftUI

/// Everything after sign-in: first-run setup, then the main tabs.
struct SignedInView: View {
    @State private var store: PetStore
    @Environment(\.scenePhase) private var scenePhase

    init(backend: any PetBackend) {
        _store = State(initialValue: PetStore(backend: backend))
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
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.phase == .ready {
                Task { await store.refreshToday() }
            }
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
