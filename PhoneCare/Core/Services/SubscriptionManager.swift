import Foundation
import StoreKit
import OSLog

// MARK: - Test Seam DTOs

/// Sendable summary of a single StoreKit entitlement, decoupled from
/// `Transaction` (which is non-constructible in tests).
struct EntitlementSnapshot: Sendable {
    let productID: String
    let isRevoked: Bool
    let expirationDate: Date?
    let isIntroductoryOffer: Bool
    let gracePeriodExpirationDate: Date?
}

/// Sendable summary of a purchase result. Decouples `applyPurchaseOutcome`
/// from `Product.PurchaseResult` (non-constructible in tests).
enum PurchaseFlowOutcome: Sendable {
    case completed
    case userCancelled
    case pending
    case unknown
}

/// Aggregated entitlement state, computed from a list of `EntitlementSnapshot`s.
struct AggregatedEntitlement: Sendable {
    let isActive: Bool
    let isTrial: Bool
    let isGracePeriod: Bool
    let productID: String?
    let expirationDate: Date?
}

// MARK: - Test Seam Protocols

protocol StoreKitProductLoading: Sendable {
    func loadProducts(ids: Set<String>) async throws -> [Product]
}

struct DefaultStoreKitProductLoader: StoreKitProductLoading {
    func loadProducts(ids: Set<String>) async throws -> [Product] {
        try await Product.products(for: ids)
    }
}

protocol PurchaseExecuting: Sendable {
    /// Executes a StoreKit purchase and translates the result into a
    /// `PurchaseFlowOutcome` plus (in production) the underlying Transaction
    /// so the caller can `finish()` it. Throws on unverified results.
    func executePurchase(_ product: Product) async throws -> (PurchaseFlowOutcome, Transaction?)
}

struct DefaultPurchaseExecutor: PurchaseExecuting {
    func executePurchase(_ product: Product) async throws -> (PurchaseFlowOutcome, Transaction?) {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                return (.completed, transaction)
            case .unverified(_, let error):
                throw error
            }
        case .userCancelled:
            return (.userCancelled, nil)
        case .pending:
            return (.pending, nil)
        @unknown default:
            return (.unknown, nil)
        }
    }
}

protocol EntitlementSnapshotting: Sendable {
    /// Iterates all current entitlements, projecting each verified one into
    /// a Sendable snapshot. Tests return canned arrays; production uses real
    /// `Transaction.currentEntitlements`.
    func currentEntitlements() async -> [EntitlementSnapshot]
}

struct DefaultEntitlementProvider: EntitlementSnapshotting {
    func currentEntitlements() async -> [EntitlementSnapshot] {
        var snapshots: [EntitlementSnapshot] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            // Look up grace-period expiration via renewal info, if available.
            var gracePeriodExpirationDate: Date? = nil
            if let products = try? await Product.products(for: [transaction.productID]),
               let subscription = products.first?.subscription,
               let status = try? await subscription.status.first,
               case .verified(let info) = status.renewalInfo {
                gracePeriodExpirationDate = info.gracePeriodExpirationDate
            }

            snapshots.append(EntitlementSnapshot(
                productID: transaction.productID,
                isRevoked: transaction.revocationDate != nil,
                expirationDate: transaction.expirationDate,
                isIntroductoryOffer: transaction.offerType == .introductory,
                gracePeriodExpirationDate: gracePeriodExpirationDate
            ))
        }
        return snapshots
    }
}

@MainActor
@Observable
final class SubscriptionManager {

    // MARK: - Product IDs

    enum ProductID: String, CaseIterable {
        case weekly  = "com.phonecare.premium.weekly"
        case monthly = "com.phonecare.premium.monthly"
        case annual  = "com.phonecare.premium.annual"
        // Future plan tiers (safe to ship before products are configured in App Store Connect).
        case family5 = "com.phonecare.premium.family5"
        case familyPlus = "com.phonecare.premium.familyplus"
    }

    // MARK: - Published State

    private(set) var products: [Product] = []
    private(set) var isPremium: Bool = false
    private(set) var isInTrial: Bool = false
    private(set) var currentProductID: String?
    private(set) var expirationDate: Date?
    private(set) var isInGracePeriod: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var purchaseError: String?

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhoneCare", category: "SubscriptionManager")
    private let productLoader: StoreKitProductLoading
    private let purchaseExecutor: PurchaseExecuting
    private let entitlementProvider: EntitlementSnapshotting

    private static let isPremiumKey = "PhoneCare_isPremium"
    #if DEBUG
    private static let debugPremiumBypassKey = "PhoneCare_debugPremiumBypass"
    #endif

    var hasPremiumAccess: Bool {
        #if DEBUG
        isPremium || debugPremiumBypassEnabled
        #else
        isPremium
        #endif
    }

