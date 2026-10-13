import SwiftUI

/// Placeholder until the Today screen is built (build step 2).
struct HomeView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("You're signed in", systemImage: "pawprint.fill")
            } description: {
                Text("Your pet and today's tasks will appear here.")
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign out", role: .destructive) {
                            Task { await session.signOut() }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .accessibilityLabel("Account")
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(SessionStore(backend: nil, deviceID: "preview"))
}
