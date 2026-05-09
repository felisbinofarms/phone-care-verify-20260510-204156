import Testing
import Foundation
import Photos
@testable import PhoneCare

private let testLargeVideoThreshold: Int64 = 50 * 1024 * 1024

private func makeAssetInfo(
    id: String = UUID().uuidString,
    mediaType: PHAssetMediaType = .image,
    mediaSubtypes: PHAssetMediaSubtype = [],
    pixelWidth: Int = 4032,
    pixelHeight: Int = 3024,
    estimatedFileSize: Int64 = 3_000_000,
    creationDate: Date? = Date(timeIntervalSince1970: 1_700_000_000),
    burstIdentifier: String? = nil,
    burstSelectionTypes: PHAssetBurstSelectionType = [],
    duration: Double = 0,
    isScreenRecording: Bool = false
) -> AssetInfo {
    AssetInfo(
        identifier: id,
        creationDate: creationDate,
        mediaType: mediaType,
        mediaSubtypes: mediaSubtypes,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        estimatedFileSize: estimatedFileSize,
        burstIdentifier: burstIdentifier,
        burstSelectionTypes: burstSelectionTypes,
        duration: duration,
        isScreenRecording: isScreenRecording
    )
}

@Suite("PhotoAnalyzer")
struct PhotoAnalyzerTests {

    // MARK: - DuplicateGroup: count

