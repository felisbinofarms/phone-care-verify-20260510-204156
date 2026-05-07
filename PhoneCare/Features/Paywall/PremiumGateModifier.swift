import SwiftUI

struct PremiumGateModifier: ViewModifier {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    let action: () -> Void

    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if subscriptionManager.isPremium {
                    action()
                } else {
                    showPaywall = true
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallBottomSheet(trigger: .gatedCTA)
            }
    }
}

extension View {
    /// If premium, runs the action. If not, shows the paywall bottom sheet.
    func premiumRequired(action: @escaping () -> Void) -> some View {
        modifier(PremiumGateModifier(action: action))
    }
}
