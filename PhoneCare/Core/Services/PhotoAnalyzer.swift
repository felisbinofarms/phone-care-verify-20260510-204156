import Foundation
import Photos
import UIKit
import OSLog

// MARK: - Group Reason

/// Explains why photos were placed in the same group.
enum GroupReason: String, Sendable, Codable {
    /// Identical copies: same creation timestamp and pixel dimensions.
    case exactDuplicate
    /// Captured in a burst sequence (shared PHAsset burst identifier).
    case burstSequence
    /// Visually similar shots detected via perceptual hashing.
    case similarShots
    /// Loaded from a previous scan — exact reason not available.
    case loadedFromCache

    var displayText: String {
        switch self {
        case .exactDuplicate:  return "These are identical copies of the same photo."
        case .burstSequence:   return "These were captured in rapid sequence (burst mode)."
        case .similarShots:    return "These photos look very similar."
        case .loadedFromCache: return "Similar photos from your previous scan."
        }
    }

    var iconName: String {
        switch self {
        case .exactDuplicate:  return "doc.on.doc"
        case .burstSequence:   return "burst"
        case .similarShots:    return "photo.on.rectangle.angled"
        case .loadedFromCache: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Duplicate Group

struct DuplicateGroup: Sendable, Identifiable {
    let id: String
    let assetIdentifiers: [String]
    let suggestedKeepIdentifier: String
    let estimatedSavingsBytes: Int64
    /// Why these photos were grouped together.
    let groupReason: GroupReason
    /// Human-readable explanation of why this photo is the suggested keep.
    let keepReason: String

    init(
        id: String,
        assetIdentifiers: [String],
        suggestedKeepIdentifier: String,
        estimatedSavingsBytes: Int64,
        groupReason: GroupReason = .loadedFromCache,
        keepReason: String = "Highest quality photo selected to keep."
    ) {
        self.id = id
        self.assetIdentifiers = assetIdentifiers
        self.suggestedKeepIdentifier = suggestedKeepIdentifier
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.groupReason = groupReason
        self.keepReason = keepReason
    }

    var count: Int { assetIdentifiers.count }

    var duplicateIdentifiers: [String] {
        assetIdentifiers.filter { $0 != suggestedKeepIdentifier }
    }
}

// MARK: - Large Video Info

/// Metadata for a video flagged as large, enriched for space-first ranking.
struct LargeVideoInfo: Sendable, Identifiable {
    let id: String           // asset local identifier
    let estimatedBytes: Int64
    let durationSeconds: Double
    let creationDate: Date?
    let isScreenRecording: Bool
}

// MARK: - Asset Info DTO

/// Sendable DTO projection of a `PHAsset`'s analysis-relevant metadata.
/// `PhotoAnalyzer` enumerates real `PHAsset`s into `[AssetInfo]` once; the rest
/// of the analysis logic operates on this DTO. Tests construct synthetic
/// `[AssetInfo]` arrays and call `PhotoAnalyzer.analyzeAssets(...)` directly,
/// bypassing the unmockable PHKit fetch.
struct AssetInfo: Sendable {
    let identifier: String
    let creationDate: Date?
    let mediaType: PHAssetMediaType
    let mediaSubtypes: PHAssetMediaSubtype
    let pixelWidth: Int
    let pixelHeight: Int
    let estimatedFileSize: Int64
    let burstIdentifier: String?
    let burstSelectionTypes: PHAssetBurstSelectionType
    let duration: Double
    let isScreenRecording: Bool
}

// MARK: - Photo Analysis Result

struct PhotoAnalysisResult: Sendable {
    let totalPhotos: Int
    let duplicateGroups: [DuplicateGroup]
    let screenshotIdentifiers: [String]
    /// Large video asset identifiers (kept for cache compatibility).
    let largeVideoIdentifiers: [String]
    /// Large video infos sorted by estimated file size descending (biggest wins first).
    let largeVideoInfos: [LargeVideoInfo]
    /// Screen-recording asset identifiers, separated from large videos so the
    /// Photos UI can offer a dedicated review surface (Q7 launch decision).
    let screenRecordingIdentifiers: [String]
    /// Screen-recording metadata sorted biggest-first.
    let screenRecordingInfos: [LargeVideoInfo]
    let blurryIdentifiers: [String]

    init(
        totalPhotos: Int,
        duplicateGroups: [DuplicateGroup],
        screenshotIdentifiers: [String],
        largeVideoIdentifiers: [String],
        largeVideoInfos: [LargeVideoInfo] = [],
        screenRecordingIdentifiers: [String] = [],
        screenRecordingInfos: [LargeVideoInfo] = [],
        blurryIdentifiers: [String]
    ) {
        self.totalPhotos = totalPhotos
        self.duplicateGroups = duplicateGroups
        self.screenshotIdentifiers = screenshotIdentifiers
        self.largeVideoIdentifiers = largeVideoIdentifiers
        self.largeVideoInfos = largeVideoInfos
        self.screenRecordingIdentifiers = screenRecordingIdentifiers
        self.screenRecordingInfos = screenRecordingInfos
        self.blurryIdentifiers = blurryIdentifiers
    }

    var duplicateCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.count - 1 }
    }

    var estimatedDuplicateSavings: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.estimatedSavingsBytes }
    }

    var screenshotCount: Int { screenshotIdentifiers.count }
    var largeVideoCount: Int { largeVideoIdentifiers.count }
    var screenRecordingCount: Int { screenRecordingIdentifiers.count }
    var blurryCount: Int { blurryIdentifiers.count }
}

