import SwiftUI
import Photos

struct CleanPhotosFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var coordinator = GuidedFlowCoordinator(
        flowType: .cleanPhotos,
        steps: [
            FlowStep(
                id: "intro",
                title: "Let's tidy up your photos",
                description: "We will help you find and remove photos you probably don't need.",
                icon: "photo.on.rectangle.angled",
                isSkippable: false
            ),
            FlowStep(
                id: "duplicates",
                title: "Remove duplicates",
                description: "These are photos that look like the same shot taken more than once. We compare them visually using on-device intelligence and suggest keeping the sharpest one.",
                icon: "plus.square.on.square",
                isSkippable: true
            ),
            FlowStep(
                id: "blurry",
                title: "Clean up blurry photos",
                description: "Blurry photos take up space but are rarely useful. Let's review them.",
                icon: "camera.metering.unknown",
                isSkippable: true
            ),
            FlowStep(
                id: "screenshots",
                title: "Review screenshots",
                description: "Old screenshots can pile up. Let's see which ones you still need.",
                icon: "rectangle.portrait",
                isSkippable: true
            ),
        ]
    )

    @State private var photoAnalyzer = PhotoAnalyzer()
    @State private var scanResult: PhotoAnalysisResult?
    @State private var isScanning = false
    @State private var isDeleting = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.isComplete {
                    CompletionCelebrationView(
                        flowType: .cleanPhotos,
                        itemsCleaned: coordinator.itemsCleaned,
                        bytesFreed: coordinator.bytesFreed,
                        onDone: { dismiss() }
                    )
                } else if let step = coordinator.currentStep {
                    FlowStepView(
                        step: step,
                        stepNumber: coordinator.currentStepNumber,
                        totalSteps: coordinator.totalSteps,
                        canGoBack: coordinator.canGoBack,
                        onConfirm: { handleConfirm(for: step) },
                        onSkip: { coordinator.skip() },
                        onBack: { coordinator.back() }
                    ) {
                        stepContent(for: step)
                    }
                }
            }
            .navigationTitle("Clean Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibleTapTarget()
                }
            }
            .task {
                guard scanResult == nil, !isScanning else { return }
                isScanning = true
                scanResult = await photoAnalyzer.analyze()
                isScanning = false
            }
            .sheet(isPresented: $showPaywall) {
                PaywallBottomSheet(trigger: .gatedCTA)
            }
        }
    }

    // MARK: - Step Actions

    private func handleConfirm(for step: FlowStep) {
        switch step.id {
        case "duplicates":
            let ids = scanResult?.duplicateGroups.flatMap(\.duplicateIdentifiers) ?? []
            deletePhotos(ids: ids, estimatedBytesEach: 3_500_000) {
                coordinator.next()
            }
        case "blurry":
            let ids = scanResult?.blurryIdentifiers ?? []
            deletePhotos(ids: ids, estimatedBytesEach: 2_000_000) {
                coordinator.next()
            }
        case "screenshots":
            let ids = scanResult?.screenshotIdentifiers ?? []
            deletePhotos(ids: ids, estimatedBytesEach: 500_000) {
                coordinator.next()
            }
        default:
            coordinator.next()
        }
    }

    private func deletePhotos(ids: [String], estimatedBytesEach: Int64, onComplete: @escaping () -> Void) {
        guard !ids.isEmpty else {
            onComplete()
            return
        }

        guard subscriptionManager.isPremium else {
            showPaywall = true
            return
        }

        isDeleting = true
        Task { @MainActor in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var assetArray: [PHAsset] = []
            assets.enumerateObjects { asset, _, _ in
                assetArray.append(asset)
            }

            guard !assetArray.isEmpty else {
                isDeleting = false
                onComplete()
                return
            }

            do {
                let assetsToDelete = assetArray as NSArray
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    PHAssetChangeRequest.deleteAssets(assetsToDelete)
                }
                // Deletion confirmed by user via system dialog.
                // Photos move to Recently Deleted (30-day recovery).
                let deletedCount = assetArray.count
                let bytesFreed = Int64(deletedCount) * estimatedBytesEach
                coordinator.recordCleanup(items: deletedCount, bytes: bytesFreed)
                isDeleting = false
                onComplete()
            } catch {
                // User cancelled the system deletion dialog — stay on step so they can retry or skip.
                isDeleting = false
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private func stepContent(for step: FlowStep) -> some View {
        switch step.id {
        case "duplicates":
            CardView {
                VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                    if isScanning {
                        HStack(spacing: PCTheme.Spacing.sm) {
                            ProgressView()
                            Text("Scanning your photos...")
                                .typography(.subheadline, color: .pcTextSecondary)
                        }
                    } else if let result = scanResult {
                        let count = result.duplicateCount
                        Text(count > 0 ? "Found \(count) duplicate photos" : "No duplicates found")
                            .typography(.subheadline)
                    }
                    tipRow("We compare photos visually using Apple's on-device Vision framework, plus dimensions and timing for exact matches")
                    tipRow("We suggest keeping the sharpest version with the highest resolution and detail")
                    tipRow("iOS keeps deleted photos in Recently Deleted for 30 days")
                }
            }
        case "blurry":
            CardView {
                VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                    if let result = scanResult {
                        let count = result.blurryCount
                        Text(count > 0 ? "Found \(count) blurry photos" : "No blurry photos found")
                            .typography(.subheadline)
                    }
                    tipRow("Photos with low pixel dimensions")
                    tipRow("Smaller images are often less useful for keeping or printing")
                    tipRow("You choose which ones to remove")
                }
            }
        case "screenshots":
            CardView {
                VStack(alignment: .leading, spacing: PCTheme.Spacing.sm) {
                    if let result = scanResult {
                        let count = result.screenshotCount
                        Text(count > 0 ? "Found \(count) screenshots" : "No screenshots found")
                            .typography(.subheadline)
                    }
                    tipRow("Screenshots older than 30 days are often no longer needed")
                    tipRow("You can review each one before deleting")
                }
            }
        default:
            EmptyView()
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: PCTheme.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(Color.pcAccent)
                .voiceOverHidden()
            Text(text)
                .typography(.footnote, color: .pcTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
