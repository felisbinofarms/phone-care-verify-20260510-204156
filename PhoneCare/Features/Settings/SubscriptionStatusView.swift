import SwiftUI

struct SubscriptionStatusView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var showPaywall = false

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.md) {
                HStack {
                    Image(systemName: subscriptionManager.hasPremiumAccess ? "star.circle.fill" : "star.circle")
                        .font(.title2)
                        .foregroundStyle(Color.pcAccent)
                        .voiceOverHidden()

                    VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                        Text(subscriptionManager.hasPremiumAccess ? "Premium" : "Free Plan")
                            .typography(.headline)

                        if subscriptionManager.hasPremiumAccess {
                            #if DEBUG
                            if subscriptionManager.debugPremiumBypassEnabled {
                                Text("Test user access active")
                                    .typography(.footnote, color: .pcAccent)
                            }
                            #endif
                            if subscriptionManager.isInTrial {
                                Text("Free trial active")
                                    .typography(.footnote, color: .pcAccent)
                            }
                            if let expDate = subscriptionManager.expirationDate {
                                Text("Renews \(expDate.relativeFormatted())")
                                    .typography(.footnote, color: .pcTextSecondary)
                            }
                        } else {
                            Text("Upgrade so PhoneCare can do the heavy lifting.")
                                .typography(.footnote, color: .pcTextSecondary)
                        }
                    }

                    Spacer()
                }

                if subscriptionManager.hasPremiumAccess {
                    Divider()
                        .foregroundStyle(Color.pcBorder)

                    Button("Manage Subscription") {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .textLinkStyle()
                    .accessibleTapTarget()

                    Button("Restore Purchases") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .textLinkStyle()
                    .accessibleTapTarget()

                    #if DEBUG
                    Divider()
                        .foregroundStyle(Color.pcBorder)

                    Toggle("Test user premium bypass", isOn: Binding(
                        get: { subscriptionManager.debugPremiumBypassEnabled },
                        set: { subscriptionManager.debugPremiumBypassEnabled = $0 }
                    ))
                    .typography(.subheadline)
                    .tint(Color.pcAccent)
                    #endif
                } else {
                    Button("Upgrade to Premium") {
                        showPaywall = true
                    }
                    .primaryCTAStyle()

                    Button("Restore Purchases") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .textLinkStyle()
                    .accessibleTapTarget()

                    #if DEBUG
                    Toggle("Test user premium bypass", isOn: Binding(
                        get: { subscriptionManager.debugPremiumBypassEnabled },
                        set: { subscriptionManager.debugPremiumBypassEnabled = $0 }
                    ))
                    .typography(.subheadline)
                    .tint(Color.pcAccent)
                    #endif
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallBottomSheet()
        }
        .accessibilityElement(children: .contain)
    }
}