// MARK: - Photo Analyzer

@MainActor
@Observable
final class PhotoAnalyzer {

    // MARK: - State

    private(set) var result: PhotoAnalysisResult?
    private(set) var isAnalyzing: Bool = false
    private(set) var progress: Double = 0.0
    private(set) var statusMessage: String = ""

    // MARK: - Configuration

    /// Minimum video file size to flag as "large" (250 MB).
    /// Q7 launch decision: focus the Large Videos surface on genuine
    /// space-win candidates and avoid spamming the list with mid-size clips.
    private let largeVideoThreshold: Int64 = 250 * 1024 * 1024

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhoneCare", category: "PhotoAnalyzer")

    // MARK: - Analyze

    func analyze() async -> PhotoAnalysisResult {
        isAnalyzing = true
        progress = 0.0
        statusMessage = "Scanning photos..."

        defer {
            isAnalyzing = false
            progress = 1.0
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            let emptyResult = PhotoAnalysisResult(
                totalPhotos: 0,
                duplicateGroups: [],
                screenshotIdentifiers: [],
                largeVideoIdentifiers: [],
                screenRecordingIdentifiers: [],
                blurryIdentifiers: []
            )
            result = emptyResult
            return emptyResult
        }

        // Run heavy work off the main actor
        let analysisResult = await Task.detached { [largeVideoThreshold] in
            await Self.performAnalysis(largeVideoThreshold: largeVideoThreshold)
        }.value

        progress = 1.0
        statusMessage = "Photo scan complete"
        result = analysisResult
        return analysisResult
    }

    // MARK: - Progress Updates (called from within analyze)

    func updateProgress(_ value: Double, message: String) {
        progress = value
        statusMessage = message
    }

    // MARK: - Cache Support

