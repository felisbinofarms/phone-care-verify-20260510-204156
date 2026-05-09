import Foundation
import Photos
import UIKit
import Vision
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

    /// Vision feature-print distance threshold for grouping near-duplicates.
    /// `VNFeaturePrintObservation.computeDistance` returns 0 for identical
    /// images and grows with visual difference. 0.5 is a conservative starting
    /// point for "obviously the same shot" while leaving headroom against
    /// false-positives on visually similar but distinct moments. Easy to
    /// tune as we learn from real user libraries.
    static let similarShotsThreshold: Float = 0.5

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
                let (best, keepReason) = await pickKeepBest(from: group, skipSharpness: skipSimilarShotsGrouping)
                let savings = group
                    .filter { $0.identifier != best.identifier }
                    .reduce(Int64(0)) { $0 + $1.estimatedFileSize }

                duplicateGroups.append(DuplicateGroup(
                    id: UUID().uuidString,
                    assetIdentifiers: group.map(\.identifier),
                    suggestedKeepIdentifier: best.identifier,
                    estimatedSavingsBytes: savings,
                    groupReason: .exactDuplicate,
                    keepReason: keepReason
                ))
                group.forEach { processedIdentifiers.insert($0.identifier) }
            }
            i += 1
        }

        // ── 4c. Similar shots via Vision feature prints ─────────────────────────
        // Apple's `VNFeaturePrintObservation` is a perceptual embedding generated
        // by Vision's on-device model. Distance between two prints reflects
        // visual similarity; 0 == identical. The 60-second time-bucket below
        // is a cheap pre-filter so we only run Vision on plausibly-related shots.
        // Tests pass `skipSimilarShotsGrouping: true` because Vision needs real
        // image data, which synthetic test AssetInfos don't have.
        if !skipSimilarShotsGrouping {
            let remaining2 = photos.filter { !processedIdentifiers.contains($0.identifier) }
            let sortedForVision = remaining2.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

            let bucketWindow: TimeInterval = 60.0
            var visionBuckets: [[AssetInfo]] = []
            var currentBucket: [AssetInfo] = []
            var bucketAnchorDate: Date?

            for photo in sortedForVision {
                guard let date = photo.creationDate else { continue }
                if let anchor = bucketAnchorDate, date.timeIntervalSince(anchor) <= bucketWindow {
                    currentBucket.append(photo)
                } else {
                    if currentBucket.count >= 2 { visionBuckets.append(currentBucket) }
                    currentBucket = [photo]
                    bucketAnchorDate = date
                }
            }
            if currentBucket.count >= 2 { visionBuckets.append(currentBucket) }

            for bucket in visionBuckets {
                struct Embedding {
                    let info: AssetInfo
                    let observation: VNFeaturePrintObservation
                }
                var prints: [Embedding] = []
                for info in bucket {
                    if let obs = await computeFeaturePrint(identifier: info.identifier) {
                        prints.append(Embedding(info: info, observation: obs))
                    }
                }
                guard prints.count >= 2 else { continue }

                let clusters = Self.clusterByDistance(
                    items: prints,
                    threshold: Self.similarShotsThreshold
                ) { a, b in
                    var d: Float = 0
                    do {
                        try a.observation.computeDistance(&d, to: b.observation)
                        return d
                    } catch {
                        // On comparison failure, treat as far apart so the pair
                        // is not clustered. Better to under-group than over-group.
                        return .greatestFiniteMagnitude
                    }
                }

                for cluster in clusters where cluster.count >= 2 {
                    let members = cluster.map(\.info)
                    guard members.allSatisfy({ !processedIdentifiers.contains($0.identifier) }) else { continue }
                    let (best, keepReason) = await pickKeepBest(from: members, skipSharpness: false)
                    let savings = members
                        .filter { $0.identifier != best.identifier }
                        .reduce(Int64(0)) { $0 + $1.estimatedFileSize }

                    duplicateGroups.append(DuplicateGroup(
                        id: UUID().uuidString,
                        assetIdentifiers: members.map(\.identifier),
                        suggestedKeepIdentifier: best.identifier,
                        estimatedSavingsBytes: savings,
                        groupReason: .similarShots,
                        keepReason: keepReason
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

    // MARK: - Vision Feature Print Helpers

    /// Loads a 512x512 thumbnail of the asset and computes its Vision
    /// feature-print observation. Returns nil when the asset is unavailable
    /// locally, the thumbnail load times out, or Vision fails. Conservative
    /// on failure: a missing print means the photo simply will not be grouped.
    private static func computeFeaturePrint(identifier: String) async -> VNFeaturePrintObservation? {
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
                        targetSize: CGSize(width: 512, height: 512),
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

        guard let cgImage = image?.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    // MARK: - Generic Clustering

    /// Single-link clustering: items are merged into the same cluster when
    /// their pairwise distance is at or below `threshold`. Uses union-find.
    /// Pure function with an injectable `distance` closure so unit tests can
    /// exercise the clustering logic without Vision or any image I/O.
    nonisolated static func clusterByDistance<T>(
        items: [T],
        threshold: Float,
        distance: (T, T) -> Float
    ) -> [[T]] {
        let count = items.count
        guard count > 0 else { return [] }
        var parent = Array(0..<count)

        func findRoot(_ idx: Int) -> Int {
            var idx = idx
            while parent[idx] != idx { idx = parent[idx] }
            return idx
        }

        for a in 0..<count {
            for b in (a + 1)..<count {
                if distance(items[a], items[b]) <= threshold {
                    let ra = findRoot(a), rb = findRoot(b)
                    if ra != rb { parent[ra] = rb }
                }
            }
        }

        var components: [Int: [T]] = [:]
        for idx in 0..<count {
            let root = findRoot(idx)
            components[root, default: []].append(items[idx])
        }
        return Array(components.values)
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

    // MARK: - Keep-Best Scoring (#70)

    /// Picks the best photo to keep within a duplicate or similar-shots group.
    /// Loads sharpness for each member (unless `skipSharpness` is true, used by
    /// tests that operate without real PHAssets), then delegates to the pure
    /// `scoreKeepBest` helper below.
    private static func pickKeepBest(
        from members: [AssetInfo],
        skipSharpness: Bool
    ) async -> (best: AssetInfo, reason: String) {
        var scored: [(info: AssetInfo, sharpness: Double?)] = []
        scored.reserveCapacity(members.count)
        for info in members {
            let sharpness = skipSharpness
                ? nil
                : await computeLaplacianVariance(identifier: info.identifier)
            scored.append((info, sharpness))
        }

        let result = scoreKeepBest(members: scored)
        return (members[result.bestIndex], result.reason)
    }

    /// Picks the best member of a group by combining sharpness, resolution,
    /// and file size into a single 0-1 score per member. Each signal is
    /// normalized within the group, then weighted: sharpness 0.5,
    /// resolution 0.25, file size 0.25. Sharpness leads because users care
    /// most about whether the kept photo is in focus; resolution and file
    /// size act as tiebreakers and as a stand-in when sharpness is unavailable.
    /// Returns the index of the chosen member and a plain-English reason
    /// string explaining the choice.
    nonisolated static func scoreKeepBest(
        members: [(info: AssetInfo, sharpness: Double?)]
    ) -> (bestIndex: Int, reason: String) {
        precondition(!members.isEmpty, "scoreKeepBest requires at least one member")

        // If all sharpness samples are nil (test path or thumbnail loads
        // failed), fall back to the largest-file heuristic.
        let allSharpnessNil = members.allSatisfy { $0.sharpness == nil }

        let sharpValues = members.map { $0.sharpness ?? 0 }
        let resValues = members.map { Double($0.info.pixelWidth * $0.info.pixelHeight) }
        let sizeValues = members.map { Double($0.info.estimatedFileSize) }

        let normalizedSharp = normalize(sharpValues)
        let normalizedRes = normalize(resValues)
        let normalizedSize = normalize(sizeValues)

        // Find best index and capture which signal contributed most to the win.
        var bestIndex = 0
        var bestScore = -Double.infinity
        var bestContribSharp = 0.0
        var bestContribRes = 0.0
        var bestContribSize = 0.0

        for i in 0..<members.count {
            let s = allSharpnessNil ? 0.0 : 0.5 * normalizedSharp[i]
            let r = (allSharpnessNil ? 0.5 : 0.25) * normalizedRes[i]
            let z = (allSharpnessNil ? 0.5 : 0.25) * normalizedSize[i]
            let score = s + r + z
            if score > bestScore {
                bestScore = score
                bestIndex = i
                bestContribSharp = s
                bestContribRes = r
                bestContribSize = z
            }
        }

        let reason: String
        if allSharpnessNil {
            reason = "Largest file size and highest resolution in the group, suggesting the most detail captured."
        } else if bestContribSharp >= bestContribRes && bestContribSharp >= bestContribSize {
            reason = "Sharpest photo in the group with strong resolution and detail."
        } else if bestContribRes >= bestContribSize {
            reason = "Highest resolution in the group, suggesting more detail than the others."
        } else {
            reason = "Largest file size in the group, suggesting the most detail captured."
        }

        return (bestIndex, reason)
    }

    /// Min-max normalize an array to 0-1. All-equal inputs return all-1.0
    /// so the signal contributes nothing to the score (no false tiebreaker).
    nonisolated private static func normalize(_ values: [Double]) -> [Double] {
        guard let minV = values.min(), let maxV = values.max() else { return values.map { _ in 0 } }
        if maxV - minV < .ulpOfOne {
            return values.map { _ in 1.0 }
        }
        return values.map { ($0 - minV) / (maxV - minV) }
    }
}
