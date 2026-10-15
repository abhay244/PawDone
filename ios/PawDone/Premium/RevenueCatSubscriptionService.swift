import Foundation
import RevenueCat

/// Purchases through RevenueCat. Products live in App Store Connect (or RevenueCat's Test
/// Store); RevenueCat's "premium" entitlement unlocks Premium, and its "current" offering
/// lists the plans.
final class RevenueCatSubscriptionService: SubscriptionService {
    static let entitlementID = "premium"

    private let apiKey: String
    private var packages: [String: Package] = [:]

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func start(userID: String) async {
        if !Purchases.isConfigured {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(withAPIKey: apiKey, appUserID: userID)
        } else if Purchases.shared.appUserID != userID {
            _ = try? await Purchases.shared.logIn(userID)
        }
    }

    func plans() async throws -> [PremiumPlan] {
        let offerings = try await Purchases.shared.offerings()
        var plans: [PremiumPlan] = []
        for package in offerings.current?.availablePackages ?? [] {
            let period: PremiumPlan.Period
            switch package.packageType {
            case .monthly: period = .monthly
            case .threeMonth: period = .threeMonths
            default: continue
            }
            packages[package.identifier] = package
            plans.append(PremiumPlan(
                id: package.identifier,
                period: period,
                price: package.storeProduct.localizedPriceString,
                pricePerMonth: period == .monthly ? nil : package.storeProduct.localizedPricePerMonth
            ))
        }
        return plans.sorted { $0.period.months < $1.period.months }
    }

    func purchase(_ plan: PremiumPlan) async throws -> PurchaseOutcome {
        guard let package = packages[plan.id] else { throw PlanUnavailable() }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            return .purchased(active: result.customerInfo.entitlements[Self.entitlementID]?.isActive == true)
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        }
    }

    func restore() async throws -> Bool {
        let customerInfo = try await Purchases.shared.restorePurchases()
        return customerInfo.entitlements[Self.entitlementID]?.isActive == true
    }
}

nonisolated struct PlanUnavailable: Error {}
