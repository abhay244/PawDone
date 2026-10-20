import StoreKit
import SwiftUI

/// Explains what deleting the account removes, warns about an active subscription, then deletes.
struct DeleteAccountView: View {
    @Environment(PetStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirming = false
    @State private var isDeleting = false
    @State private var isManagingSubscription = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This can't be undone", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    ForEach(deletedItems, id: \.self) { item in
                        Label(item, systemImage: "trash")
                    }
                } header: {
                    Text("Deleting your account permanently removes")
                } footer: {
                    Text("Tasks you marked done in other people's households stay in their history, without your name or photos.")
                }

                if store.iHavePremium {
                    Section {
                        Text("Deleting your account doesn't cancel your Premium subscription. Cancel it first, or Apple will keep charging you.")
                        Button("Manage subscription") { isManagingSubscription = true }
                    } header: {
                        Text("Your subscription")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirming = true
                    } label: {
                        HStack {
                            Text("Delete account")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeleting)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
            .confirmationDialog("Delete your account?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Delete account", role: .destructive, action: delete)
            } message: {
                Text(session.deletionNeedsAppleAuthorization
                    ? "Everything listed will be permanently deleted. Apple will ask you to confirm."
                    : "Everything listed will be permanently deleted.")
            }
            .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
            .onChange(of: isManagingSubscription) { _, isOpen in
                if !isOpen { Task { await store.refreshPremium() } }
            }
            .alert("Couldn't delete your account", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var ownedPet: Pet? {
        store.pets.first { $0.ownerID == store.myUserID }
    }

    private var deletedItems: [String] {
        var items: [String] = []
        if let pet = ownedPet {
            items.append("\(pet.name), with its schedule, history and photos")
            items.append("Access for anyone helping with \(pet.name)")
        }
        items.append("Your name, sign-in and settings")
        if !store.memberships.isEmpty {
            items.append("Your place in households you help with")
        }
        return items
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func delete() {
        isDeleting = true
        Task {
            do {
                // Apple requires revoking Sign in with Apple when an account is deleted;
                // the server needs a fresh authorization code for that.
                var appleCode: String?
                if session.deletionNeedsAppleAuthorization {
                    appleCode = try await AppleReauthorization.authorizationCode()
                }
                // On success the session ends and the app returns to the sign-in screen.
                try await session.deleteAccount(appleAuthorizationCode: appleCode)
            } catch is AppleReauthorization.Cancelled {
                isDeleting = false
            } catch {
                _ = UserFacingError.message(for: error) // Logs the details.
                errorMessage = "Nothing was deleted. Check your connection and try again."
                isDeleting = false
            }
        }
    }
}
