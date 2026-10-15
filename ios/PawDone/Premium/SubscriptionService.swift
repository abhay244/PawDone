import Foundation

/// A Premium plan as shown on the paywall, with the App Store's localized prices.
nonisolated struct PremiumPlan: Identifiable, Equatable, Sendable {
    enum Period: Int, Sendable {
        case monthly = 1
        case threeMonths = 3

        var months: Int { rawValue }
    }

    let id: String
    let period: Period
    /// e.g. "₹199.00" or "$3.99"
    let price: String
    /// For plans longer than a month, e.g. "₹166.33".
    let pricePerMonth: String?
}

nonisolated enum PurchaseOutcome: Equatable, Sendable {
    /// `active` is whether Premium is now on.
    case purchased(active: Bool)
    case cancelled
}

/// The store. `RevenueCatSubscriptionService` is the real one; tests and demo mode use fakes.
protocol SubscriptionService: AnyObject {
    /// Identifies purchases with the signed-in user. Call on every sign-in.
    func start(userID: String) async
    /// Premium plans, shortest first.
    func plans() async throws -> [PremiumPlan]
    func purchase(_ plan: PremiumPlan) async throws -> PurchaseOutcome
    /// Restores earlier purchases on this Apple Account. Returns whether Premium is active.
    func restore() async throws -> Bool
}
