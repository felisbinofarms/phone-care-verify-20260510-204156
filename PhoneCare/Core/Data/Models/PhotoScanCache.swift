import Foundation
import SwiftData

@Model
final class PhotoScanCache {
    var id: UUID = UUID()

    /// PHPhotoLibrary change token, used to detect library mutations since last scan.
    var libraryChangeToken: Data?

    /// JSON-encoded array of duplicate photo groups: [[String]] (local identifiers).
    var duplicateGroups: Data = Data()

    /// JSON-encoded array of similar photo groups: [[String]].
    var similarGroups: Data = Data()

    /// JSON-encoded array of screenshot local identifiers: [String].
    var screenshotIDs: Data = Data()

    /// JSON-encoded array of blurry photo local identifiers: [String].
    var blurryIDs: Data = Data()

    /// JSON-encoded array of large video local identifiers: [String].
    var largeVideoIDs: Data = Data()

    /// JSON-encoded array of screen-recording local identifiers: [String].
    var screenRecordingIDs: Data = Data()

    var totalScannedCount: Int = 0
    var scanDate: Date = Date()

    // MARK: - Decode Helpers

    func decodedDuplicateGroups() -> [[String]] {
        (try? JSONDecoder().decode([[String]].self, from: duplicateGroups)) ?? []
    }

    func decodedSimilarGroups() -> [[String]] {
        (try? JSONDecoder().decode([[String]].self, from: similarGroups)) ?? []
    }

    func decodedScreenshotIDs() -> [String] {
        (try? JSONDecoder().decode([String].self, from: screenshotIDs)) ?? []
    }

    func decodedBlurryIDs() -> [String] {
        (try? JSONDecoder().decode([String].self, from: blurryIDs)) ?? []
    }

    func decodedLargeVideoIDs() -> [String] {
        (try? JSONDecoder().decode([String].self, from: largeVideoIDs)) ?? []
    }

    func decodedScreenRecordingIDs() -> [String] {
        (try? JSONDecoder().decode([String].self, from: screenRecordingIDs)) ?? []
    }

    // MARK: - Encode Helpers

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        libraryChangeToken: Data? = nil,
        duplicateGroups: [[String]] = [],
        similarGroups: [[String]] = [],
        screenshotIDs: [String] = [],
        blurryIDs: [String] = [],
        largeVideoIDs: [String] = [],
        screenRecordingIDs: [String] = [],
        totalScannedCount: Int = 0,
        scanDate: Date = Date()
    ) {
        self.id = id
        self.libraryChangeToken = libraryChangeToken
        self.duplicateGroups = Self.encode(duplicateGroups)
        self.similarGroups = Self.encode(similarGroups)
        self.screenshotIDs = Self.encode(screenshotIDs)
        self.blurryIDs = Self.encode(blurryIDs)
        self.largeVideoIDs = Self.encode(largeVideoIDs)
        self.screenRecordingIDs = Self.encode(screenRecordingIDs)
        self.totalScannedCount = totalScannedCount
        self.scanDate = scanDate
    }
}
