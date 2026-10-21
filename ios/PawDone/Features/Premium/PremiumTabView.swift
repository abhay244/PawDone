import StoreKit
import SwiftUI

/// The Premium tab: plans for users without Premium, and their subscription for those with it.
struct PremiumTabView: View {
    @Environment(PetStore.self) private var store

    var body: some View {
        Group {
            if store.iHavePremium {
                PremiumStatusView()
            } else {
                PaywallView(isSheet: false, note: sharedPremiumNote)
            }
        }
        // Pick up renewals, cancellations and expiry that happened elsewhere.
        .task { await store.refreshPremium() }
    }

    /// Helpers already get Premium features for the pet they help with, through its owner.
    private var sharedPremiumNote: String? {
        guard let pet = store.pet, !store.isOwner, store.hasPremium else { return nil }
        let owner = store.ownerName(of: pet) ?? "The owner"
        return "\(owner) has Premium, so it's already on for \(pet.name). Get your own for your pet and devices."
    }
}

/// For subscribers: what their plan is, when it renews, what it includes.
private struct PremiumStatusView: View {
    @Environment(PetStore.self) private var store
    @State private var isManagingSubscription = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 64, height: 64)
                            .accessibilityHidden(true)
                        Text("TailTick Premium")
                            .font(.title2.bold())
                        Label("Active", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Your plan") {
                    if let period = PremiumPlan.Period(productID: store.myEntitlement?.productID) {
                        LabeledContent("Plan", value: period.displayName)
                    }
                    if let expiresAt = store.myEntitlement?.expiresAt {
                        LabeledContent("Renews or ends", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button("Manage subscription") { isManagingSubscription = true }
                }

                Section {
                    Benefit(symbol: "person.2.fill", title: "Family & helpers", detail: householdDetail)
                    Benefit(symbol: "photo.on.rectangle.angled", title: "Shared photo proof",
                            detail: "Everyone in the household sees the photos.")
                    Benefit(symbol: "bell.badge.fill", title: "Done notifications",
                            detail: "Everyone hears when a task is finished.")
                    Benefit(symbol: "iphone.and.arrow.forward", title: "All your devices",
                            detail: "Use TailTick on your iPhone and iPad at the same time.")
                } header: {
                    Text("Included")
                } footer: {
                    Text("Invite and manage people in Account → Family & helpers.")
                }
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
            .onChange(of: isManagingSubscription) { _, isOpen in
                // Pick up a cancellation or plan change made in the sheet.
                if !isOpen { Task { await store.refreshPremium() } }
            }
        }
    }

    private var householdDetail: String {
        guard store.isOwner else {
            return "Invite up to \(PetStore.householdLimit) people to help with your pet."
        }
        let used = store.memberIDs.count + store.invites.count
        return "\(used) of \(PetStore.householdLimit) places used, including open invites."
    }
}