    #if DEBUG
    var debugPremiumBypassEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.debugPremiumBypassKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.debugPremiumBypassKey)
            // Reflect instantly in UI while preserving entitlement state.
            isPremium = UserDefaults.standard.bool(forKey: Self.isPremiumKey) || newValue
        }
    }
    #endif

    // MARK: - Init

    init(
        productLoader: StoreKitProductLoading = DefaultStoreKitProductLoader(),
        purchaseExecutor: PurchaseExecuting = DefaultPurchaseExecutor(),
        entitlementProvider: EntitlementSnapshotting = DefaultEntitlementProvider()
    ) {
        self.productLoader = productLoader
        self.purchaseExecutor = purchaseExecutor
        self.entitlementProvider = entitlementProvider
        // Restore cached premium state for instant UI.
        let cachedPremium = UserDefaults.standard.bool(forKey: Self.isPremiumKey)
        #if DEBUG
        isPremium = cachedPremium || UserDefaults.standard.bool(forKey: Self.debugPremiumBypassKey)
        #else
        isPremium = cachedPremium
        #endif
    }

    // MARK: - Transaction Listener

    func startTransactionListener() {
        transactionListener?.cancel()
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let ids = ProductID.allCases.map(\.rawValue)
            let storeProducts = try await productLoader.loadProducts(ids: Set(ids))
            products = storeProducts.sorted { $0.price < $1.price }
            logger.info("Loaded \(storeProducts.count) products.")
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ product: Product) async throws -> Transaction? {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        let (outcome, transaction) = try await purchaseExecutor.executePurchase(product)
        return await applyPurchaseOutcome(outcome, transaction: transaction)
    }

    /// Internal — handles the post-IO state transition. Tests synthesize a
    /// `PurchaseFlowOutcome` and pass `transaction: nil` to bypass `Transaction`'s
    /// non-constructibility while still exercising the state-update logic.
    @discardableResult
    func applyPurchaseOutcome(
        _ outcome: PurchaseFlowOutcome,
        transaction: Transaction? = nil
    ) async -> Transaction? {
        switch outcome {
        case .completed:
            await transaction?.finish()
            await checkEntitlement()
            logger.info("Purchase completed.")
            return transaction
        case .userCancelled:
            logger.info("Purchase cancelled by user.")
            return nil
        case .pending:
            logger.info("Purchase pending approval.")
            return nil
        case .unknown:
            logger.warning("Unknown purchase result.")
            return nil
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await checkEntitlement()
            logger.info("Restore completed.")
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement Check

    func checkEntitlement() async {
        let snapshots = await entitlementProvider.currentEntitlements()
        let aggregated = aggregateEntitlements(snapshots)
        applyEntitlement(
            isActive: aggregated.isActive,
            isTrial: aggregated.isTrial,
            isGracePeriod: aggregated.isGracePeriod,
            productID: aggregated.productID,
            expiration: aggregated.expirationDate
        )
    }

    /// Internal — pure aggregation of entitlement snapshots. Tests call this
    /// directly with synthetic snapshots.
    func aggregateEntitlements(_ snapshots: [EntitlementSnapshot]) -> AggregatedEntitlement {
        var foundActive = false
        var trialActive = false
        var gracePeriod = false
        var activeProductID: String?
        var activeExpiration: Date?

        for snapshot in snapshots {
            // Only consider our product IDs.
            guard ProductID(rawValue: snapshot.productID) != nil else { continue }
            // Skip revoked entitlements.
            guard !snapshot.isRevoked else { continue }

            foundActive = true
            activeProductID = snapshot.productID
            activeExpiration = snapshot.expirationDate
            if snapshot.isIntroductoryOffer { trialActive = true }
            if snapshot.gracePeriodExpirationDate != nil { gracePeriod = true }
        }

        return AggregatedEntitlement(
            isActive: foundActive,
            isTrial: trialActive,
            isGracePeriod: gracePeriod,
            productID: activeProductID,
            expirationDate: activeExpiration
        )
    }

    private func applyEntitlement(
        isActive: Bool,
        isTrial: Bool,
        isGracePeriod: Bool,
        productID: String?,
        expiration: Date?
    ) {
        currentProductID = productID
        expirationDate = expiration
        isInTrial = isTrial
        isInGracePeriod = isGracePeriod

        let newIsPremium: Bool
        #if DEBUG
        newIsPremium = isActive || debugPremiumBypassEnabled
        #else
        newIsPremium = isActive
        #endif

        // Persist BEFORE in-memory mutation so a process kill between the two
        // writes cannot leave UserDefaults stale relative to in-memory state.
        UserDefaults.standard.set(newIsPremium, forKey: Self.isPremiumKey)
        isPremium = newIsPremium
    }

    // MARK: - Helpers

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(transactionResult) else { return }
        await transaction.finish()
        await checkEntitlement()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Formatting Helpers

    func displayPrice(for product: Product) -> String {
        product.displayPrice
    }

    func periodLabel(for product: Product) -> String {
        guard let subscription = product.subscription else { return "" }
        switch subscription.subscriptionPeriod.unit {
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        case .day:   return "day"
        @unknown default: return ""
        }
    }
}
