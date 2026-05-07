import SwiftUI
import Charts

struct BatteryTrendChart: View {
    let snapshots: [BatterySnapshot]
    let timeRange: BatteryTimeRange
    let isPremium: Bool
    var onPremiumGate: (() -> Void)?

    @State private var selectedSnapshot: BatterySnapshot?

    private var isGated: Bool {
        !isPremium && timeRange != .oneDay
    }

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.md) {
                Text("Battery Trend")
                    .typography(.headline)
                    .voiceOverHeading()

                if snapshots.isEmpty {
                    emptyChartState
                } else if isGated {
                    premiumGateOverlay
                } else {
                    chartContent
                }
            }
        }
    }

    // MARK: - Chart

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Chart {
                ForEach(snapshots, id: \.id) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Level", snapshot.level * 100)
                    )
                    .foregroundStyle(Color.pcAccent)
                    .interpolationMethod(.catmullRom)

                    if let selected = selectedSnapshot, selected.id == snapshot.id {
                        PointMark(
                            x: .value("Date", snapshot.date),
                            y: .value("Level", snapshot.level * 100)
                        )
                        .foregroundStyle(Color.pcPrimary)
                        .symbolSize(80)
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)%")
                                .typography(.caption, color: .pcTextSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xPos = value.location.x
                                    guard let date: Date = proxy.value(atX: xPos) else { return }
                                    selectedSnapshot = closestSnapshot(to: date)
                                }
                                .onEnded { _ in
                                    selectedSnapshot = nil
                                }
                        )
                }
            }
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartAccessibilityLabel)

            // Selected detail
            if let snapshot = selectedSnapshot {
                HStack(spacing: PCTheme.Spacing.md) {
                    Text(snapshot.date.shortRelativeFormatted())
                        .typography(.footnote, color: .pcTextSecondary)
                    Text("\(Int(snapshot.level * 100))%")
                        .typography(.footnote, color: .pcAccent)
                    if snapshot.isCharging {
                        Label("Charging", systemImage: "bolt.fill")
                            .typography(.caption, color: .pcTextSecondary)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Empty / Gated

    private var emptyChartState: some View {
        VStack(spacing: PCTheme.Spacing.md) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title)
                .foregroundStyle(Color.pcTextSecondary)
                .voiceOverHidden()

            Text("No battery data yet")
                .typography(.subheadline, color: .pcTextSecondary)

            Text("Battery trends will appear as data is collected over time.")
                .typography(.footnote, color: .pcTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PCTheme.Spacing.lg)
    }

    private var premiumGateOverlay: some View {
        VStack(spacing: PCTheme.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(Color.pcTextSecondary)
                .voiceOverHidden()

            Text("Extended history is a Premium feature")
                .typography(.subheadline, color: .pcTextSecondary)
                .multilineTextAlignment(.center)

            Text("Unlock Premium to see 30-day, 90-day, and yearly battery trends.")
                .typography(.footnote, color: .pcTextSecondary)
                .multilineTextAlignment(.center)

            Button("Unlock Premium") {
                onPremiumGate?()
            }
            .primaryCTAStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PCTheme.Spacing.lg)
    }

    // MARK: - Helpers

    private func closestSnapshot(to date: Date) -> BatterySnapshot? {
        snapshots.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private var chartAccessibilityLabel: String {
        guard !snapshots.isEmpty else { return "Battery trend chart, no data available" }
        let avg = snapshots.reduce(0.0) { $0 + $1.level } / Double(snapshots.count)
        return "Battery trend chart showing \(snapshots.count) data points over \(timeRange.rawValue). Average level: \(Int(avg * 100)) percent."
    }
}
