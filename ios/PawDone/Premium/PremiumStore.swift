import Foundation
import Observation

/// Plans, purchases and restores for the paywall.
@Observable
final class PremiumStore {
    enum PlansState: Equatable {
        case idle
        case loading
        case loaded([PremiumPlan])
        case failed
    }

    private(set) var plansState: PlansState = .idle
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let service: (any SubscriptionService)?
    @ObservationIgnored private let backend: any PetBackend

    init(service: (any SubscriptionService)?, backend: any PetBackend) {
        self.service = service
        self.backend = backend
    }

    /// False until a RevenueCat API key is set in Config/Secrets.xcconfig.
    var isAvailable: Bool { service != nil }

    var plans: [PremiumPlan] {
        if case .loaded(let plans) = plansState { return plans }
        return []
    }

    /// Ties purchases to the signed-in user. RevenueCat IDs are case-sensitive, so this
    /// uses the lowercase form the server uses.
    func start(userID: UUID?) async {
        guard let service, let userID else { return }
        await service.start(userID: userID.uuidString.lowercased())
    }

    func loadPlans() async {
        guard let service else { return }
        plansState = .loading
        do {
            plansState = .loaded(try await service.plans())
        } catch {
            _ = UserFacingError.message(for: error) // Logs the details.
            plansState = .failed
        }
    }

    /// Returns true when Premium is now active.
    func purchase(_ plan: PremiumPlan) async -> Bool {
        guard let service else { return false }
        return await perform {
            switch try await service.purchase(plan) {
            case .cancelled:
                return false
            case .purchased(let active):
                if !active {
                    self.errorMessage = "Your purchase went through, but Premium isn't active yet. Try “Restore purchases” in a minute."
                }
                return active
            }
        }
    }

    /// Returns true when Premium is now active.
    func restore() async -> Bool {
        guard let service else { return false }
        return await perform {
            let active = try await service.restore()
            if !active {
                self.errorMessage = "No active Premium subscription was found for this Apple Account."
            }
            return active
        }
    }

    private func perform(_ action: () async throws -> Bool) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let active = try await action()
            if active {
                // Update the server now rather than waiting for RevenueCat's webhook.
                // If this fails, the webhook catches up shortly.
                try? await backend.syncPremium()
            }
            return active
        } catch {
            _ = UserFacingError.message(for: error) // Logs the details.
            errorMessage = "Couldn't complete that with the App Store. Check your connection and try again."
            return false
        }
    }
}
