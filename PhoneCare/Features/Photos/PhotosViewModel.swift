import SwiftUI
import SwiftData
import Photos

enum PhotoCategory: String, CaseIterable, Identifiable {
    case duplicates = "Duplicates"
    case screenshots = "Screenshots"
    case blurry = "Blurry"
    case largeVideos = "Large Videos"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .duplicates:  return "plus.square.on.square"
        case .screenshots: return "rectangle.portrait"
        case .blurry:      return "camera.metering.unknown"
        case .largeVideos: return "video.fill"
        }
    }
}

struct ScreenshotAgeGroup: Identifiable {
    let title: String
    let ids: [String]
    var id: String { title }
}

@MainActor
@Observable
final class PhotosViewModel {

    // MARK: - Dependencies

    private let analyzer = PhotoAnalyzer()

    // MARK: - State

    var selectedCategory: PhotoCategory = .duplicates
    private(set) var isScanning: Bool = false
    private(set) var scanComplete: Bool = false
    private(set) var permissionDenied: Bool = false

    // Group data
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var screenshotIDs: [String] = []
    private(set) var blurryIDs: [String] = []
    private(set) var largeVideoIDs: [String] = []
    /// Large video metadata sorted by file size descending (biggest wins first).
    private(set) var largeVideoInfos: [LargeVideoInfo] = []

    // Selection
    var selectedPhotoIDs: Set<String> = []

    // Batch delete
    var showBatchDeleteSheet: Bool = false
    private(set) var isDeleting: Bool = false
    private(set) var lastDeletedCount: Int = 0
    private(set) var lastDeletedSize: Int64 = 0
    var showUndoToast: Bool = false

    // MARK: - Progress (pass-through from analyzer)

    var scanProgress: Double { analyzer.progress }
    var scanStatusMessage: String { analyzer.statusMessage }

    // MARK: - Computed

    var currentResultCount: Int {
        switch selectedCategory {
        case .duplicates:  return duplicateGroups.count
        case .screenshots: return screenshotIDs.count
        case .blurry:      return blurryIDs.count
        case .largeVideos: return largeVideoIDs.count
        }
    }

    var currentCategoryDescription: String {
        switch selectedCategory {
        case .duplicates:
            let count = duplicateGroups.reduce(0) { $0 + $1.assetIdentifiers.count }
            return count == 0 ? "No duplicates found" : "\(duplicateGroups.count) groups with \(count) photos"
        case .screenshots:
            return screenshotIDs.isEmpty ? "No screenshots found" : "\(screenshotIDs.count) screenshots"
        case .blurry:
            return blurryIDs.isEmpty ? "No blurry photos found" : "\(blurryIDs.count) blurry photos"
        case .largeVideos:
            return largeVideoIDs.isEmpty ? "No large videos found" : "\(largeVideoIDs.count) large videos"
        }
    }

    var selectedCount: Int { selectedPhotoIDs.count }

    var hasResults: Bool { currentResultCount > 0 }

    // MARK: - Screenshot Age Groups

