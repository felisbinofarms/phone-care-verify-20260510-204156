import SwiftUI

struct StorageView: View {
    @Environment(DataManager.self) private var dataManager
    @State private var viewModel = StorageViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: PCTheme.Spacing.lg) {
                // Total / Used display
                storageOverview

                // Segmented bar chart
                if !viewModel.categories.isEmpty {
                    CardView {
                        VStack(alignment: .leading, spacing: PCTheme.Spacing.md) {
                            Text("Storage Breakdown")
                                .typography(.headline)
                                .voiceOverHeading()

                            StorageBarChart(
                                totalBytes: viewModel.totalStorage,
                                categories: viewModel.categories,
                                freeBytes: viewModel.freeStorage
                            )
                        }
                    }
                }

                // Category list with drill-down
                categoryList

                // Recommendations
                if !viewModel.recommendations.isEmpty {
                    recommendationsSection
                }

                // Storage Tools
                storageToolsSection
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.top, PCTheme.Spacing.md)
            .padding(.bottom, PCTheme.Spacing.xl)
        }
        .background(Color.pcBackground)
        .accessibilityIdentifier("screen.storage")
        .navigationTitle("Storage")
        .refreshable {
            viewModel.load(dataManager: dataManager)
        }
        .onAppear {
            viewModel.load(dataManager: dataManager)
        }
    }

    // MARK: - Overview

    private var storageOverview: some View {
        CardView {
            if let error = viewModel.errorMessage {
                VStack(spacing: PCTheme.Spacing.sm) {
                    Image(systemName: "internaldrive")
                        .font(.title2)
                        .foregroundStyle(Color.pcTextSecondary)
                        .voiceOverHidden()

                    Text(error)
                        .typography(.subheadline, color: .pcTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PCTheme.Spacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(error)
            } else {
                VStack(spacing: PCTheme.Spacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                            Text("Used")
                                .typography(.footnote, color: .pcTextSecondary)
                            Text(viewModel.formatBytes(viewModel.usedStorage))
                                .typography(.title2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: PCTheme.Spacing.xs) {
                            Text("Free")
                                .typography(.footnote, color: .pcTextSecondary)
                            Text(viewModel.formatBytes(viewModel.freeStorage))
                                .typography(.title2, color: .pcAccent)
                        }
                    }

                    // Simple progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.pcBorder.opacity(0.3))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(usedColor)
                                .frame(width: geo.size.width * CGFloat(min(viewModel.usedPercentage, 100)) / 100)
                        }
                    }
                    .frame(height: 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Storage usage: \(Int(viewModel.usedPercentage)) percent used")

                    Text("of \(viewModel.formatBytes(viewModel.totalStorage)) total")
                        .typography(.caption, color: .pcTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var usedColor: Color {
        // Use blue/green spectrum, never red for storage
        if viewModel.usedPercentage >= 90 {
            return .pcWarning
        } else if viewModel.usedPercentage >= 75 {
                return .pcPrimary
        } else {
            return .pcAccent
        }
    }

    // MARK: - Category List

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            if !viewModel.categories.isEmpty {
                Text("Categories")
                    .typography(.headline)
                    .voiceOverHeading()

                ForEach(viewModel.categories) { category in
                    NavigationLink {
                        if category.id == "apps" {
                            AppStorageDetailView(category: category)
                        } else if category.id == "system" {
                            SystemDataExplainerView(
                                category: category,
                                availableBytes: viewModel.freeStorage,
                                recoverableBytes: viewModel.recoverableStorage
                            )
                        } else {
                            CategoryDrillDownView(category: category)
                        }
                    } label: {
                        categoryRow(category)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func categoryRow(_ category: StorageCategory) -> some View {
        CardView {
            HStack(spacing: PCTheme.Spacing.md) {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(category.color)
                    .frame(width: 36, height: 36)
                    .background(category.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PCTheme.Radius.sm))
                    .voiceOverHidden()

                VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                    Text(category.name)
                        .typography(.subheadline)

                    Text(viewModel.formatBytes(category.sizeInBytes))
                        .typography(.footnote, color: .pcTextSecondary)
                }

                Spacer()

                Text("\(String(format: "%.0f", category.percentage))%")
                    .typography(.footnote, color: .pcTextSecondary)

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Color.pcTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap for details")
    }

    // MARK: - Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Text("Suggestions")
                .typography(.headline)
                .voiceOverHeading()

            ForEach(viewModel.recommendations) { rec in
                recommendationRow(rec)
            }
        }
    }

    @ViewBuilder
    private func recommendationRow(_ rec: StorageRecommendation) -> some View {
        let content = CardView {
            HStack(spacing: PCTheme.Spacing.md) {
                Image(systemName: rec.icon)
                    .font(.title3)
                    .foregroundStyle(Color.pcAccent)
                    .frame(width: 36, height: 36)
                    .voiceOverHidden()

                VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                    Text(rec.title)
                        .typography(.subheadline)

                    Text(rec.description)
                        .typography(.footnote, color: .pcTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if rec.potentialSavings > 0 {
                        Text("Could save \(viewModel.formatBytes(rec.potentialSavings))")
                            .typography(.footnote, color: .pcAccent)
                    }
                }

                Spacer()

                if rec.destination != nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.pcTextSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)

        if let dest = rec.destination {
            switch dest {
            case .photos:
                NavigationLink { PhotosView() } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Go to Photos tab")
            case .contacts:
                NavigationLink { ContactsView() } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Go to Contacts")
            case .settings:
                NavigationLink { SettingsView() } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Go to Settings")
            }
        } else {
            content
        }
    }


    // MARK: - Storage Tools

    private var storageToolsSection: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Text("Storage Tools")
                .typography(.headline)
                .voiceOverHeading()

            NavigationLink {
                LargeFileFinderView(largeVideoIDs: [])
            } label: {
                toolRow(
                    icon: "video.fill",
                    title: "Find Large Videos",
                    subtitle: "See which videos are using the most space"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("storage.tool.largeFiles")

            NavigationLink {
                MessageAttachmentGuideView()
            } label: {
                toolRow(
                    icon: "message.fill",
                    title: "iMessage Attachments",
                    subtitle: "Guide to freeing up space from message attachments"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("storage.tool.messageGuide")
        }
    }

    private func toolRow(icon: String, title: String, subtitle: String) -> some View {
        CardView {
            HStack(spacing: PCTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.pcAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.pcAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PCTheme.Radius.sm))
                    .voiceOverHidden()

                VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
                    Text(title)
                        .typography(.subheadline)
                    Text(subtitle)
                        .typography(.footnote, color: .pcTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Color.pcTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to open")
    }
}

// Embedded here so it is included by the current Xcode project without regenerating project files.
struct SystemDataExplainerView: View {
    let category: StorageCategory
    let availableBytes: Int64
    let recoverableBytes: Int64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.lg) {
                overviewCard
                transparencyCard
                actionSteps
                restartTip
            }
            .padding(.horizontal, PCTheme.Spacing.md)
            .padding(.top, PCTheme.Spacing.md)
            .padding(.bottom, PCTheme.Spacing.xl)
        }
        .background(Color.pcBackground)
        .accessibilityIdentifier("screen.systemData")
        .navigationTitle("System Data")
    }

    private var overviewCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.md) {
                Text("What this means")
                    .typography(.headline)

                Text("System Data is iPhone space used by caches, logs, downloaded voices, temporary files, and other items Apple groups together.")
                    .typography(.subheadline, color: .pcTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: PCTheme.Spacing.md) {
                    storageStat(title: "System Data", value: formatBytes(category.sizeInBytes))
                    storageStat(title: "Available Now", value: formatBytes(availableBytes))
                    storageStat(title: "Recoverable", value: formatBytes(max(recoverableBytes - availableBytes, 0)))
                }
            }
        }
    }

    private var transparencyCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                Text("What Apple does not show apps")
                    .typography(.headline)

                Text("Apple does not let apps see the full System Data breakdown or clear it directly. We can explain what usually lives here and point you to the settings that help the most.")
                    .typography(.subheadline, color: .pcTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionSteps: some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
            Text("Ways to reduce it")
                .typography(.headline)
                .voiceOverHeading()

            settingsActionCard(
                title: "1. Clear Safari website data",
                detail: "Web history and site data can build up over time.",
                buttonTitle: "Open Safari Settings",
                urlString: "App-Prefs:root=SAFARI"
            )

            settingsActionCard(
                title: "2. Review iPhone storage",
                detail: "Offload unused apps and check large downloads stored by apps.",
                buttonTitle: "Open iPhone Storage",
                urlString: "App-Prefs:root=General&path=STORAGE_MGMT"
            )

            settingsActionCard(
                title: "3. Check downloaded music",
                detail: "Offline songs can quietly take up a lot of space.",
                buttonTitle: "Open Music Settings",
                urlString: "App-Prefs:root=MUSIC"
            )

            settingsActionCard(
                title: "4. Check downloaded podcasts",
                detail: "Old podcast downloads are easy to forget about.",
                buttonTitle: "Open Podcasts Settings",
                urlString: "App-Prefs:root=PODCASTS"
            )
        }
    }

    private var restartTip: some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                Text("5. Restart your iPhone")
                    .typography(.headline)

                Text("A restart can clear temporary caches and logs that build up during normal use. It will not remove your photos, contacts, or apps.")
                    .typography(.subheadline, color: .pcTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func storageStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: PCTheme.Spacing.xs) {
            Text(title)
                .typography(.caption, color: .pcTextSecondary)
            Text(value)
                .typography(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsActionCard(title: String, detail: String, buttonTitle: String, urlString: String) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                Text(title)
                    .typography(.subheadline)

                Text(detail)
                    .typography(.footnote, color: .pcTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(buttonTitle) {
                    openSettingsURL(urlString)
                }
                .secondaryStyle()
            }
        }
    }

    private func openSettingsURL(_ urlString: String) {
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        if let fallback = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(fallback)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