    func saveCache(to dataManager: DataManager, analysisResult: PhotoAnalysisResult) async {
        // Get the current library change token
        let changeToken: Data? = nil // PHPhotoLibrary change token requires registration

        let duplicateGroupIDs = analysisResult.duplicateGroups.map { $0.assetIdentifiers }

        let cache = PhotoScanCache(
            libraryChangeToken: changeToken,
            duplicateGroups: duplicateGroupIDs,
            screenshotIDs: analysisResult.screenshotIdentifiers,
            blurryIDs: analysisResult.blurryIdentifiers,
            largeVideoIDs: analysisResult.largeVideoIdentifiers,
            screenRecordingIDs: analysisResult.screenRecordingIdentifiers,
            totalScannedCount: analysisResult.totalPhotos,
            scanDate: Date()
        )

        do {
            // Delete old caches first
            try dataManager.deleteAll(PhotoScanCache.self)
            try dataManager.save(cache)
            logger.info("Photo scan cache saved.")
        } catch {
            logger.error("Failed to save photo scan cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Static Analysis (runs off main actor)

    private static func performAnalysis(
        largeVideoThreshold: Int64
    ) async -> PhotoAnalysisResult {
        let (assets, totalCount) = fetchAllAssets()
        guard totalCount > 0 else {
            return PhotoAnalysisResult(
                totalPhotos: 0,
                duplicateGroups: [],
                screenshotIdentifiers: [],
                largeVideoIdentifiers: [],
                screenRecordingIdentifiers: [],
                blurryIdentifiers: []
            )
        }
        return await analyzeAssets(
            assets,
            totalCount: totalCount,
            largeVideoThreshold: largeVideoThreshold
        )
    }

    /// Enumerates the real photo library and projects each `PHAsset` into a
    /// Sendable `AssetInfo`. The PHKit-only half of the analysis pipeline;
    /// tests bypass this and call `analyzeAssets(...)` with synthetic data.
    private static func fetchAllAssets() -> (assets: [AssetInfo], totalCount: Int) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = false
        // Include all burst frames so we can detect burst sequences
        fetchOptions.includeAllBurstAssets = true
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        let totalCount = allAssets.count

        var assetInfos: [AssetInfo] = []
        assetInfos.reserveCapacity(totalCount)

        for i in 0..<totalCount {
            let asset = allAssets.object(at: i)

            var estimatedSize: Int64 = 0
            let resources = PHAssetResource.assetResources(for: asset)
            var isScreenRecording = false
            for resource in resources {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    estimatedSize += size
                }

                // PHAssetMediaSubtype has no stable screen-recording case across SDKs.
                // Use filename hints produced by iOS screen recordings as a fallback.
                let filename = resource.originalFilename.lowercased()
                if filename.contains("rp_replay") || filename.contains("screen recording") {
                    isScreenRecording = true
                }
            }
            if estimatedSize == 0 {
                let pixelCount = Int64(asset.pixelWidth * asset.pixelHeight)
                estimatedSize = asset.mediaType == .video
                    ? max(Int64(asset.duration * 8_000_000), pixelCount * 4)
                    : pixelCount * 3
            }

            assetInfos.append(AssetInfo(
                identifier: asset.localIdentifier,
                creationDate: asset.creationDate,
                mediaType: asset.mediaType,
                mediaSubtypes: asset.mediaSubtypes,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                estimatedFileSize: estimatedSize,
                burstIdentifier: asset.burstIdentifier,
                burstSelectionTypes: asset.burstSelectionTypes,
                duration: asset.duration,
                isScreenRecording: isScreenRecording
            ))
        }

        return (assetInfos, totalCount)
    }

    /// Pure analysis logic — accepts pre-projected `[AssetInfo]` and returns
    /// the analysis result. Tests call this directly with synthetic data and
    /// pass `skipSimilarShotsGrouping: true` to bypass the perceptual-hash
    /// thumbnail loading (which requires real PHAsset identifiers).
    static func analyzeAssets(
        _ assetInfos: [AssetInfo],
        totalCount: Int,
        largeVideoThreshold: Int64,
        skipSimilarShotsGrouping: Bool = false
    ) async -> PhotoAnalysisResult {
        // ── 1. Screenshots ──────────────────────────────────────────────────────
        let screenshots = assetInfos.filter { $0.mediaSubtypes.contains(.photoScreenshot) }
        let screenshotIDs = screenshots.map(\.identifier)

        // ── 2. Screen recordings (own surface, regardless of size) ──────────────
        // Screen recordings get their own review surface (Q7 launch decision).
        // They are excluded from the Large Videos category below so a recording
        // never appears in two places at once.
        let screenRecordingAssets = assetInfos.filter {
            $0.mediaType == .video && $0.isScreenRecording
        }.sorted { $0.estimatedFileSize > $1.estimatedFileSize }

        let screenRecordingIDs = screenRecordingAssets.map(\.identifier)
        let screenRecordingInfos = screenRecordingAssets.map { v in
            LargeVideoInfo(
                id: v.identifier,
                estimatedBytes: v.estimatedFileSize,
                durationSeconds: v.duration,
                creationDate: v.creationDate,
                isScreenRecording: true
            )
        }

        // ── 3. Large videos (non-recording videos over threshold, biggest-first) ─
        let largeVideoAssets = assetInfos.filter {
            $0.mediaType == .video
            && !$0.isScreenRecording
            && $0.estimatedFileSize > largeVideoThreshold
        }.sorted { $0.estimatedFileSize > $1.estimatedFileSize }

        let largeVideoIDs = largeVideoAssets.map(\.identifier)
        let largeVideoInfos = largeVideoAssets.map { v in
            LargeVideoInfo(
                id: v.identifier,
                estimatedBytes: v.estimatedFileSize,
                durationSeconds: v.duration,
                creationDate: v.creationDate,
                isScreenRecording: false
            )
        }

        // ── 3. Blurry detection (Laplacian variance on small candidates) ────────
        // Pre-filter: only inspect non-screenshot images with low pixel count;
        // full-resolution photos are unlikely to be blurry-and-worth-flagging.
        let blurryThresholdPixels = 500 * 500
        let blurryCandidates = assetInfos.filter {
            $0.mediaType == .image
            && !$0.mediaSubtypes.contains(.photoScreenshot)
            && $0.pixelWidth > 0
            && ($0.pixelWidth * $0.pixelHeight) < blurryThresholdPixels
        }

        // Verify each candidate's actual sharpness. Conservative on load
        // failure — don't flag photos we couldn't measure.
        let blurryVarianceThreshold: Double = 100.0
        var blurryIDs: [String] = []
        blurryIDs.reserveCapacity(blurryCandidates.count)
        for candidate in blurryCandidates {
            if let variance = await computeLaplacianVariance(identifier: candidate.identifier),
               variance < blurryVarianceThreshold {
                blurryIDs.append(candidate.identifier)
            }
        }

        // ── 4. Duplicate / similar photo grouping ───────────────────────────────
        // Work on non-screenshot, non-blurry photos only
        let blurrySet = Set(blurryIDs)
        let screenshotSet = Set(screenshotIDs)
        let photos = assetInfos.filter {
            $0.mediaType == .image
            && !screenshotSet.contains($0.identifier)
            && !blurrySet.contains($0.identifier)
        }

        var duplicateGroups: [DuplicateGroup] = []
        var processedIdentifiers: Set<String> = []

        // — 4a. Burst sequences ——————————————————————————————————————————————————
        var burstBuckets: [String: [AssetInfo]] = [:]
        for photo in photos {
            guard let burst = photo.burstIdentifier else { continue }
            burstBuckets[burst, default: []].append(photo)
        }
        for (_, members) in burstBuckets where members.count >= 2 {
            // Prefer user-picked best shot; fall back to auto-pick, then highest res
            guard let best = members.first(where: { $0.burstSelectionTypes.contains(.userPick) })
                ?? members.first(where: { $0.burstSelectionTypes.contains(.autoPick) })
                ?? members.max(by: { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) })
                ?? members.first
            else { continue }

            let savings = members
                .filter { $0.identifier != best.identifier }
                .reduce(Int64(0)) { $0 + $1.estimatedFileSize }

            let keepReason: String
            if best.burstSelectionTypes.contains(.userPick) {
                keepReason = "You previously selected this as the best shot in the burst."
            } else {
                keepReason = "This frame has the best estimated quality in the burst sequence."
            }

            duplicateGroups.append(DuplicateGroup(
                id: UUID().uuidString,
                assetIdentifiers: members.map(\.identifier),
                suggestedKeepIdentifier: best.identifier,
                estimatedSavingsBytes: savings,
                groupReason: .burstSequence,
                keepReason: keepReason
            ))
            members.forEach { processedIdentifiers.insert($0.identifier) }
        }

        // — 4b. Exact duplicates (same creation time ± 0.5s + same dimensions) ——
        let exactWindow: TimeInterval = 0.5
        let remaining1 = photos.filter { !processedIdentifiers.contains($0.identifier) }
        let sortedByDate = remaining1.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        var i = 0
        while i < sortedByDate.count {
            let anchor = sortedByDate[i]
            guard !processedIdentifiers.contains(anchor.identifier),
                  let anchorDate = anchor.creationDate else {
                i += 1
                continue
            }

            var group: [AssetInfo] = [anchor]
            var j = i + 1
            while j < sortedByDate.count {
                let candidate = sortedByDate[j]
                guard let candidateDate = candidate.creationDate,
                      abs(candidateDate.timeIntervalSince(anchorDate)) <= exactWindow else { break }
                if !processedIdentifiers.contains(candidate.identifier)
                    && candidate.pixelWidth == anchor.pixelWidth
                    && candidate.pixelHeight == anchor.pixelHeight {
                    group.append(candidate)
                }
                j += 1
            }

            if group.count >= 2 {
                guard let best = group.max(by: { $0.estimatedFileSize < $1.estimatedFileSize }) ?? group.first else { continue }
                let savings = group
                    .filter { $0.identifier != best.identifier }
                    .reduce(Int64(0)) { $0 + $1.estimatedFileSize }

                duplicateGroups.append(DuplicateGroup(
                    id: UUID().uuidString,
                    assetIdentifiers: group.map(\.identifier),
                    suggestedKeepIdentifier: best.identifier,
                    estimatedSavingsBytes: savings,
                    groupReason: .exactDuplicate,
                    keepReason: "This copy has the largest file size, indicating it may be higher quality."
                ))
                group.forEach { processedIdentifiers.insert($0.identifier) }
            }
            i += 1
        }

        // — 4c. Similar shots via 8×8 perceptual hash ————————————————————————————
        // Skipped by tests via `skipSimilarShotsGrouping: true`, since this loop
        // calls `computePerceptualHash` which loads thumbnails via PHImageManager
        // for real PHAsset identifiers — synthetic test identifiers don't resolve.
        if !skipSimilarShotsGrouping {
            let remaining2 = photos.filter { !processedIdentifiers.contains($0.identifier) }
            let sortedForPHash = remaining2.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

            let phashBucketWindow: TimeInterval = 60.0
            var phashBuckets: [[AssetInfo]] = []
            var currentBucket: [AssetInfo] = []
            var bucketAnchorDate: Date?

            for photo in sortedForPHash {
                guard let date = photo.creationDate else { continue }
                if let anchor = bucketAnchorDate, date.timeIntervalSince(anchor) <= phashBucketWindow {
                    currentBucket.append(photo)
                } else {
                    if currentBucket.count >= 2 { phashBuckets.append(currentBucket) }
                    currentBucket = [photo]
                    bucketAnchorDate = date
                }
            }
            if currentBucket.count >= 2 { phashBuckets.append(currentBucket) }

            for bucket in phashBuckets {
                // Compute hashes for all photos in this time window
                var hashPairs: [(info: AssetInfo, hash: UInt64)] = []
                for info in bucket {
                    if let h = await computePerceptualHash(identifier: info.identifier) {
                        hashPairs.append((info, h))
                    }
                }
                guard hashPairs.count >= 2 else { continue }

                // Union-Find to cluster similar photos
                let count = hashPairs.count
                var parent = Array(0..<count)

                func findRoot(_ idx: Int) -> Int {
                    var idx = idx
                    while parent[idx] != idx { idx = parent[idx] }
                    return idx
                }

                for a in 0..<count {
                    for b in (a + 1)..<count {
                        if hammingDistance(hashPairs[a].hash, hashPairs[b].hash) <= 12 {
                            let ra = findRoot(a), rb = findRoot(b)
                            if ra != rb { parent[ra] = rb }
                        }
                    }
                }

                var components: [Int: [AssetInfo]] = [:]
                for idx in 0..<count {
                    let root = findRoot(idx)
                    components[root, default: []].append(hashPairs[idx].info)
                }

                for (_, members) in components where members.count >= 2 {
                    guard members.allSatisfy({ !processedIdentifiers.contains($0.identifier) }) else { continue }
                    guard let best = members.max(by: { $0.estimatedFileSize < $1.estimatedFileSize }) ?? members.first else { continue }
                    let savings = members
                        .filter { $0.identifier != best.identifier }
                        .reduce(Int64(0)) { $0 + $1.estimatedFileSize }

                    duplicateGroups.append(DuplicateGroup(
                        id: UUID().uuidString,
                        assetIdentifiers: members.map(\.identifier),
                        suggestedKeepIdentifier: best.identifier,
                        estimatedSavingsBytes: savings,
                        groupReason: .similarShots,
                        keepReason: "This photo has the largest file size in the group, suggesting it captures the most detail."
                    ))
                    members.forEach { processedIdentifiers.insert($0.identifier) }
                }
            }
        }

        return PhotoAnalysisResult(
            totalPhotos: totalCount,
            duplicateGroups: duplicateGroups,
            screenshotIdentifiers: screenshotIDs,
            largeVideoIdentifiers: largeVideoIDs,
            largeVideoInfos: largeVideoInfos,
            screenRecordingIdentifiers: screenRecordingIDs,
            screenRecordingInfos: screenRecordingInfos,
            blurryIdentifiers: blurryIDs
        )
    }

