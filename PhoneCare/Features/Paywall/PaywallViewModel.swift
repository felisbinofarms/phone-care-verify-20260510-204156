import SwiftUI
import StoreKit

@MainActor
@Observable
final class PaywallViewModel {

    // MARK: - State

    private(set) var products: [Product] = []
    var selectedProduct: Product?
    private(set) var isPurchasing: Bool = false
    private(set) var isLoadingProducts: Bool = false
    private(set) var purchaseError: String?
    private(set) var purchaseComplete: Bool = false

    // MARK: - Re-show Limiting

    private static let lastShownKey = "PaywallLastShownDate"
    private static let reshowInterval: TimeInterval = 7 * 24 * 3600 // 1 week

    var shouldShow: Bool {
        guard let lastShown = UserDefaults.standard.object(forKey: Self.lastShownKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastShown) >= Self.reshowInterval
    }

    func recordShown() {
        UserDefaults.standard.set(Date(), forKey: Self.lastShownKey)
    }

    // MARK: - Load

    func load(subscriptionManager: SubscriptionManager) async {
        isLoadingProducts = true
        if subscriptionManager.products.isEmpty {
            await subscriptionManager.loadProducts()
        }
        products = subscriptionManager.products
        isLoadingProducts = false
        // Default select the monthly plan, falling back to the cheapest available product
        // if no monthly SKU has loaded. Looking up by SubscriptionPeriod is robust to
        // future SKU additions (e.g. family plans) that would shift array indices.
        if selectedProduct == nil {
            selectedProduct = products.first(where: { $0.subscription?.subscriptionPeriod.unit == .month })
                ?? products.first
        }
    }

    // MARK: - Purchase

    func purchase(subscriptionManager: SubscriptionManager) async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        purchaseError = nil

        do {
            let transaction = try await subscriptionManager.purchase(product)
            if transaction != nil {
                purchaseComplete = true
            }
        } catch {
            purchaseError = "Something went wrong. Please try again."
        }

        isPurchasing = false
    }

    // MARK: - Restore

    func restore(subscriptionManager: SubscriptionManager) async {
        isPurchasing = true
        await subscriptionManager.restorePurchases()
        if subscriptionManager.isPremium {
            purchaseComplete = true
        }
        isPurchasing = false
    }

    // MARK: - Helpers

    func savingsLabel(for product: Product) -> String? {
        guard let subscription = product.subscription,
              let weekly = products.first(where: {
                  $0.subscription?.subscriptionPeriod.unit == .week
              }) else {
            return nil
        }

        let weeklyPricePerYear = weekly.price * 52
        let productPricePerYear: Decimal
        switch subscription.subscriptionPeriod.unit {
        case .month:
            productPricePerYear = product.price * 12
        case .year:
            productPricePerYear = product.price
        default:
            return nil
        }

        guard weeklyPricePerYear > 0 else { return nil }
        let savings = ((weeklyPricePerYear - productPricePerYear) / weeklyPricePerYear) * 100
        let savingsInt = NSDecimalNumber(decimal: savings).intValue
        guard savingsInt > 0 else { return nil }
        return "Save \(savingsInt)%"
    }

    func hasFreeTrial(for product: Product) -> Bool {
        guard let subscription = product.subscription else { return false }
        return subscription.introductoryOffer?.paymentMode == .freeTrial
    }

    func trialLabel(for product: Product) -> String? {
        guard let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            return nil
        }
        let period = offer.period
        switch period.unit {
        case .day:
            return "\(period.value)-day free trial"
        case .week:
            return "\(period.value)-week free trial"
        case .month:
            return "\(period.value)-month free trial"
        case .year:
            return "\(period.value)-year free trial"
        @unknown default:
            return "Free trial"
        }
    }

    // MARK: - Pricing Framing Helpers

    func competitorComparisonLabel() -> String {
        PaywallPricingContent.comparisonMessage(for: products)
    }
}

enum PaywallPricingContent {
    static let competitorAnnualCostText = "over $400/year"

    static func comparisonMessage(for products: [Product]) -> String {
        guard let annualPlan = products.first(where: { $0.isAnnualPlan }) else {
            return "Some phone cleaner apps cost \(competitorAnnualCostText). PhoneCare keeps pricing straightforward."
        }

        return "Some phone cleaner apps cost \(competitorAnnualCostText). PhoneCare annual plan is \(annualPlan.displayPrice)/year."
    }
}

extension Product {
    var isAnnualPlan: Bool {
        subscription?.subscriptionPeriod.unit == .year
    }

    var weeklyEquivalentLabel: String? {
        guard let subscription, subscription.subscriptionPeriod.unit == .year else { return nil }
        let weeksInPlan = Decimal(subscription.subscriptionPeriod.value * 52)
        let weeklyPrice = price / weeksInPlan
        let formatted = weeklyPrice.formatted(priceFormatStyle)
        return "That's just \(formatted)/week"
    }

    var annualCostLabel: String? {
        guard let subscription else { return nil }
        let periodValue = Decimal(subscription.subscriptionPeriod.value)
        guard periodValue > 0 else { return nil }
        let annualPrice: Decimal
        switch subscription.subscriptionPeriod.unit {
        case .week:
            annualPrice = (price * 52) / periodValue
        case .month:
            annualPrice = (price * 12) / periodValue
        case .year:
            annualPrice = price / periodValue
        default:
            return nil
        }

        let formatted = annualPrice.formatted(priceFormatStyle)
        return "\(formatted)/year"
    }
}
