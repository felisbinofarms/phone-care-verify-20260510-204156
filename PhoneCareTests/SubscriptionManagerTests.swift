import Testing
import Foundation
import StoreKit
@testable import PhoneCare

private struct MockProductLoader: StoreKitProductLoading {
    func loadProducts(ids: Set<String>) async throws -> [Product] { [] }
}

private struct ThrowingProductLoader: StoreKitProductLoading {
    enum LoaderError: Error { case simulated }
    func loadProducts(ids: Set<String>) async throws -> [Product] {
        throw LoaderError.simulated
    }
}

private final class FlakyProductLoader: StoreKitProductLoading, @unchecked Sendable {
    var shouldThrow = true

    func loadProducts(ids: Set<String>) async throws -> [Product] {
        if shouldThrow {
            throw ThrowingProductLoader.LoaderError.simulated
        }
        return []
    }
}

private final class MockPurchaseExecutor: PurchaseExecuting, @unchecked Sendable {
    var nextOutcome: PurchaseFlowOutcome = .userCancelled
    var shouldThrow: Error?

    func executePurchase(_ product: Product) async throws -> (PurchaseFlowOutcome, Transaction?) {
        if let err = shouldThrow { throw err }
        // Tests pass `transaction: nil` since `Transaction` is non-constructible.
        return (nextOutcome, nil)
    }
}

private final class MockEntitlementProvider: EntitlementSnapshotting, @unchecked Sendable {
    var snapshots: [EntitlementSnapshot] = []
    func currentEntitlements() async -> [EntitlementSnapshot] { snapshots }
}

private func makeSnapshot(
    productID: String = "com.phonecare.premium.annual",
    isRevoked: Bool = false,
    expirationDate: Date? = Date().addingTimeInterval(86_400 * 30),
    isIntroductoryOffer: Bool = false,
    gracePeriodExpirationDate: Date? = nil
) -> EntitlementSnapshot {
    EntitlementSnapshot(
        productID: productID,
        isRevoked: isRevoked,
        expirationDate: expirationDate,
        isIntroductoryOffer: isIntroductoryOffer,
        gracePeriodExpirationDate: gracePeriodExpirationDate
    )
}

@Suite("SubscriptionManager")
@MainActor
struct SubscriptionManagerTests {

    // MARK: - ProductID enum