    // MARK: - Perceptual Hash Helpers

    /// Requests an 8×8 thumbnail and computes an average-hash (aHash) for it.
    /// Returns nil when the asset is unavailable locally.
    private static func computePerceptualHash(identifier: String) async -> UInt64? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else { return nil }

        let image: UIImage? = await withThrowingTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let options = PHImageRequestOptions()
                    options.deliveryMode = .fastFormat
                    options.isNetworkAccessAllowed = false
                    options.resizeMode = .fast

                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: CGSize(width: 8, height: 8),
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        continuation.resume(returning: image)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return nil
            }
            do {
                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
            } catch {}
            group.cancelAll()
            return nil
        }
        return image.flatMap { Self.averageHash(from: $0) }
    }

    /// Converts a UIImage to an 8×8 greyscale average hash (64-bit aHash).
    private static func averageHash(from image: UIImage) -> UInt64? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelData = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &pixelData,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let mean = Double(pixelData.reduce(UInt32(0)) { $0 + UInt32($1) }) / Double(pixelData.count)
        var hash: UInt64 = 0
        for (idx, pixel) in pixelData.enumerated() {
            if Double(pixel) >= mean { hash |= (1 << idx) }
        }
        return hash
    }

    /// Counts the number of differing bits between two hashes (Hamming distance).
    private static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - Blur Detection Helpers

    /// Loads a 64×64 grayscale thumbnail of the asset and returns its Laplacian
    /// variance — a standard sharpness measure. Higher variance = sharper.
    /// Returns nil on load failure or timeout.
    private static func computeLaplacianVariance(identifier: String) async -> Double? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else { return nil }

        let image: UIImage? = await withThrowingTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let options = PHImageRequestOptions()
                    options.deliveryMode = .fastFormat
                    options.isNetworkAccessAllowed = false
                    options.resizeMode = .fast

                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: CGSize(width: 64, height: 64),
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        continuation.resume(returning: image)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return nil
            }
            do {
                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
            } catch {}
            group.cancelAll()
            return nil
        }

        return image.flatMap(Self.laplacianVariance(from:))
    }

    /// Computes the variance of a 3×3 Laplacian filter applied to a 64×64
    /// grayscale rendering of the image. Low variance = lacks high-frequency
    /// edge content, indicating a blurry image.
    private static func laplacianVariance(from image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 64
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelData = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &pixelData,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // 3×3 Laplacian kernel: [0, -1, 0; -1, 4, -1; 0, -1, 0].
        // Skip the 1-pixel border (no neighbors) so variance reflects interior content.
        var laplacian: [Double] = []
        laplacian.reserveCapacity((side - 2) * (side - 2))
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let idx = y * side + x
                let center = Double(pixelData[idx])
                let top = Double(pixelData[idx - side])
                let bottom = Double(pixelData[idx + side])
                let left = Double(pixelData[idx - 1])
                let right = Double(pixelData[idx + 1])
                laplacian.append(4 * center - top - bottom - left - right)
            }
        }

        guard !laplacian.isEmpty else { return nil }
        let mean = laplacian.reduce(0.0, +) / Double(laplacian.count)
        let variance = laplacian.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(laplacian.count)
        return variance
    }
}
