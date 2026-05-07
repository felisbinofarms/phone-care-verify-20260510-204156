import SwiftUI

struct BatteryView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var viewModel = BatteryViewModel()
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: PCTheme.Spacing.lg) {
                // Current level
                currentLevelSection

                // Quick stats row
                quickStatsRow

                // Time range picker + chart
                trendSection

                // Tips
                tipsSection
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.top, PCTheme.Spacing.md)
            .padding(.bottom, PCTheme.Spacing.xl)
        }
        .background(Color.pcBackground)
        .navigationTitle("Battery")
        .refreshable {
            viewModel.load(dataManager: dataManager)
        }
        .onAppear {
            viewModel.load(dataManager: dataManager)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallBottomSheet(trigger: .gatedCTA)
        }
    }

    // MARK: - Current Level

    private var currentLevelSection: some View {
        CardView {
            VStack(spacing: PCTheme.Spacing.md) {
                // Large battery display
                HStack(spacing: PCTheme.Spacing.md) {
                    Image(systemName: viewModel.chargingIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(batteryColor)
                        .symbolEffect(.pulse, isActive: viewModel.isCharging)
                        .voiceOverHidden()

                    VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                        Text("\(viewModel.levelPercentage)%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(batteryColor)

                        HStack(spacing: PCTheme.Spacing.xs) {
                            if viewModel.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.footnote)
                                    .foregroundStyle(Color.pcAccent)
                            }
                            Text(viewModel.chargingStateText)
                                .typography(.subheadline, color: .pcTextSecondary)
                        }
                    }

                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery level \(viewModel.levelPercentage) percent, \(viewModel.chargingStateText)")
    }

    private var batteryColor: Color {
        healthColor(for: viewModel.levelPercentage)
    }

    // MARK: - Quick Stats

    private var quickStatsRow: some View {
        VStack(spacing: PCTheme.Spacing.md) {
            HStack(spacing: PCTheme.Spacing.md) {
                statCard(
                    icon: "thermometer.medium",
                    title: "Temperature",
                    value: viewModel.thermalStateText,
                    color: viewModel.thermalStateColor
                )

                statCard(
                    icon: "bolt.circle",
                    title: "Low Power",
                    value: viewModel.isLowPowerMode ? "On" : "Off",
                    color: viewModel.isLowPowerMode ? .pcAccent : .pcTextSecondary
                )

                if viewModel.maxCapacity != nil {
                    statCard(
                        icon: "heart.fill",
                        title: "Capacity",
                        value: viewModel.capacityText,
                        color: .pcAccent
                    )
                }
            }

            if viewModel.maxCapacity == nil {
                capacityUnavailableCard
            }
        }
    }

    private var capacityUnavailableCard: some View {
        CardView {
            HStack(spacing: PCTheme.Spacing.md) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(Color.pcTextSecondary)
                    .voiceOverHidden()

                VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                    Text("Battery Capacity")
                        .typography(.subheadline)

                    Text("Battery health details are only available in iPhone Settings.")
                        .typography(.footnote, color: .pcTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery capacity unavailable. Battery health details are only available in iPhone Settings.")
        .accessibilityHint("Activate Open Settings button to view in Settings")
    }

    private func statCard(icon: String, title: String, value: String, color: Color) -> some View {
        CardView {
            VStack(spacing: PCTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .voiceOverHidden()

                Text(title)
                    .typography(.caption, color: .pcTextSecondary)

                Text(value)
                    .typography(.footnote)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            // Time range picker
            HStack(spacing: PCTheme.Spacing.sm) {
                ForEach(BatteryTimeRange.allCases) { range in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedTimeRange = range
                        }
                    } label: {
                        Text(range.rawValue)
                            .typography(.footnote)
                            .padding(.horizontal, PCTheme.Spacing.md)
                            .padding(.vertical, PCTheme.Spacing.sm)
                            .background(
                                Capsule()
                                    .fill(viewModel.selectedTimeRange == range ? Color.pcAccent : Color.pcMintTint)
                            )
                            .foregroundStyle(viewModel.selectedTimeRange == range ? .white : Color.pcAccent)
                    }
                    .accessibleTapTarget()
                    .accessibilityAddTraits(viewModel.selectedTimeRange == range ? [.isSelected] : [])
                }

                Spacer()
            }

            BatteryTrendChart(
                snapshots: viewModel.filteredSnapshots,
                timeRange: viewModel.selectedTimeRange,
                isPremium: subscriptionManager.isPremium,
                onPremiumGate: { showPaywall = true }
            )
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Text("Battery Tips")
                .typography(.headline)
                .voiceOverHeading()

            ForEach(viewModel.tips) { tip in
                CardView {
                    HStack(alignment: .top, spacing: PCTheme.Spacing.md) {
                        Image(systemName: tip.icon)
                            .font(.title3)
                            .foregroundStyle(Color.pcAccent)
                            .frame(width: 32)
                            .voiceOverHidden()

                        VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                            Text(tip.title)
                                .typography(.subheadline)

                            Text(tip.description)
                                .typography(.footnote, color: .pcTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
