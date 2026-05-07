import SwiftUI
import StoreKit

struct PaywallOnboardingView: View {
    let subscriptionManager: SubscriptionManager
    let onContinue: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var selectedProductID: String?
    @State private var isPurchasing = false
    @State private var isLoadingProducts = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: PCTheme.Spacing.lg) {
                    HStack {
                        Button {
                            onBack()
                        } label: {
                            HStack(spacing: PCTheme.Spacing.xs) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.medium))
                                Text("Back")
                                    .font(.body)
                            }
                            .foregroundStyle(Color.pcPrimary)
                        }
                        .accessibleTapTarget()
                        .accessibilityLabel("Go back")

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, PCTheme.Spacing.md)

                    // Header
                    VStack(spacing: PCTheme.Spacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.pcAccent)
                            .accessibilityHidden(true)

                        Text("PhoneCare Premium does the heavy lifting.")
                            .typography(.title1)
                            .multilineTextAlignment(.center)

                        Text("All the heavy work, in one tap.")
                            .typography(.subheadline, color: .pcTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, PCTheme.Spacing.lg)

                    // Benefits
                    VStack(alignment: .leading, spacing: PCTheme.Spacing.md) {
                        BenefitRow(icon: "photo.on.rectangle.fill", text: "Batch cleanups for photos and storage")
                        BenefitRow(icon: "person.2.fill", text: "Merge duplicate contacts in one tap")
                        BenefitRow(icon: "chart.line.uptrend.xyaxis", text: "Battery history beyond 24 hours")
                        BenefitRow(icon: "wand.and.stars", text: "Step-by-step guided cleanup flows")
                        BenefitRow(icon: "bell.badge", text: "Smart reminders that keep your phone tidy")
                    }
                    .padding(.horizontal, PCTheme.Spacing.md)

                    // Plan options
                    if isLoadingProducts {
                        ProgressView("Loading plans…")
                            .padding(.vertical, PCTheme.Spacing.lg)
                    } else if sortedProducts.isEmpty {
                        VStack(spacing: PCTheme.Spacing.md) {
                            Text("We couldn't load subscription plans. Please check your internet connection and try again.")
                                .typography(.subheadline, color: .pcTextSecondary)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                Task { await loadProductsWithState() }
                            }
                            .textLinkStyle()
                            .accessibleTapTarget()
                        }
                        .padding(.horizontal, PCTheme.Spacing.md)
                        .padding(.vertical, PCTheme.Spacing.lg)
                    } else {
                        VStack(spacing: PCTheme.Spacing.sm) {
                            ForEach(sortedProducts, id: \.id) { product in
                                PlanOptionRow(
                                    product: product,
                                    periodLabel: subscriptionManager.periodLabel(for: product),
                                    weeklyEquivalentLabel: product.weeklyEquivalentLabel,
                                    isSelected: selectedProductID == product.id,
                                    isRecommended: isAnnual(product)
                                ) {
                                    selectedProductID = product.id
                                }
                            }
                        }
                        .padding(.horizontal, PCTheme.Spacing.md)
                    }

                    // Competitor comparison
                    HStack(spacing: PCTheme.Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.pcTextSecondary)
                            .accessibilityHidden(true)
                        Text(PaywallPricingContent.comparisonMessage(for: sortedProducts))
                            .typography(.footnote, color: .pcTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(PCTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: PCTheme.Radius.sm)
                            .fill(Color.pcSurface)
                    )
                    .padding(.horizontal, PCTheme.Spacing.md)
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, PCTheme.Spacing.md)
            }

            // Bottom actions
            VStack(spacing: PCTheme.Spacing.md) {
                // Purchase CTA
                Button {
                    Task { await handlePurchase() }
                } label: {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(purchaseButtonTitle)
                    }
                }
                .primaryCTAStyle()
                .disabled(selectedProductID == nil || isPurchasing)

                // Not now -- ALWAYS visible, same size as CTA
                Button {
                    onSkip()
                } label: {
                    Text("Not now")
                }
                .textLinkStyle()
                .frame(minHeight: PCTheme.HitArea.primaryCTA)

                // Restore + Terms
                HStack(spacing: PCTheme.Spacing.md) {
                    Button("Restore Purchases") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if subscriptionManager.isPremium {
                                onContinue()
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.pcTextSecondary)

                    Text("|")
                        .font(.caption)
                        .foregroundStyle(Color.pcBorder)

                    Button("Terms") {
                        if let url = PrivacyManifesto.termsOfServiceURL {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.pcTextSecondary)

                    Text("|")
                        .font(.caption)
                        .foregroundStyle(Color.pcBorder)

                    Button("Privacy") {
                        if let url = PrivacyManifesto.privacyPolicyURL {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.pcTextSecondary)
                }
                .padding(.bottom, PCTheme.Spacing.sm)
            }
            .padding(.horizontal, PCTheme.Spacing.lg)
            .padding(.bottom, PCTheme.Spacing.md)
        }
        .task {
            await loadProductsWithState()
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Helpers

    private var sortedProducts: [Product] {
        subscriptionManager.products.sorted { $0.price < $1.price }
    }

    private func isAnnual(_ product: Product) -> Bool {
        product.subscription?.subscriptionPeriod.unit == .year
    }

    private func loadProductsWithState() async {
        isLoadingProducts = true
        if subscriptionManager.products.isEmpty {
            await subscriptionManager.loadProducts()
        }
        isLoadingProducts = false
        // Pre-select annual plan
        selectedProductID = sortedProducts.first(where: { isAnnual($0) })?.id
            ?? sortedProducts.last?.id
    }

    private var purchaseButtonTitle: String {
        guard let id = selectedProductID,
              let product = subscriptionManager.products.first(where: { $0.id == id }) else {
            return "Subscribe"
        }
        if product.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Start free trial"
        }
        return "Subscribe for \(product.displayPrice)"
    }

    private func handlePurchase() async {
        guard let productID = selectedProductID,
              let product = subscriptionManager.products.first(where: { $0.id == productID }) else {
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let transaction = try await subscriptionManager.purchase(product)
            if transaction != nil {
                onContinue()
            }
        } catch {
            errorMessage = "We could not complete your purchase. Please try again."
            showError = true
        }
    }
}

// MARK: - Benefit Row

private struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: PCTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.pcAccent)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(text)
                .typography(.body)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan Option Row

private struct PlanOptionRow: View {
    let product: Product
    let periodLabel: String
    let weeklyEquivalentLabel: String?
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PCTheme.Spacing.md) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.pcAccent : Color.pcBorder)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: PCTheme.Spacing.sm) {
                        Text(periodLabel.capitalized)
                            .typography(.headline)

                        if isRecommended {
                            Text("Best Value")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, PCTheme.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.pcAccent))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .typography(.headline, color: .pcAccent)
                    if let weekly = weeklyEquivalentLabel {
                        Text(weekly)
                            .typography(.caption, color: .pcTextSecondary)
                    }
                }
            }
            .padding(PCTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: PCTheme.Radius.md)
                    .fill(isSelected ? Color.pcMintTint : Color.pcSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PCTheme.Radius.md)
                    .strokeBorder(
                        isSelected ? Color.pcAccent : Color.pcBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel({
            var label = "\(periodLabel) plan, \(product.displayPrice)"
            if let weekly = weeklyEquivalentLabel {
                label += ", \(weekly)"
            }
            return label
        }())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isRecommended ? "Best value" : "")
    }
}
