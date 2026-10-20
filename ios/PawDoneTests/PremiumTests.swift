import Foundation
import Testing
@testable import PawDone

final class FakeSubscriptionService: SubscriptionService {
    struct Failure: Error {}

    var plansResult: Result<[PremiumPlan], Error> = .success([])
    var purchaseResult: Result<PurchaseOutcome, Error> = .success(.purchased(active: true))
    var restoreResult: Result<Bool, Error> = .success(false)
    private(set) var startedUserIDs: [String] = []
    private(set) var purchasedPlanIDs: [String] = []

    func start(userID: String) async { startedUserIDs.append(userID) }
    func plans() async throws -> [PremiumPlan] { try plansResult.get() }

    func purchase(_ plan: PremiumPlan) async throws -> PurchaseOutcome {
        purchasedPlanIDs.append(plan.id)
        return try purchaseResult.get()
    }

    func restore() async throws -> Bool { try restoreResult.get() }
}

@MainActor
struct PremiumStoreTests {
    let service = FakeSubscriptionService()
    let backend = FakePetBackend()
    let monthly = PremiumPlan(id: "monthly", period: .monthly, price: "₹199.00", pricePerMonth: nil)
    let quarterly = PremiumPlan(id: "quarterly", period: .threeMonths, price: "₹499.00", pricePerMonth: "₹166.33")

    func makeStore() -> PremiumStore {
        PremiumStore(service: service, backend: backend)
    }

    @Test func startsWithLowercaseUserID() async {
        let userID = UUID()
        await makeStore().start(userID: userID)
        #expect(service.startedUserIDs == [userID.uuidString.lowercased()], "matches the server's IDs; RevenueCat is case-sensitive")
    }

    @Test func unavailableWithoutService() async {
        let store = PremiumStore(service: nil, backend: backend)
        #expect(!store.isAvailable)
        #expect(!(await store.purchase(monthly)))
    }

    @Test func loadsPlans() async {
        service.plansResult = .success([monthly, quarterly])
        let store = makeStore()
        await store.loadPlans()
        #expect(store.plans == [monthly, quarterly])
    }

    @Test func plansFailureIsShown() async {
        service.plansResult = .failure(FakeSubscriptionService.Failure())
        let store = makeStore()
        await store.loadPlans()
        #expect(store.plansState == .failed)
    }

    @Test func purchaseSyncsTheServer() async {
        let store = makeStore()
        #expect(await store.purchase(quarterly))
        #expect(service.purchasedPlanIDs == ["quarterly"])
        #expect(backend.syncCount == 1)
        #expect(store.errorMessage == nil)
        #expect(!store.isWorking)
    }

    @Test func cancelledPurchaseIsQuiet() async {
        service.purchaseResult = .success(.cancelled)
        let store = makeStore()
        #expect(!(await store.purchase(monthly)))
        #expect(backend.syncCount == 0)
        #expect(store.errorMessage == nil)
    }

    @Test func failedPurchaseShowsError() async {
        service.purchaseResult = .failure(FakeSubscriptionService.Failure())
        let store = makeStore()
        #expect(!(await store.purchase(monthly)))
        #expect(store.errorMessage != nil)
        #expect(backend.syncCount == 0)
    }

    @Test func purchaseWithoutEntitlementExplains() async {
        service.purchaseResult = .success(.purchased(active: false))
        let store = makeStore()
        #expect(!(await store.purchase(monthly)))
        #expect(store.errorMessage?.contains("Restore purchases") == true)
    }

    @Test func restoreWithNothingToRestore() async {
        let store = makeStore()
        #expect(!(await store.restore()))
        #expect(store.errorMessage?.contains("No active Premium") == true)
    }

    @Test func restoreSyncsTheServer() async {
        service.restoreResult = .success(true)
        let store = makeStore()
        #expect(await store.restore())
        #expect(backend.syncCount == 1)
    }
}

struct PlanPeriodTests {
    @Test(arguments: [
        ("com.abhaysingh.pawdone.premium.monthly", PremiumPlan.Period?.some(.monthly)),
        ("com.abhaysingh.pawdone.premium.quarterly", .some(.threeMonths)),
        ("demo.monthly", .some(.monthly)),
        ("lifetime", nil),
    ])
    func readsPlanFromProductID(productID: String, period: PremiumPlan.Period?) {
        #expect(PremiumPlan.Period(productID: productID) == period)
    }

    @Test func noProductMeansNoPlan() {
        #expect(PremiumPlan.Period(productID: nil) == nil)
        #expect(PremiumPlan.Period.threeMonths.displayName == "3 months")
    }
}

@MainActor
struct MyPremiumTests {
    let now = ServerDate.parse("2026-10-16T10:00:00Z")!

    @Test func activeUntilExpiry() {
        let entitlement = MyEntitlement(isPremium: true, productID: "m", expiresAt: now.addingTimeInterval(60))
        #expect(entitlement.isActive(at: now))
        #expect(!entitlement.isActive(at: now.addingTimeInterval(120)))
        #expect(MyEntitlement(isPremium: true, productID: nil, expiresAt: nil).isActive(at: now), "no expiry: lifetime")
        #expect(!MyEntitlement(isPremium: false, productID: nil, expiresAt: nil).isActive(at: now))
    }

    @Test func decodesEntitlementRow() throws {
        let json = #"{"is_premium": true, "product_id": "com.abhaysingh.pawdone.premium.monthly", "expires_at": "2026-11-16T10:00:00+00:00"}"#
        let entitlement = try JSONDecoder().decode(MyEntitlement.self, from: Data(json.utf8))
        #expect(entitlement.isPremium)
        #expect(entitlement.expiresAt?.ISO8601Format() == "2026-11-16T10:00:00Z")
    }

    @Test func refreshPremiumPicksUpPurchase() async {
        let backend = FakePetBackend()
        let pet = Pet.make(owner: backend.currentUserID!)
        backend.pets = [pet]
        let now = now
        let store = PetStore(backend: backend, defaults: UserDefaults(suiteName: UUID().uuidString)!, now: { now })
        await store.load()
        #expect(!store.iHavePremium)
        #expect(!store.hasPremium)

        backend.myEntitlement = MyEntitlement(isPremium: true, productID: "m", expiresAt: now.addingTimeInterval(86_400))
        backend.premiumPetIDs = [pet.id]
        await store.refreshPremium()

        #expect(store.iHavePremium)
        #expect(store.hasPremium)
    }
}
