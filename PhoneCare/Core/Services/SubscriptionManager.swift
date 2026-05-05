import Foundation
import StoreKit
import OSLog

protocol StoreKitProductLoading: Sendable {
    func loadProducts(ids: Set<String>) async throws -> [Product]
}

struct DefaultStoreKitProductLoader: StoreKitProductLoading {
    func loadProducts(ids: Set<String>) async throws -> [Product] {
        try await Product.products(for: ids)
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

    init(productLoader: StoreKitProductLoading = DefaultStoreKitProductLoader()) {
        self.productLoader = productLoader
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

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await checkEntitlement()
            logger.info("Purchase successful: \(product.id)")
            return transaction

        case .userCancelled:
            logger.info("Purchase cancelled by user.")
            return nil

        case .pending:
            logger.info("Purchase pending approval.")
            return nil

        @unknown default:
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
        var foundActive = false
        var trialActive = false
        var gracePeriod = false
        var activeProductID: String?
        var activeExpiration: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            // Only consider our product IDs.
            guard ProductID(rawValue: transaction.productID) != nil else { continue }

            if transaction.revocationDate == nil {
                foundActive = true
                activeProductID = transaction.productID

                if let offerType = transaction.offerType, offerType == .introductory {
                    trialActive = true
                }

                activeExpiration = transaction.expirationDate

                // Check grace period via renewal info.
                if let renewalInfo = await renewalInfo(for: transaction.productID) {
                    if renewalInfo.gracePeriodExpirationDate != nil {
                        gracePeriod = true
                    }
                }
            }
        }

        applyEntitlement(
            isActive: foundActive,
            isTrial: trialActive,
            isGracePeriod: gracePeriod,
            productID: activeProductID,
            expiration: activeExpiration
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
        #if DEBUG
        isPremium = isActive || debugPremiumBypassEnabled
        #else
        isPremium = isActive
        #endif
        UserDefaults.standard.set(isPremium, forKey: Self.isPremiumKey)
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

    private func renewalInfo(for productID: String) async -> Product.SubscriptionInfo.RenewalInfo? {
        guard let product = products.first(where: { $0.id == productID }),
              let subscription = product.subscription else {
            return nil
        }
        guard let status = try? await subscription.status.first,
              case .verified(let info) = status.renewalInfo else {
            return nil
        }
        return info
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
