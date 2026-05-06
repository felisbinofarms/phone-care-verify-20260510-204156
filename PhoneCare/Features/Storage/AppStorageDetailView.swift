import SwiftUI

struct AppStorageDetailView: View {
    let category: StorageCategory
    @Environment(DataManager.self) private var dataManager

    @State private var details: [ScanDetail] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.lg) {
                headerSection

                if !details.isEmpty {
                    appBreakdownSection
                } else {
                    emptyState
                }

                tipsSection
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.top, PCTheme.Spacing.md)
        }
        .background(Color.pcBackground)
        .navigationTitle(category.name)
        .onAppear {
            loadDetails()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        CardView {
            HStack(spacing: PCTheme.Spacing.md) {
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundStyle(category.color)
                    .frame(width: 44, height: 44)
                    .background(category.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PCTheme.Radius.sm))
                    .voiceOverHidden()

                VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                    Text(category.name)
                        .typography(.headline)

                    Text(formatBytes(category.sizeInBytes))
                        .typography(.title3, color: .pcTextSecondary)

                    Text("\(String(format: "%.1f", category.percentage))% of total storage")
                        .typography(.footnote, color: .pcTextSecondary)
                }

                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - App Breakdown

    private var appBreakdownSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Text("Largest Apps")
                .typography(.headline)
                .voiceOverHeading()

            let sortedDetails = details.sorted { $0.sizeInBytes > $1.sizeInBytes }

            ForEach(sortedDetails.prefix(10), id: \.id) { detail in
                appRow(detail)
            }

            if details.count > 10 {
                NavigationLink {
                    VStack {
                        Text("All Apps")
                            .typography(.headline)
                            .padding()

                        ScrollView {
                            VStack(spacing: PCTheme.Spacing.sm) {
                                ForEach(sortedDetails, id: \.id) { detail in
                                    appRow(detail)
                                }
                            }
                            .padding(.horizontal, PCTheme.Spacing.md)
                        }
                    }
                    .background(Color.pcBackground)
                } label: {
                    HStack {
                        Text("Show all \(details.count) apps")
                            .typography(.footnote, color: .pcAccent)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(Color.pcAccent)
                    }
                    .padding(.top, PCTheme.Spacing.sm)
                }
            }
        }
    }

    private func appRow(_ detail: ScanDetail) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                HStack {
                    Text(detail.detailType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .typography(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Text(formatBytes(detail.sizeInBytes))
                        .typography(.footnote, color: .pcAccent)
                        .fontWeight(.semibold)
                }

                appRecommendation(for: detail)
            }
        }
    }

    private func appRecommendation(for detail: ScanDetail) -> some View {
        let recommendation: String
        if detail.sizeInBytes > 1_000_000_000 {
            recommendation = "Large app. If you don't open it often, offloading frees space while keeping your data."
        } else if detail.sizeInBytes > 500_000_000 {
            recommendation = "Sizable app. Worth checking if you still use it regularly."
        } else if detail.sizeInBytes > 100_000_000 {
            recommendation = "Moderate size. Keep if you use it; offload if not."
        } else {
            recommendation = "Small footprint."
        }

        return HStack(spacing: PCTheme.Spacing.xs) {
            Image(systemName: "lightbulb.fill")
                .font(.caption2)
                .foregroundStyle(Color.pcAccent)

            Text(recommendation)
                .typography(.caption, color: .pcTextSecondary)
        }
        .padding(.top, PCTheme.Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        CardView {
            VStack(spacing: PCTheme.Spacing.md) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(Color.pcTextSecondary)
                    .voiceOverHidden()

                Text("No app data yet")
                    .typography(.subheadline, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)

                Text("Run a scan from the home screen to get app storage information.")
                    .typography(.caption, color: .pcTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PCTheme.Spacing.lg)
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Text("Tips")
                .typography(.headline)
                .voiceOverHeading()

            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: PCTheme.Spacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.pcAccent)
                        .voiceOverHidden()

                    Text(tip)
                        .typography(.footnote, color: .pcTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, PCTheme.Spacing.lg)
    }

    private var tips: [String] {
        [
            "Offloading an app removes it but keeps your data. Reinstalling is quick.",
            "Apps cache data that can grow over time. Clear in Settings → General → Storage.",
            "Consider cloud storage (iCloud, Google Drive) for large media files."
        ]
    }

    // MARK: - Helpers

    private func loadDetails() {
        do {
            if let scan = try dataManager.latestScanResult() {
                details = (scan.details ?? []).filter { $0.category == "storage" && $0.detailType.contains("apps") }
            }
        } catch {
            details = []
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Preview

#Preview {
    let category = StorageCategory(
        id: "apps",
        name: "Apps",
        icon: "square.grid.2x2.fill",
        color: .blue,
        sizeInBytes: 25_000_000_000,
        percentage: 20.8
    )

    AppStorageDetailView(category: category)
}
