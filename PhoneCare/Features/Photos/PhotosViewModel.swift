import SwiftUI
import SwiftData
import Photos

enum PhotoCategory: String, CaseIterable, Identifiable {
    case duplicates = "Duplicates"
    case screenshots = "Screenshots"
    case blurry = "Blurry"
    case largeVideos = "Large Videos"
    case screenRecordings = "Screen Recordings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .duplicates:       return "plus.square.on.square"
        case .screenshots:      return "rectangle.portrait"
        case .blurry:           return "camera.metering.unknown"
        case .largeVideos:      return "video.fill"
        case .screenRecordings: return "record.circle"
        }
    }
}

struct ScreenshotAgeGroup: Identifiable {
    let title: String
    let ids: [String]
    var id: String { title }
}

/// Sort options for the Large Videos and Screen Recordings surfaces.
/// Default is `biggestFirst` per Q7 launch decision: lead with the largest
/// space wins, but let users flip to oldest-first when they want to scan
/// chronologically.
enum LargeVideoSortOrder: String, CaseIterable, Identifiable {
    case biggestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .biggestFirst: return "Biggest first"
        case .oldestFirst:  return "Oldest first"
        }
    }
}

/// Sort options for the Screenshots surface.
/// Default is `oldestFirst` per Q7 launch decision: oldest screenshots are
/// the safest to delete, so we surface those age groups first.
enum ScreenshotSortOrder: String, CaseIterable, Identifiable {
    case oldestFirst
    case newestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oldestFirst: return "Oldest first"
        case .newestFirst: return "Newest first"
        }
    }
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
    private(set) var screenRecordingIDs: [String] = []
    /// Screen-recording metadata, sourced from the analyzer biggest-first.
    private(set) var screenRecordingInfos: [LargeVideoInfo] = []

    // Sort state (per-session, not persisted across launches in v1).
    var largeVideoSort: LargeVideoSortOrder = .biggestFirst
    var screenshotSort: ScreenshotSortOrder = .oldestFirst

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
        case .duplicates:       return duplicateGroups.count
        case .screenshots:      return screenshotIDs.count
        case .blurry:           return blurryIDs.count
        case .largeVideos:      return largeVideoIDs.count
        case .screenRecordings: return screenRecordingIDs.count
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
        case .screenRecordings:
            return screenRecordingIDs.isEmpty ? "No screen recordings found" : "\(screenRecordingIDs.count) screen recordings"
        }
    }

    // MARK: - Sorted Surfaces

    var sortedLargeVideoInfos: [LargeVideoInfo] {
        sortVideoInfos(largeVideoInfos, by: largeVideoSort)
    }

    var sortedScreenRecordingInfos: [LargeVideoInfo] {
        sortVideoInfos(screenRecordingInfos, by: largeVideoSort)
    }

    private func sortVideoInfos(
        _ infos: [LargeVideoInfo],
        by order: LargeVideoSortOrder
    ) -> [LargeVideoInfo] {
        switch order {
        case .biggestFirst:
            return infos.sorted { $0.estimatedBytes > $1.estimatedBytes }
        case .oldestFirst:
            // Items missing a creationDate sort to the end; not "oldest" but
            // also not above dated items, which would mislead the user.
            return infos.sorted {
                ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture)
            }
        }
    }

    var selectedCount: Int { selectedPhotoIDs.count }

    var hasResults: Bool { currentResultCount > 0 }

    // MARK: - Screenshot Age Groups

    func screenshotsByAge(sortOrder: ScreenshotSortOrder = .oldestFirst) -> [ScreenshotAgeGroup] {
        guard !screenshotIDs.isEmpty else { return [] }

        var dated: [(id: String, date: Date?)] = []
        dated.reserveCapacity(screenshotIDs.count)

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: screenshotIDs, options: nil)
        fetchResult.enumerateObjects { asset, _, _ in
            dated.append((asset.localIdentifier, asset.creationDate))
        }

        return Self.bucketScreenshotsByAge(dated, now: Date(), sortOrder: sortOrder)
    }

    /// Pure bucketing logic, exposed for unit tests. Given dated screenshots
    /// and a reference `now`, produce the age-grouped sections; honors the
    /// requested sort order. Items with `date == nil` are bucketed as oldest
    /// since "unknown date" almost always means imported or restored content.
    static func bucketScreenshotsByAge(
        _ dated: [(id: String, date: Date?)],
        now: Date,
        sortOrder: ScreenshotSortOrder = .oldestFirst
    ) -> [ScreenshotAgeGroup] {
        guard !dated.isEmpty else { return [] }

        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!

        var thisWeek: [String] = []
        var lastMonth: [String] = []
        var olderThan30: [String] = []
        var olderThan90: [String] = []

        for entry in dated {
            guard let date = entry.date else {
                olderThan90.append(entry.id)
                continue
            }
            if date >= oneWeekAgo {
                thisWeek.append(entry.id)
            } else if date >= oneMonthAgo {
                lastMonth.append(entry.id)
            } else if date >= threeMonthsAgo {
                olderThan30.append(entry.id)
            } else {
                olderThan90.append(entry.id)
            }
        }

        // Build oldest-first; reverse if newest-first requested. Oldest at the
        // top is the launch default per Q7 because old screenshots are the
        // safest to delete.
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

        return sortOrder == .oldestFirst ? groups : groups.reversed()
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
                screenRecordingIDs = cache.decodedScreenRecordingIDs()
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
            screenRecordingIDs = analysisResult.screenRecordingIdentifiers
            screenRecordingInfos = analysisResult.screenRecordingInfos

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
        screenRecordingIDs = screenRecordingIDs.filter { !deletedIDs.contains($0) }
        screenRecordingInfos = screenRecordingInfos.filter { !deletedIDs.contains($0.id) }

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
        largeVideoInfos: [LargeVideoInfo] = [],
        screenRecordingIDs: [String] = [],
        screenRecordingInfos: [LargeVideoInfo] = []
    ) {
        self.duplicateGroups = duplicateGroups
        self.screenshotIDs = screenshotIDs
        self.blurryIDs = blurryIDs
        self.largeVideoIDs = largeVideoIDs
        self.largeVideoInfos = largeVideoInfos
        self.screenRecordingIDs = screenRecordingIDs
        self.screenRecordingInfos = screenRecordingInfos
        self.scanComplete = true
    }
#endif
}