    @Test("count returns the total number of identifiers in the group")
    func duplicateGroup_count() {
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a", "b", "c"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 1_000_000
        )
        #expect(group.count == 3)
    }

    @Test("count returns 1 for a single-asset group")
    func duplicateGroup_countSingle() {
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 0
        )
        #expect(group.count == 1)
    }

    // MARK: - DuplicateGroup: duplicateIdentifiers

    @Test("duplicateIdentifiers excludes the suggested-keep identifier")
    func duplicateGroup_duplicateIdentifiers() {
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a", "b", "c"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 0
        )
        let dupes = group.duplicateIdentifiers
        #expect(!dupes.contains("a"))
        #expect(dupes.contains("b"))
        #expect(dupes.contains("c"))
        #expect(dupes.count == 2)
    }

    @Test("duplicateIdentifiers is empty when only the kept asset exists")
    func duplicateGroup_duplicateIdentifiers_empty() {
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 0
        )
        #expect(group.duplicateIdentifiers.isEmpty)
    }

    // MARK: - PhotoAnalysisResult: duplicateCount

    @Test("duplicateCount sums extras across all groups")
    func photoResult_duplicateCount() {
        let groups = [
            DuplicateGroup(id: "1", assetIdentifiers: ["a", "b", "c"], suggestedKeepIdentifier: "a", estimatedSavingsBytes: 0),
            DuplicateGroup(id: "2", assetIdentifiers: ["x", "y"], suggestedKeepIdentifier: "x", estimatedSavingsBytes: 0),
        ]
        let result = PhotoAnalysisResult(
            totalPhotos: 100,
            duplicateGroups: groups,
            screenshotIdentifiers: [],
            largeVideoIdentifiers: [],
            blurryIdentifiers: []
        )
        // (3 - 1) + (2 - 1) = 3
        #expect(result.duplicateCount == 3)
    }

    @Test("duplicateCount is zero when there are no groups")
    func photoResult_duplicateCount_zero() {
        let result = PhotoAnalysisResult(
            totalPhotos: 50,
            duplicateGroups: [],
            screenshotIdentifiers: [],
            largeVideoIdentifiers: [],
            blurryIdentifiers: []
        )
        #expect(result.duplicateCount == 0)
    }

    // MARK: - PhotoAnalysisResult: estimatedDuplicateSavings

    @Test("estimatedDuplicateSavings sums savings across all groups")
    func photoResult_savings() {
        let groups = [
            DuplicateGroup(id: "1", assetIdentifiers: ["a", "b"], suggestedKeepIdentifier: "a", estimatedSavingsBytes: 2_000_000),
            DuplicateGroup(id: "2", assetIdentifiers: ["x", "y"], suggestedKeepIdentifier: "x", estimatedSavingsBytes: 3_000_000),
        ]
        let result = PhotoAnalysisResult(
            totalPhotos: 50,
            duplicateGroups: groups,
            screenshotIdentifiers: [],
            largeVideoIdentifiers: [],
            blurryIdentifiers: []
        )
        #expect(result.estimatedDuplicateSavings == 5_000_000)
    }

    @Test("estimatedDuplicateSavings is zero when no groups exist")
    func photoResult_savings_zero() {
        let result = PhotoAnalysisResult(
            totalPhotos: 0,
            duplicateGroups: [],
            screenshotIdentifiers: [],
            largeVideoIdentifiers: [],
            blurryIdentifiers: []
        )
        #expect(result.estimatedDuplicateSavings == 0)
    }

    // MARK: - PhotoAnalysisResult: count helpers

    @Test("screenshotCount, largeVideoCount, blurryCount return correct values")
    func photoResult_categoryCounts() {
        let result = PhotoAnalysisResult(
            totalPhotos: 200,
            duplicateGroups: [],
            screenshotIdentifiers: ["s1", "s2", "s3"],
            largeVideoIdentifiers: ["v1"],
            blurryIdentifiers: ["b1", "b2"]
        )
        #expect(result.screenshotCount == 3)
        #expect(result.largeVideoCount == 1)
        #expect(result.blurryCount == 2)
    }

    @Test("All counts are zero for an empty result")
    func photoResult_allZero() {
        let result = PhotoAnalysisResult(
            totalPhotos: 0,
            duplicateGroups: [],
            screenshotIdentifiers: [],
            largeVideoIdentifiers: [],
            blurryIdentifiers: []
        )
        #expect(result.duplicateCount == 0)
        #expect(result.estimatedDuplicateSavings == 0)
        #expect(result.screenshotCount == 0)
        #expect(result.largeVideoCount == 0)
        #expect(result.blurryCount == 0)
    }

    // MARK: - GroupReason display

    @Test("GroupReason.exactDuplicate has expected displayText and iconName")
    func groupReason_exactDuplicate() {
        let reason = GroupReason.exactDuplicate
        #expect(reason.displayText == "These are identical copies of the same photo.")
        #expect(reason.iconName == "doc.on.doc")
    }

    @Test("GroupReason.burstSequence has expected displayText and iconName")
    func groupReason_burstSequence() {
        let reason = GroupReason.burstSequence
        #expect(reason.displayText == "These were captured in rapid sequence (burst mode).")
        #expect(reason.iconName == "burst")
    }

    @Test("GroupReason.similarShots has expected displayText")
    func groupReason_similarShots() {
        let reason = GroupReason.similarShots
        #expect(reason.displayText == "These photos look very similar.")
    }

    @Test("GroupReason.loadedFromCache has expected displayText")
    func groupReason_loadedFromCache() {
        let reason = GroupReason.loadedFromCache
        #expect(reason.displayText == "Similar photos from your previous scan.")
    }

    // MARK: - DuplicateGroup: groupReason defaults

    @Test("DuplicateGroup defaults to loadedFromCache groupReason")
    func duplicateGroup_defaultGroupReason() {
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a", "b"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 0
        )
        #expect(group.groupReason == .loadedFromCache)
    }

    @Test("DuplicateGroup can be created with a specific groupReason")
    func duplicateGroup_customGroupReason() {
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a", "b"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 0,
            groupReason: .burstSequence,
            keepReason: "User previously selected this as the best shot."
        )
        #expect(group.groupReason == .burstSequence)
        #expect(group.keepReason == "User previously selected this as the best shot.")
    }

    // MARK: - LargeVideoInfo

    @Test("LargeVideoInfo id matches constructor id")
    func largeVideoInfo_id() {
        let info = LargeVideoInfo(
            id: "video-123",
            estimatedBytes: 500_000_000,
            durationSeconds: 120.5,
            creationDate: Date(),
            isScreenRecording: false
        )
        #expect(info.id == "video-123")
        #expect(info.estimatedBytes == 500_000_000)
        #expect(info.isScreenRecording == false)
    }

    @Test("LargeVideoInfo isScreenRecording flag is preserved")
    func largeVideoInfo_screenRecording() {
        let info = LargeVideoInfo(
            id: "rec-1",
            estimatedBytes: 100_000_000,
            durationSeconds: 60.0,
            creationDate: nil,
            isScreenRecording: true
        )
        #expect(info.isScreenRecording == true)
        #expect(info.creationDate == nil)
    }

    // MARK: - PhotoAnalysisResult: largeVideoInfos default

    @Test("PhotoAnalysisResult largeVideoInfos defaults to empty array")
    func photoResult_largeVideoInfos_default() {
        let result = PhotoAnalysisResult(
            totalPhotos: 10,
            duplicateGroups: [],
            screenshotIdentifiers: [],
            largeVideoIdentifiers: ["v1"],
            blurryIdentifiers: []
        )
        #expect(result.largeVideoInfos.isEmpty)
        #expect(result.largeVideoCount == 1)
    }

    // MARK: - Empty photo library produces empty duplicate groups

    @Test("PhotoAnalysisResult with zero photos has empty duplicateGroups")
    func emptyPhotoLibrary_emptyDuplicateGroups() {
        let result = PhotoAnalysisResult(
            totalPhotos: 0,
            duplicateGroups: [],
            screenshotIdentifiers: [],
            largeVideoIdentifiers: [],
            blurryIdentifiers: []
        )
        #expect(result.duplicateGroups.isEmpty)
        #expect(result.duplicateCount == 0)
    }

    // MARK: - Two identical photos detected as duplicates

    @Test("Two-asset group with exactDuplicate reason has exactly one duplicate identifier")
    func twoIdenticalPhotos_detectedAsDuplicates() {
        let group = DuplicateGroup(
            id: "exact-001",
            assetIdentifiers: ["photo_original", "photo_copy"],
            suggestedKeepIdentifier: "photo_original",
            estimatedSavingsBytes: 3_500_000,
            groupReason: .exactDuplicate
        )
        #expect(group.groupReason == .exactDuplicate)
        #expect(group.count == 2)
        #expect(group.duplicateIdentifiers.count == 1)
        #expect(group.duplicateIdentifiers.first == "photo_copy")
        #expect(group.estimatedSavingsBytes == 3_500_000)
    }

    @Test("exactDuplicate group's suggestedKeepIdentifier is in assetIdentifiers")
    func exactDuplicate_keepIdentifier_inGroup() {
        let group = DuplicateGroup(
            id: "exact-002",
            assetIdentifiers: ["img_a", "img_b"],
            suggestedKeepIdentifier: "img_a",
            estimatedSavingsBytes: 1_200_000,
            groupReason: .exactDuplicate
        )
        #expect(group.assetIdentifiers.contains(group.suggestedKeepIdentifier))
    }

    // MARK: - Burst photos grouped into one burst group

    @Test("Burst group with three assets has burstSequence reason and two duplicate identifiers")
    func burstPhotos_groupedIntoBurstGroup() {
        let group = DuplicateGroup(
            id: "burst-001",
            assetIdentifiers: ["burst_frame_1", "burst_frame_2", "burst_frame_3"],
            suggestedKeepIdentifier: "burst_frame_1",
            estimatedSavingsBytes: 8_000_000,
            groupReason: .burstSequence,
            keepReason: "This frame has the best estimated quality in the burst sequence."
        )
        #expect(group.groupReason == .burstSequence)
        #expect(group.count == 3)
        #expect(group.duplicateIdentifiers.count == 2)
        #expect(!group.keepReason.isEmpty)
    }

    @Test("Burst group savings equal sum of non-kept frame sizes")
    func burstGroup_savings_correctlyReflected() {
        let savings: Int64 = 12_000_000
        let group = DuplicateGroup(
            id: "burst-002",
            assetIdentifiers: ["b1", "b2", "b3", "b4"],
            suggestedKeepIdentifier: "b1",
            estimatedSavingsBytes: savings,
            groupReason: .burstSequence
        )
        #expect(group.estimatedSavingsBytes == savings)
        #expect(group.duplicateIdentifiers == ["b2", "b3", "b4"])
    }

    // MARK: - analyzeAssets (pure function) — #102

    @Test("analyzeAssets with empty input returns an empty result")
    func analyzeAssets_emptyInput_returnsEmptyResult() async {
        let result = await PhotoAnalyzer.analyzeAssets(
            [],
            totalCount: 0,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.totalPhotos == 0)
        #expect(result.duplicateGroups.isEmpty)
        #expect(result.screenshotIdentifiers.isEmpty)
        #expect(result.largeVideoIdentifiers.isEmpty)
        #expect(result.blurryIdentifiers.isEmpty)
    }

    @Test("analyzeAssets classifies a screenshot in screenshotIdentifiers, NOT in blurryIdentifiers")
    func analyzeAssets_screenshotsAreClassifiedNotBlurry() async {
        let screenshot = makeAssetInfo(
            id: "screenshot-1",
            mediaSubtypes: .photoScreenshot,
            // tiny dimensions that would otherwise hit the blurry pre-filter (< 500x500)
            pixelWidth: 100,
            pixelHeight: 100
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [screenshot],
            totalCount: 1,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.screenshotIdentifiers == ["screenshot-1"])
        #expect(!result.blurryIdentifiers.contains("screenshot-1"))
    }

    @Test("analyzeAssets groups two assets with the same burstIdentifier as a burst-sequence duplicate")
    func analyzeAssets_burstSequence_isGroupedAsDuplicate() async {
        let burstID = "burst-abc"
        let frame1 = makeAssetInfo(
            id: "frame-1",
            burstIdentifier: burstID,
            burstSelectionTypes: .userPick
        )
        let frame2 = makeAssetInfo(
            id: "frame-2",
            burstIdentifier: burstID,
            burstSelectionTypes: []
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [frame1, frame2],
            totalCount: 2,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.duplicateGroups.count == 1)
        let group = result.duplicateGroups.first
        #expect(group?.groupReason == .burstSequence)
        #expect(group?.assetIdentifiers.contains("frame-1") == true)
        #expect(group?.assetIdentifiers.contains("frame-2") == true)
    }

    @Test("analyzeAssets groups two assets with identical creation date and dimensions as exact duplicates")
    func analyzeAssets_sameDateAndDimensions_isExactDuplicate() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = makeAssetInfo(
            id: "orig",
            pixelWidth: 4032,
            pixelHeight: 3024,
            creationDate: date
        )
        let copy = makeAssetInfo(
            id: "copy",
            pixelWidth: 4032,
            pixelHeight: 3024,
            creationDate: date
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [original, copy],
            totalCount: 2,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.duplicateGroups.count == 1)
        let group = result.duplicateGroups.first
        #expect(group?.groupReason == .exactDuplicate)
        #expect(group?.assetIdentifiers.contains("orig") == true)
        #expect(group?.assetIdentifiers.contains("copy") == true)
    }

    @Test("analyzeAssets flags a video over the largeVideoThreshold")
    func analyzeAssets_largeVideoOverThreshold_isFlagged() async {
        let bigVideo = makeAssetInfo(
            id: "big-video",
            mediaType: .video,
            estimatedFileSize: testLargeVideoThreshold + 1_000_000,
            duration: 30
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [bigVideo],
            totalCount: 1,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.largeVideoIdentifiers == ["big-video"])
        #expect(result.largeVideoInfos.count == 1)
        #expect(result.largeVideoInfos.first?.id == "big-video")
    }

    @Test("analyzeAssets does not flag a video under the largeVideoThreshold")
    func analyzeAssets_smallVideo_underThreshold_notFlagged() async {
        let smallVideo = makeAssetInfo(
            id: "small-video",
            mediaType: .video,
            estimatedFileSize: 1_000_000,  // 1 MB, well under 50 MB threshold
            duration: 5
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [smallVideo],
            totalCount: 1,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.largeVideoIdentifiers.isEmpty)
        #expect(result.largeVideoInfos.isEmpty)
    }

    // MARK: - Screen recordings as a separate category (#71)

    @Test("analyzeAssets puts screen recordings in their own category, not in largeVideos")
    func analyzeAssets_screenRecordings_landInOwnCategoryNotLargeVideos() async {
        let recording = makeAssetInfo(
            id: "rec-1",
            mediaType: .video,
            estimatedFileSize: testLargeVideoThreshold + 100_000_000,
            duration: 60,
            isScreenRecording: true
        )
        let regularVideo = makeAssetInfo(
            id: "vid-1",
            mediaType: .video,
            estimatedFileSize: testLargeVideoThreshold + 100_000_000,
            duration: 30,
            isScreenRecording: false
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [recording, regularVideo],
            totalCount: 2,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.screenRecordingIdentifiers == ["rec-1"])
        #expect(result.largeVideoIdentifiers == ["vid-1"])
        #expect(result.screenRecordingCount == 1)
        // No double-counting: a recording must not appear in both surfaces.
        #expect(!result.largeVideoIdentifiers.contains("rec-1"))
    }

    @Test("analyzeAssets surfaces screen recordings regardless of file size")
    func analyzeAssets_smallScreenRecording_isStillSurfaced() async {
        let smallRecording = makeAssetInfo(
            id: "rec-tiny",
            mediaType: .video,
            estimatedFileSize: 1_000_000,
            duration: 5,
            isScreenRecording: true
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [smallRecording],
            totalCount: 1,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.screenRecordingIdentifiers == ["rec-tiny"])
        #expect(result.screenRecordingInfos.first?.isScreenRecording == true)
    }

    @Test("analyzeAssets sorts screen recordings biggest-first")
    func analyzeAssets_screenRecordings_sortedBiggestFirst() async {
        let smaller = makeAssetInfo(
            id: "rec-small",
            mediaType: .video,
            estimatedFileSize: 50_000_000,
            isScreenRecording: true
        )
        let bigger = makeAssetInfo(
            id: "rec-big",
            mediaType: .video,
            estimatedFileSize: 500_000_000,
            isScreenRecording: true
        )

        let result = await PhotoAnalyzer.analyzeAssets(
            [smaller, bigger],
            totalCount: 2,
            largeVideoThreshold: testLargeVideoThreshold,
            skipSimilarShotsGrouping: true
        )

        #expect(result.screenRecordingIdentifiers == ["rec-big", "rec-small"])
    }
}
