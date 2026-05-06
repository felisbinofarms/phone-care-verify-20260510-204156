import SwiftUI

struct DashboardView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(AppState.self) private var appState

    @State private var viewModel = DashboardViewModel()
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: PCTheme.Spacing.lg) {
                // Health Score Ring
                healthScoreSection

                // Quick Wins
                QuickWinsSection(
                    quickWins: viewModel.quickWins,
                    isPremium: subscriptionManager.isPremium
                ) { win in
                    handleQuickWinTap(win)
                }

                // Feature Cards
                featureCardsSection

                // Last scan info
                if let date = viewModel.lastScanDate {
                    Text("Last checked \(date.relativeFormatted())")
                        .typography(.caption, color: .pcTextSecondary)
                        .padding(.bottom, PCTheme.Spacing.md)
                }
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.top, PCTheme.Spacing.md)
        }
        .background(Color.pcBackground)
        .accessibilityIdentifier("screen.dashboard")
        .navigationTitle("Phone Health")
        .refreshable {
            viewModel.refresh(dataManager: dataManager, permissionManager: permissionManager)
        }
        .onAppear {
            viewModel.refresh(dataManager: dataManager, permissionManager: permissionManager)
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if newTab == .home {
                viewModel.refresh(dataManager: dataManager, permissionManager: permissionManager)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallBottomSheet()
        }
    }

    // MARK: - Health Score

    private var healthScoreSection: some View {
        VStack(spacing: PCTheme.Spacing.sm) {
            HealthScoreRingView(score: viewModel.healthScore)

            if viewModel.healthScore == 0 && viewModel.lastScanDate == nil {
                Text("Scan your phone to see your health score")
                    .typography(.subheadline, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(healthSummaryText)
                    .typography(.subheadline, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, PCTheme.Spacing.sm)
    }

    private var healthSummaryText: String {
        let score = viewModel.healthScore
        if score >= 76 {
            return "Your phone is in great shape!"
        } else if score >= HealthScoreCalculator.goodThreshold {
            return "Your phone is doing well. A few things could help."
        } else {
            return "There are some things you can do to help your phone."
        }
    }

    // MARK: - Feature Cards

    private var featureCardsSection: some View {
        let displayCards = viewModel.cardOrder.filter { $0 != "healthScore" }

        return VStack(spacing: PCTheme.Spacing.md) {
            ForEach(displayCards, id: \.self) { key in
                featureCard(for: key)
            }
        }
    }

    @ViewBuilder
    private func featureCard(for key: String) -> some View {
        let destination = destinationForCard(key)
        NavigationLink {
            destination
        } label: {
            DashboardCardView(
                icon: viewModel.iconForCard(key),
                iconColor: .pcAccent,
                title: viewModel.titleForCard(key),
                status: viewModel.statusForCard(key),
                description: viewModel.descriptionForCard(key)
            ) {
                HStack {
                    Spacer()
                    Text("View Details")
                        .typography(.footnote, color: .pcPrimary)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.pcPrimary)
                }
                .accessibleTapTarget()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destinationForCard(_ key: String) -> some View {
        switch key {
        case "storage":
            StorageView()
        case "photos":
            PhotosView()
        case "contacts":
            ContactsView()
        case "battery":
            BatteryView()
        case "privacy":
            PrivacyView()
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func handleQuickWinTap(_ win: QuickWin) {
        guard subscriptionManager.isPremium else {
            showPaywall = true
            return
        }
        switch win.id {
        case "photos":
            appState.selectedTab = .photos
        case "storage":
            appState.selectedTab = .storage
        case "privacy":
            appState.selectedTab = .privacy
        default:
            break
        }
    }
}
