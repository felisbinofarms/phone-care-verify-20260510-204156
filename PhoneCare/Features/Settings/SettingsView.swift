import SwiftUI

struct SettingsView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(AppState.self) private var appState
    @State private var viewModel = SettingsViewModel()
    @State private var showNotificationSaved = false
    @State private var notificationSaveFeedbackID = 0

    var body: some View {
        ScrollView {
            VStack(spacing: PCTheme.Spacing.lg) {
                // Subscription
                subscriptionSection

                // Appearance
                appearanceSection

                // Notifications
                notificationsSection

                // Share with a friend
                giftAFriendSection

                // About
                aboutSection

                // Annual Report
                annualReportSection

                // Data & Privacy
                dataPrivacySection
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.top, PCTheme.Spacing.md)
            .padding(.bottom, PCTheme.Spacing.xl)
        }
        .background(Color.pcBackground)
        .accessibilityIdentifier("screen.settings")
        .navigationTitle("Settings")
        .onAppear {
            viewModel.load(dataManager: dataManager, appState: appState)
        }
        .task(id: notificationSaveFeedbackID) {
            guard notificationSaveFeedbackID > 0 else { return }
            let currentFeedbackID = notificationSaveFeedbackID
            try? await Task.sleep(for: .seconds(1.5))
            guard currentFeedbackID == notificationSaveFeedbackID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showNotificationSaved = false
            }
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Text("Subscription")
                .typography(.headline)
                .voiceOverHeading()

            SubscriptionStatusView()
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            AppearancePickerView(
                selectedMode: $viewModel.appearanceMode,
                onChange: {
                    viewModel.saveAppearance(appState: appState)
                }
            )
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.md) {
                Text("Notifications")
                    .typography(.headline)
                    .voiceOverHeading()

                Toggle("Weekly health check reminder", isOn: $viewModel.weeklyNotification)
                    .typography(.subheadline)
                    .tint(Color.pcAccent)
                    .accessibilityIdentifier("settings.notification.weekly")
                    .onChange(of: viewModel.weeklyNotification) { _, _ in
                        saveNotificationSettings()
                    }

                Divider().foregroundStyle(Color.pcBorder)

                Toggle("Duplicate photo alerts", isOn: $viewModel.duplicateAlerts)
                    .typography(.subheadline)
                    .tint(Color.pcAccent)
                    .accessibilityIdentifier("settings.notification.duplicates")
                    .onChange(of: viewModel.duplicateAlerts) { _, _ in
                        saveNotificationSettings()
                    }

                Divider().foregroundStyle(Color.pcBorder)

                Toggle("Show battery tips in app", isOn: $viewModel.batteryAlerts)
                    .typography(.subheadline)
                    .tint(Color.pcAccent)
                    .accessibilityIdentifier("settings.notification.battery")
                    .onChange(of: viewModel.batteryAlerts) { _, _ in
                        saveNotificationSettings()
                    }

                if showNotificationSaved {
                    Text("Changes saved")
                        .typography(.caption, color: .pcAccent)
                        .transition(.opacity)
                }
            }
        }
    }

    private func saveNotificationSettings() {
        viewModel.saveNotifications(dataManager: dataManager)
        notificationSaveFeedbackID += 1
        withAnimation(.easeInOut(duration: 0.2)) {
            showNotificationSaved = true
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        NavigationLink {
            AboutView(appVersion: viewModel.appVersion)
        } label: {
            CardView {
                HStack(spacing: PCTheme.Spacing.md) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(Color.pcPrimary)
                        .voiceOverHidden()

                    VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                        Text("About PhoneCare")
                            .typography(.subheadline)

                        Text("Version \(viewModel.appVersion)")
                            .typography(.footnote, color: .pcTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.pcTextSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.about")
        .accessibilityHint("Tap for app information, support, and legal links")
    }

    // MARK: - Data & Privacy

    private var dataPrivacySection: some View {
        NavigationLink {
            DataPrivacyView()
        } label: {
            CardView {
                HStack(spacing: PCTheme.Spacing.md) {
                    Image(systemName: "shield.checkered")
                        .font(.title3)
                        .foregroundStyle(Color.pcPrimary)
                        .voiceOverHidden()

                    VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                        Text(PrivacyManifesto.sectionTitle)
                            .typography(.subheadline)

                        Text(PrivacyManifesto.summaryText)
                            .typography(.footnote, color: .pcTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.pcTextSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.dataPrivacy")
        .accessibilityHint("Tap to read your privacy details and manage your app data")
    }

    // MARK: - Gift a Friend

    private var giftAFriendSection: some View {
        NavigationLink {
            GiftAFriendView()
        } label: {
            CardView {
                HStack(spacing: PCTheme.Spacing.md) {
                    Image(systemName: "gift.fill")
                        .font(.title3)
                        .foregroundStyle(Color.pcAccent)
                        .voiceOverHidden()

                    VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                        Text("Share with a Friend")
                            .typography(.subheadline)
                        Text("Know someone who could use honest phone care?")
                            .typography(.footnote, color: .pcTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.pcTextSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.giftAFriend")
        .accessibilityHint("Tap to share PhoneCare with a friend")
    }

    // MARK: - Annual Report

    private var annualReportSection: some View {
        let stats = (try? dataManager.fetch(CleanupStats.self))?.first ?? CleanupStats()
        return NavigationLink {
            AnnualReportView(stats: stats)
        } label: {
            CardView {
                HStack(spacing: PCTheme.Spacing.md) {
                    Image(systemName: "star.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.pcAccent)
                        .voiceOverHidden()

                    VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                        Text("Your Year with PhoneCare")
                            .typography(.subheadline)
                        Text("See everything you've accomplished")
                            .typography(.footnote, color: .pcTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.pcTextSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.annualReport")
        .accessibilityHint("Tap to view your annual health report")
    }
}