    func screenshotsByAge() -> [ScreenshotAgeGroup] {
        guard !screenshotIDs.isEmpty else { return [] }

        let now = Date()
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!

        var thisWeek: [String] = []
        var lastMonth: [String] = []
        var olderThan30: [String] = []
        var olderThan90: [String] = []

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: screenshotIDs, options: nil)
        fetchResult.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            guard let date = asset.creationDate else {
                olderThan90.append(id)
                return
            }
            if date >= oneWeekAgo {
                thisWeek.append(id)
            } else if date >= oneMonthAgo {
                lastMonth.append(id)
            } else if date >= threeMonthsAgo {
                olderThan30.append(id)
            } else {
                olderThan90.append(id)
            }
        }

        // Oldest first — most likely safe-to-delete, surface at top
        var groups: [ScreenshotAgeGroup] = []
        if !olderThan90.isEmpty {
            groups.append(ScreenshotAgeGroup(title: "Older than 90 Days", ids: olderThan90))
        }
        if !olderThan30.isEmpty {
            groups.append(ScreenshotAgeGroup(title: "Older than 30 Days", ids: olderThan30))
        }
        if !lastMonth.isEmpty {
            groups.append(ScreenshotAgeGroup(title: "Last Month", ids: lastMonth))
        }
        if !thisWeek.isEmpty {
            groups.append(ScreenshotAgeGroup(title: "This Week", ids: thisWeek))
        }
        return groups
    }

    func selectAllInAgeGroup(_ group: ScreenshotAgeGroup) {
        selectedPhotoIDs.formUnion(group.ids)
    }

    // MARK: - Load

    func load(dataManager: DataManager) {
        do {
            let caches = try dataManager.fetch(
                PhotoScanCache.self,
                sortBy: [SortDescriptor(\.scanDate, order: .reverse)],
                fetchLimit: 1
            )
            if let cache = caches.first {
                // Convert cached [[String]] to [DuplicateGroup] (reasons not persisted)
                duplicateGroups = cache.decodedDuplicateGroups().enumerated().map { idx, ids in
                    DuplicateGroup(
                        id: "cache-\(idx)",
                        assetIdentifiers: ids,
                        suggestedKeepIdentifier: ids.first ?? "",
                        estimatedSavingsBytes: 0,
                        groupReason: .loadedFromCache,
                        keepReason: "Re-scan to see why this photo is recommended."
                    )
                }
                screenshotIDs = cache.decodedScreenshotIDs()
                blurryIDs = cache.decodedBlurryIDs()
                largeVideoIDs = cache.decodedLargeVideoIDs()
                scanComplete = true
            }
        } catch {
            // Show empty state
        }
    }

    // MARK: - Scan

    func startScan(dataManager: DataManager) {
        isScanning = true
        permissionDenied = false
        Task {
            let analysisResult = await analyzer.analyze()

            let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard authStatus == .authorized || authStatus == .limited else {
                isScanning = false
                permissionDenied = true
                return
            }

            await analyzer.saveCache(to: dataManager, analysisResult: analysisResult)
            updateScanResult(dataManager: dataManager, analysisResult: analysisResult)

            duplicateGroups = analysisResult.duplicateGroups
            screenshotIDs = analysisResult.screenshotIdentifiers
            blurryIDs = analysisResult.blurryIdentifiers
            largeVideoIDs = analysisResult.largeVideoIdentifiers
            largeVideoInfos = analysisResult.largeVideoInfos

            isScanning = false
            scanComplete = true
        }
    }

    // MARK: - Selection

    func toggleSelection(_ id: String) {
        if selectedPhotoIDs.contains(id) {
            selectedPhotoIDs.remove(id)
        } else {
            selectedPhotoIDs.insert(id)
        }
    }

    func selectAll(in ids: [String]) {
        selectedPhotoIDs.formUnion(ids)
    }

    func deselectAll() {
        selectedPhotoIDs.removeAll()
    }

    // MARK: - Batch Delete

    func prepareBatchDelete() {
        guard !selectedPhotoIDs.isEmpty else { return }
        showBatchDeleteSheet = true
    }

    func confirmBatchDelete(dataManager: DataManager) async {
        let idsToDelete = Array(selectedPhotoIDs)
        guard !idsToDelete.isEmpty else { return }

        isDeleting = true
        showBatchDeleteSheet = false

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: idsToDelete, options: nil)
        var assetArray: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in assetArray.append(asset) }

        guard !assetArray.isEmpty else {
            isDeleting = false
            selectedPhotoIDs.removeAll()
            return
        }

        // Estimate bytes before deletion
        var estimatedBytes: Int64 = 0
        for asset in assetArray {
            var assetSize: Int64 = 0
            for resource in PHAssetResource.assetResources(for: asset) {
                if let size = resource.value(forKey: "fileSize") as? Int64 { assetSize += size }
            }
            if assetSize == 0 {
                let pixelCount = Int64(asset.pixelWidth * asset.pixelHeight)
                assetSize = asset.mediaType == .video
                    ? max(Int64(asset.duration * 8_000_000), pixelCount * 4)
                    : pixelCount * 3
            }
            estimatedBytes += assetSize
        }

        do {
            let assetsNSArray = assetArray as NSArray
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.deleteAssets(assetsNSArray)
            }
            // User confirmed the iOS system deletion dialog.
            // Photos move to Recently Deleted (30-day recovery window).
            applyDeletion(
                deletedIDs: Set(idsToDelete),
                count: assetArray.count,
                bytes: estimatedBytes
            )
        } catch {
            // User cancelled the iOS system dialog — silently restore state.
        }

        isDeleting = false
    }

    /// Updates all local state after a confirmed deletion.
    /// Extracted so the state-update logic is testable without PHPhotoLibrary.
    func applyDeletion(deletedIDs: Set<String>, count: Int, bytes: Int64) {
        selectedPhotoIDs.subtract(deletedIDs)
        lastDeletedCount = count
        lastDeletedSize = bytes
        showBatchDeleteSheet = false

        duplicateGroups = duplicateGroups.compactMap { group in
            let remaining = group.assetIdentifiers.filter { !deletedIDs.contains($0) }
            guard remaining.count >= 2 else { return nil }
            let newKeep = deletedIDs.contains(group.suggestedKeepIdentifier)
                ? (remaining.first ?? group.suggestedKeepIdentifier)
                : group.suggestedKeepIdentifier
            return DuplicateGroup(
                id: group.id,
                assetIdentifiers: remaining,
                suggestedKeepIdentifier: newKeep,
                estimatedSavingsBytes: group.estimatedSavingsBytes,
                groupReason: group.groupReason,
                keepReason: group.keepReason
            )
        }
        screenshotIDs = screenshotIDs.filter { !deletedIDs.contains($0) }
        blurryIDs = blurryIDs.filter { !deletedIDs.contains($0) }
        largeVideoIDs = largeVideoIDs.filter { !deletedIDs.contains($0) }
        largeVideoInfos = largeVideoInfos.filter { !deletedIDs.contains($0.id) }

        showUndoToast = true
    }

    func dismissDeletedToast() {
        showUndoToast = false
    }

    // MARK: - Batch Delete Intent

    /// What the view should do when the user taps the batch-delete CTA.
    /// Free users with multi-select hit a friction prompt; everyone else proceeds.
    enum BatchDeleteIntent {
        case empty
        case proceed
        case showFrictionPrompt
    }

    func batchDeleteIntent(isPremium: Bool) -> BatchDeleteIntent {
        if selectedPhotoIDs.isEmpty { return .empty }
        if !isPremium && selectedPhotoIDs.count > 1 { return .showFrictionPrompt }
        return .proceed
    }

    // MARK: - Persistence

    private func updateScanResult(dataManager: DataManager, analysisResult: PhotoAnalysisResult) {
        do {
            if let existing = try dataManager.latestScanResult() {
                existing.photoCount = analysisResult.totalPhotos
                existing.duplicatePhotoCount = analysisResult.duplicateCount
                existing.duplicatePhotoSize = analysisResult.estimatedDuplicateSavings
                try dataManager.saveContext()
            } else {
                let scanResult = ScanResult(
                    photoCount: analysisResult.totalPhotos,
                    duplicatePhotoCount: analysisResult.duplicateCount,
                    duplicatePhotoSize: analysisResult.estimatedDuplicateSavings
                )
                try dataManager.save(scanResult)
            }
        } catch {
            // Persistence failure shouldn't block scan results from showing
        }
    }

    // MARK: - Debug Test Helpers

#if DEBUG
    /// Injects scan data directly, bypassing PHPhotoLibrary. For unit tests only.
    func injectTestData(
        duplicateGroups: [DuplicateGroup],
        screenshotIDs: [String],
        blurryIDs: [String],
        largeVideoIDs: [String],
        largeVideoInfos: [LargeVideoInfo] = []
    ) {
        self.duplicateGroups = duplicateGroups
        self.screenshotIDs = screenshotIDs
        self.blurryIDs = blurryIDs
        self.largeVideoIDs = largeVideoIDs
        self.largeVideoInfos = largeVideoInfos
        self.scanComplete = true
    }
#endif
}
