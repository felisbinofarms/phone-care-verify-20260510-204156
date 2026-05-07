import SwiftUI

struct PaywallBottomSheet: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel = PaywallViewModel()

    var contextualBenefit: String?
    var trigger: PaywallViewModel.Trigger = .userInitiated
    @State private var showComparePlans = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.pcBorder)
                .frame(width: 36, height: 5)
                .padding(.top, PCTheme.Spacing.sm)
                .voiceOverHidden()

            ScrollView {
                VStack(spacing: PCTheme.Spacing.lg) {
                    // Header
                    headerSection

                    // Benefits
                    benefitsSection

                    // Product cards
                    productsSection

                    // Competitor comparison
                    competitorComparisonSection

                    // Compare plans (expandable)
                    comparePlansSection

                    // Error
                    if let error = viewModel.purchaseError {
                        Text(error)
                            .typography(.footnote, color: .pcWarning)
                            .multilineTextAlignment(.center)
                    }

                    // Purchase button
                    purchaseButton

                    // Restore + Legal
                    footerSection
                }
                .padding(.horizontal, PCTheme.Spacing.md)
                .padding(.top, PCTheme.Spacing.lg)
                .padding(.bottom, PCTheme.Spacing.xl)
            }
        }
        .background(Color.pcBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            await viewModel.load(subscriptionManager: subscriptionManager)
            PaywallViewModel.recordShown(for: trigger)
        }
        .onChange(of: viewModel.purchaseComplete) { _, complete in
            if complete { dismiss() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: PCTheme.Spacing.md) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.pcAccent)
                .voiceOverHidden()

            Text("PhoneCare Premium does the heavy lifting.")
                .typography(.title2)
                .multilineTextAlignment(.center)

            if let benefit = contextualBenefit {
                Text(benefit)
                    .typography(.subheadline, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("All the heavy work, in one tap.")
                    .typography(.subheadline, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            benefitRow(icon: "photo.on.rectangle", text: "Batch cleanups for photos and storage")
            benefitRow(icon: "person.2", text: "Merge duplicate contacts in one tap")
            benefitRow(icon: "chart.xyaxis.line", text: "Battery history beyond 24 hours")
            benefitRow(icon: "wand.and.stars", text: "Step-by-step guided cleanup flows")
            benefitRow(icon: "bell.badge", text: "Smart reminders that keep your phone tidy")
        }
        .padding(.vertical, PCTheme.Spacing.sm)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: PCTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.pcAccent)
                .frame(width: 24)
                .voiceOverHidden()

            Text(text)
                .typography(.subheadline)

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Products

    @ViewBuilder
    private var productsSection: some View {
        if viewModel.isLoadingProducts {
            ProgressView("Loading plans…")
                .padding(.vertical, PCTheme.Spacing.lg)
        } else if viewModel.products.isEmpty {
            VStack(spacing: PCTheme.Spacing.md) {
                Text("We couldn't load subscription plans. Please check your internet connection and try again.")
                    .typography(.subheadline, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task {
                        await viewModel.load(subscriptionManager: subscriptionManager)
                    }
                }
                .textLinkStyle()
                .accessibleTapTarget()
                .accessibilityLabel("Try again")
            }
            .padding(.vertical, PCTheme.Spacing.lg)
        } else {
            HStack(spacing: PCTheme.Spacing.sm) {
                ForEach(viewModel.products, id: \.id) { product in
                    ProductCardView(
                        product: product,
                        isSelected: viewModel.selectedProduct?.id == product.id,
                        savingsLabel: viewModel.savingsLabel(for: product),
                        trialLabel: viewModel.trialLabel(for: product),
                        periodLabel: subscriptionManager.periodLabel(for: product),
                        weeklyEquivalentLabel: product.weeklyEquivalentLabel,
                        onSelect: { viewModel.selectedProduct = product }
                    )
                }
            }
        }
    }

    // MARK: - Competitor Comparison

    private var competitorComparisonSection: some View {
        HStack(spacing: PCTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.pcTextSecondary)
                .accessibilityHidden(true)

            Text(viewModel.competitorComparisonLabel())
                .typography(.footnote, color: .pcTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(PCTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: PCTheme.Radius.sm)
                .fill(Color.pcSurface)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Compare Plans

    private var comparePlansSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showComparePlans.toggle()
                }
            } label: {
                HStack {
                    Text("Compare plans")
                        .typography(.subheadline, color: .pcPrimary)
                    Spacer()
                    Image(systemName: showComparePlans ? "chevron.up" : "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(Color.pcTextSecondary)
                }
            }
            .accessibilityLabel("Compare plans")
            .accessibilityHint(showComparePlans ? "Collapse plan comparison" : "Expand plan comparison")

            if showComparePlans {
                VStack(spacing: PCTheme.Spacing.xs) {
                    HStack {
                        Text("Plan")
                            .typography(.caption, color: .pcTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Per year")
                            .typography(.caption, color: .pcTextSecondary)
                    }
                    Divider()
                    ForEach(viewModel.products, id: \.id) { product in
                        HStack {
                            Text(subscriptionManager.periodLabel(for: product).capitalized)
                                .typography(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(product.annualCostLabel ?? product.displayPrice)
                                .typography(.subheadline, color: .pcAccent)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(PCTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: PCTheme.Radius.sm)
                        .fill(Color.pcSurface)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task {
                await viewModel.purchase(subscriptionManager: subscriptionManager)
            }
        } label: {
            if viewModel.isPurchasing {
                ProgressView()
                    .tint(.white)
            } else {
                Text(purchaseButtonTitle)
            }
        }
        .primaryCTAStyle()
        .disabled(viewModel.isPurchasing || viewModel.selectedProduct == nil)
        .accessibilityLabel(purchaseButtonAccessibilityLabel)
    }

    private var purchaseButtonTitle: String {
        guard let product = viewModel.selectedProduct else { return "Select a Plan" }
        if viewModel.hasFreeTrial(for: product) {
            return "Start Free Trial"
        }
        return "Subscribe for \(product.displayPrice)"
    }

    private var purchaseButtonAccessibilityLabel: String {
        guard let product = viewModel.selectedProduct else { return "Select a plan." }
        let period = subscriptionManager.periodLabel(for: product)
        if viewModel.hasFreeTrial(for: product),
           let trial = viewModel.trialLabel(for: product) {
            return "Start \(trial). After the trial you will be charged \(product.displayPrice) per \(period). Cancel anytime."
        }
        return "Subscribe for \(product.displayPrice) per \(period)."
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: PCTheme.Spacing.sm) {
            Button("Restore Purchases") {
                Task {
                    await viewModel.restore(subscriptionManager: subscriptionManager)
                }
            }
            .textLinkStyle()
            .accessibleTapTarget()
            .accessibilityLabel("Restore Purchases")

            Text("Payment will be charged to your Apple ID. Subscription automatically renews unless canceled at least 24 hours before the end of the current period.")
                .typography(.caption, color: .pcTextSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: PCTheme.Spacing.md) {
                Button("Terms of Use") {
                        if let url = PrivacyManifesto.termsOfServiceURL {
                            UIApplication.shared.open(url)
                        }
                }
                .textLinkStyle()
                .font(.caption)
                .accessibilityLabel("Terms of Service")

                Button("Privacy Policy") {
                        if let url = PrivacyManifesto.privacyPolicyURL {
                            UIApplication.shared.open(url)
                        }
                }
                .textLinkStyle()
                .font(.caption)
                .accessibilityLabel("Privacy Policy")
            }

            // Dismiss
            Button("Not Now") {
                dismiss()
            }
            .textLinkStyle()
            .accessibleTapTarget()
            .padding(.top, PCTheme.Spacing.sm)
        }
    }
}
