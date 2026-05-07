import SwiftUI

struct HonestAlternativeView: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeaderView(
                title: "Why PhoneCare?",
                subtitle: "There are many phone cleaner apps out there. Here is what makes us different.",
                onBack: onBack
            )

            ScrollView {
                VStack(spacing: PCTheme.Spacing.lg) {
                    // Pricing comparison card
                    pricingComparisonCard

                    // Honest differentiators
                    differentiatorsList
                }
                .padding(.horizontal, PCTheme.Spacing.md)
                .padding(.top, PCTheme.Spacing.lg)
                .padding(.bottom, PCTheme.Spacing.lg)
            }

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Sounds good")
            }
            .primaryCTAStyle()
            .padding(.horizontal, PCTheme.Spacing.lg)
            .padding(.bottom, PCTheme.Spacing.lg)
        }
    }

    // MARK: - Pricing Comparison Card

    private var pricingComparisonCard: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("App")
                    .typography(.footnote, color: .pcTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Per year")
                    .typography(.footnote, color: .pcTextSecondary)
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.vertical, PCTheme.Spacing.sm)

            Divider()
                .padding(.horizontal, PCTheme.Spacing.md)

            // Competitor row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Popular cleaner apps")
                        .typography(.subheadline)
                    Text("e.g. Cleanup+, Phone Cleaner Pro")
                        .typography(.caption, color: .pcTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("$415")
                    .typography(.headline, color: .pcTextSecondary)
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.vertical, PCTheme.Spacing.sm)

            Divider()
                .padding(.horizontal, PCTheme.Spacing.md)

            // PhoneCare row, highlighted
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PhoneCare")
                        .typography(.subheadline)
                    Text("Everything included, nothing hidden")
                        .typography(.caption, color: .pcTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("$19.99")
                    .typography(.headline, color: .pcAccent)
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.vertical, PCTheme.Spacing.sm)
            .background(Color.pcAccent.opacity(0.06))
        }
        .background(
            RoundedRectangle(cornerRadius: PCTheme.Radius.lg)
                .fill(Color.pcSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PCTheme.Radius.lg)
                .stroke(Color.pcBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pricing comparison. Popular cleaner apps cost around $415 per year. PhoneCare costs $19.99 per year.")
    }

    // MARK: - Differentiators

    private var differentiatorsList: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.md) {
            differentiatorRow(
                icon: "checkmark.seal.fill",
                text: "7-day free trial on monthly and annual",
                detail: "Try everything before you pay. No credit card charges during your trial."
            )
            differentiatorRow(
                icon: "arrow.uturn.backward.circle.fill",
                text: "Undo button on every action",
                detail: "Changed your mind? Every delete and merge can be undone within 30 days."
            )
            differentiatorRow(
                icon: "lock.shield.fill",
                text: "Zero trackers, everything stays on your phone",
                detail: "We do not collect, upload, or share your data. All scans happen on-device."
            )
        }
    }

    private func differentiatorRow(icon: String, text: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: PCTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.pcAccent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                Text(text)
                    .typography(.headline)

                Text(detail)
                    .typography(.subheadline, color: .pcTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
