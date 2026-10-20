import SwiftUI

/// PawDone Premium: what it adds, the plans, and Apple's required subscription details.
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premium
    @Environment(PetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlanID: PremiumPlan.ID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    plansSection
                    footer
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                if premium.isAvailable {
                    subscribeBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if premium.plans.isEmpty {
                    await premium.loadPlans()
                }
                if selectedPlanID == nil {
                    // Default to the longer plan: better value.
                    selectedPlanID = premium.plans.last?.id
                }
            }
            .alert("Premium", isPresented: isShowingError) {
                Button("OK") {}
            } message: {
                Text(premium.errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("PawDone Premium")
                .font(.largeTitle.bold())
            Text("Share \(store.pet?.name ?? "your pet")'s care with the people who help.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            Benefit(symbol: "person.2.fill", title: "Invite 2 family members or helpers",
                    detail: "They see the day's tasks and mark them done.")
            Benefit(symbol: "photo.on.rectangle.angled", title: "Shared photo proof",
                    detail: "Everyone sees the photos, from any phone.")
            Benefit(symbol: "bell.badge.fill", title: "Know when it's done",
                    detail: "A notification as soon as someone finishes a task.")
            Benefit(symbol: "iphone.and.arrow.forward", title: "All your devices",
                    detail: "Use PawDone on your iPhone and iPad at the same time.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var plansSection: some View {
        if !premium.isAvailable {
            Text("Purchases aren't set up in this build yet.")
                .foregroundStyle(.secondary)
        } else {
            switch premium.plansState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .failed:
                VStack(spacing: 12) {
                    Text("Couldn't load the plans. Check your connection.")
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task {
                            await premium.loadPlans()
                            selectedPlanID = premium.plans.last?.id
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .loaded(let plans) where plans.isEmpty:
                Text("No plans are available right now. Try again later.")
                    .foregroundStyle(.secondary)
            case .loaded(let plans):
                VStack(spacing: 12) {
                    ForEach(plans) { plan in
                        PlanCard(plan: plan, isSelected: plan.id == selectedPlanID) {
                            selectedPlanID = plan.id
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if premium.isAvailable {
                Button("Restore purchases", action: restore)
                    .disabled(premium.isWorking)
            }
            Text("Subscriptions renew automatically at the same price until cancelled. Payment is charged to your Apple Account. Cancel anytime in Settings, at least 24 hours before the end of the period.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: AppConfig.termsOfUseURL)
                Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
            }
            .font(.caption)
        }
    }

    private var subscribeBar: some View {
        Button(action: subscribe) {
            Group {
                if premium.isWorking {
                    ProgressView()
                } else {
                    Text("Continue")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selectedPlan == nil || premium.isWorking)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Actions

    private var selectedPlan: PremiumPlan? {
        premium.plans.first { $0.id == selectedPlanID }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { premium.errorMessage != nil }, set: { if !$0 { premium.errorMessage = nil } })
    }

    private func subscribe() {
        guard let plan = selectedPlan else { return }
        Task {
            if await premium.purchase(plan) {
                await finish()
            }
        }
    }

    private func restore() {
        Task {
            if await premium.restore() {
                await finish()
            }
        }
    }

    private func finish() async {
        await store.refreshPremium()
        dismiss()
    }
}

private struct Benefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlanCard: View {
    let plan: PremiumPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.period == .monthly ? "Monthly" : "3 months")
                        .font(.headline)
                    if let perMonth = plan.pricePerMonth {
                        Text("\(perMonth) a month")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(plan.period == .monthly ? "\(plan.price) / month" : "\(plan.price) / 3 months")
                    .font(.headline)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : Color(.separator), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