    @Test("Every ProductID case round-trips through init(rawValue:)")
    func productID_roundTrip() {
        for id in SubscriptionManager.ProductID.allCases {
            #expect(SubscriptionManager.ProductID(rawValue: id.rawValue) == id,
                    "\(id) did not round-trip through rawValue")
        }
    }

    @Test("Every ProductID has a non-empty raw value starting with the app bundle prefix")
    func productID_rawValueFormat() {
        for id in SubscriptionManager.ProductID.allCases {
            #expect(!id.rawValue.isEmpty)
            #expect(id.rawValue.hasPrefix("com.phonecare.premium."),
                    "\(id.rawValue) missing expected bundle prefix")
        }
    }

    @Test("ProductID returns nil for an unknown raw value")
    func productID_unknownRawValue() {
        #expect(SubscriptionManager.ProductID(rawValue: "com.competitor.app") == nil)
    }

    // MARK: - Initial state

    @Test("Manager starts with no products loaded")
    func initialState_noProducts() {
        let manager = SubscriptionManager()
        #expect(manager.products.isEmpty)
    }

    @Test("Manager starts not loading")
    func initialState_notLoading() {
        let manager = SubscriptionManager()
        #expect(manager.isLoading == false)
    }

    @Test("Manager starts with no purchase error")
    func initialState_noPurchaseError() {
        let manager = SubscriptionManager()
        #expect(manager.purchaseError == nil)
    }

    @Test("Manager starts with no expiration date")
    func initialState_noExpirationDate() {
        let manager = SubscriptionManager()
        #expect(manager.expirationDate == nil)
    }

    @Test("Manager starts not in grace period")
    func initialState_notInGracePeriod() {
        let manager = SubscriptionManager()
        #expect(manager.isInGracePeriod == false)
    }

    // MARK: - Premium state consistency

    @Test("Two managers created in the same process agree on isPremium")
    func isPremium_consistentAcrossInstances() {
        let a = SubscriptionManager()
        let b = SubscriptionManager()
        #expect(a.isPremium == b.isPremium)
    }

    @Test("Trial and currentProductID are nil before any entitlement check")
    func initialState_noTrialOrProduct() {
        let manager = SubscriptionManager()
        #expect(manager.isInTrial == false)
        #expect(manager.currentProductID == nil)
    }

    // MARK: - isPremium starts false on fresh init

    @Test("isPremium is false on fresh init when no cached premium state exists")
    func isPremium_freshInit_false() {
        UserDefaults.standard.removeObject(forKey: "PhoneCare_isPremium")
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: "PhoneCare_debugPremiumBypass")
        #endif
        let manager = SubscriptionManager()
        #expect(manager.isPremium == false)
    }

    // MARK: - Debug premium bypass (DEBUG builds only)

    #if DEBUG
    @Test("debugPremiumBypassEnabled toggles hasPremiumAccess immediately")
    func debugPremiumBypass_togglesHasPremiumAccess() {
        UserDefaults.standard.removeObject(forKey: "PhoneCare_isPremium")
        UserDefaults.standard.removeObject(forKey: "PhoneCare_debugPremiumBypass")
        let manager = SubscriptionManager()
        #expect(manager.hasPremiumAccess == false)
        manager.debugPremiumBypassEnabled = true
        #expect(manager.hasPremiumAccess == true)
        manager.debugPremiumBypassEnabled = false
        #expect(manager.hasPremiumAccess == false)
    }

    @Test("debugPremiumBypassEnabled persists to UserDefaults")
    func debugPremiumBypass_persistsToUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "PhoneCare_debugPremiumBypass")
        let manager = SubscriptionManager()
        manager.debugPremiumBypassEnabled = true
        #expect(UserDefaults.standard.bool(forKey: "PhoneCare_debugPremiumBypass") == true)
        manager.debugPremiumBypassEnabled = false
    }
    #endif

    // MARK: - loadProducts in test environment

    @Test("loadProducts in test environment does not crash")
    func loadProducts_testEnvironment_doesNotCrash() async {
        let manager = SubscriptionManager(productLoader: MockProductLoader())
        await manager.loadProducts()
        // The key invariant: isLoading must be false after the call completes.
        #expect(manager.isLoading == false)
    }

    @Test("loadProducts leaves isLoading false after completion")
    func loadProducts_isLoading_falseAfterCompletion() async {
        let manager = SubscriptionManager(productLoader: MockProductLoader())
        #expect(manager.isLoading == false)
        await manager.loadProducts()
        #expect(manager.isLoading == false)
    }

    // MARK: - Error paths (#118)

    @Test("loadProducts surfaces purchaseError when the loader throws")
    func loadProducts_throwingLoader_setsPurchaseError() async {
        let manager = SubscriptionManager(productLoader: ThrowingProductLoader())
        await manager.loadProducts()
        #expect(manager.products.isEmpty)
        #expect(manager.purchaseError != nil)
        #expect(manager.isLoading == false)
    }

    @Test("loadProducts recovers if a later call succeeds after an earlier failure")
    func loadProducts_recoversAfterFailure() async {
        let loader = FlakyProductLoader()
        let manager = SubscriptionManager(productLoader: loader)

        await manager.loadProducts()
        #expect(manager.purchaseError != nil)

        loader.shouldThrow = false
        await manager.loadProducts()
        #expect(manager.purchaseError == nil)
        #expect(manager.isLoading == false)
    }

    // MARK: - Purchase outcome handling — #104

    @Test("applyPurchaseOutcome(.completed) calls checkEntitlement and updates premium state")
    func applyPurchaseOutcome_completed_callsCheckEntitlement() async {
        UserDefaults.standard.removeObject(forKey: "PhoneCare_isPremium")
        let provider = MockEntitlementProvider()
        provider.snapshots = [makeSnapshot()]
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: provider
        )

        _ = await manager.applyPurchaseOutcome(.completed, transaction: nil)
        #expect(manager.isPremium == true)
        #expect(manager.currentProductID == "com.phonecare.premium.annual")
    }

    @Test("applyPurchaseOutcome(.userCancelled) returns nil and leaves premium state unchanged")
    func applyPurchaseOutcome_userCancelled_noStateChange() async {
        UserDefaults.standard.removeObject(forKey: "PhoneCare_isPremium")
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let initial = manager.isPremium

        let result = await manager.applyPurchaseOutcome(.userCancelled, transaction: nil)
        #expect(result == nil)
        #expect(manager.isPremium == initial)
    }

    @Test("applyPurchaseOutcome(.pending) returns nil")
    func applyPurchaseOutcome_pending_returnsNil() async {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let result = await manager.applyPurchaseOutcome(.pending, transaction: nil)
        #expect(result == nil)
    }

    @Test("applyPurchaseOutcome(.unknown) returns nil")
    func applyPurchaseOutcome_unknown_returnsNil() async {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let result = await manager.applyPurchaseOutcome(.unknown, transaction: nil)
        #expect(result == nil)
    }

    // MARK: - Entitlement aggregation — #104

    @Test("aggregateEntitlements with empty list returns inactive aggregate")
    func aggregateEntitlements_emptyList_returnsInactive() {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let aggregated = manager.aggregateEntitlements([])
        #expect(aggregated.isActive == false)
        #expect(aggregated.productID == nil)
        #expect(aggregated.expirationDate == nil)
        #expect(aggregated.isTrial == false)
        #expect(aggregated.isGracePeriod == false)
    }

    @Test("aggregateEntitlements with one active snapshot returns active state")
    func aggregateEntitlements_oneActive_returnsActive() {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let exp = Date(timeIntervalSince1970: 2_000_000_000)
        let snap = makeSnapshot(productID: "com.phonecare.premium.monthly", expirationDate: exp)
        let aggregated = manager.aggregateEntitlements([snap])

        #expect(aggregated.isActive == true)
        #expect(aggregated.productID == "com.phonecare.premium.monthly")
        #expect(aggregated.expirationDate == exp)
    }

    @Test("aggregateEntitlements skips revoked snapshots")
    func aggregateEntitlements_revoked_isInactive() {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let aggregated = manager.aggregateEntitlements([makeSnapshot(isRevoked: true)])
        #expect(aggregated.isActive == false)
        #expect(aggregated.productID == nil)
    }

    @Test("aggregateEntitlements sets isTrial when introductory offer is present")
    func aggregateEntitlements_introductory_setsTrial() {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let snap = makeSnapshot(isIntroductoryOffer: true)
        let aggregated = manager.aggregateEntitlements([snap])
        #expect(aggregated.isActive == true)
        #expect(aggregated.isTrial == true)
    }

    @Test("aggregateEntitlements filters out unknown product IDs")
    func aggregateEntitlements_unknownProductID_isFiltered() {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let snap = makeSnapshot(productID: "com.competitor.app.premium")
        let aggregated = manager.aggregateEntitlements([snap])
        #expect(aggregated.isActive == false)
    }

    @Test("aggregateEntitlements sets isGracePeriod when gracePeriodExpirationDate is present")
    func aggregateEntitlements_gracePeriod_isSet() {
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: MockEntitlementProvider()
        )
        let snap = makeSnapshot(gracePeriodExpirationDate: Date().addingTimeInterval(3600))
        let aggregated = manager.aggregateEntitlements([snap])
        #expect(aggregated.isActive == true)
        #expect(aggregated.isGracePeriod == true)
    }

    // MARK: - checkEntitlement integration — #104

    @Test("checkEntitlement with mocked provider returning active updates manager state")
    func checkEntitlement_integration_withMockedProvider() async {
        UserDefaults.standard.removeObject(forKey: "PhoneCare_isPremium")
        let provider = MockEntitlementProvider()
        let exp = Date(timeIntervalSince1970: 2_100_000_000)
        provider.snapshots = [makeSnapshot(productID: "com.phonecare.premium.weekly", expirationDate: exp)]
        let manager = SubscriptionManager(
            productLoader: MockProductLoader(),
            purchaseExecutor: MockPurchaseExecutor(),
            entitlementProvider: provider
        )

        await manager.checkEntitlement()
        #expect(manager.isPremium == true)
        #expect(manager.currentProductID == "com.phonecare.premium.weekly")
        #expect(manager.expirationDate == exp)
    }
}
