import Foundation
import Photos
import OSLog

// MARK: - Storage Category

struct StorageCategoryData: Sendable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let sizeInBytes: Int64
    let color: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
}

// MARK: - Storage Analysis Result

struct StorageAnalysisResult: Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
    let recoverableBytes: Int64
    var categories: [StorageCategoryData]

    init(
        totalBytes: Int64,
        availableBytes: Int64,
        recoverableBytes: Int64 = 0,
        categories: [StorageCategoryData]
    ) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.recoverableBytes = recoverableBytes
        self.categories = categories
    }

    var usedBytes: Int64 { totalBytes - availableBytes }

    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }
}

// MARK: - Storage Analyzer

@MainActor
@Observable
final class StorageAnalyzer {

    // MARK: - State

    private(set) var result: StorageAnalysisResult?
    private(set) var isAnalyzing: Bool = false
    private(set) var progress: Double = 0.0
    private(set) var statusMessage: String = ""
    private(set) var errorMessage: String?

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhoneCare", category: "StorageAnalyzer")

    // MARK: - Analyze

    func analyze() async -> StorageAnalysisResult {
        isAnalyzing = true
        progress = 0.0
        statusMessage = "Checking storage..."
        errorMessage = nil

        defer {
            isAnalyzing = false
            progress = 1.0
        }

        // Step 1: Get total and available capacity
        guard let (total, available, recoverable) = fetchDiskCapacity() else {
            errorMessage = "Could not read device storage. Try again."
            statusMessage = ""
            let emptyResult = StorageAnalysisResult(
                totalBytes: 0,
                availableBytes: 0,
                recoverableBytes: 0,
                categories: []
            )
            result = emptyResult
            return emptyResult
        }
        progress = 0.3
        statusMessage = "Reading storage details..."

        // Step 2: Estimate photo library size
        let photoSize = await estimatePhotoLibrarySize()
        progress = 0.6
        statusMessage = "Calculating categories..."

        // Step 3: Estimate app storage
        let appSize = estimateAppStorageSize()
        progress = 0.8

        // Step 4: Build categories
        let used = total - available
        let systemAndOther = max(0, used - photoSize - appSize)

        var categories: [StorageCategoryData] = [
            StorageCategoryData(
                id: "photos",
                name: "Photos & Videos",
                icon: "photo.fill",
                sizeInBytes: photoSize,
                color: "pcPrimary"
            ),
            StorageCategoryData(
                id: "apps",
                name: "Apps",
                icon: "square.grid.2x2.fill",
                sizeInBytes: appSize,
                color: "pcAccent"
            ),
            StorageCategoryData(
                id: "system",
                name: "System & Other",
                icon: "gearshape.fill",
                sizeInBytes: systemAndOther,
                color: "pcTextSecondary"
            ),
            StorageCategoryData(
                id: "available",
                name: "Available",
                icon: "checkmark.circle.fill",
                sizeInBytes: available,
                color: "pcMintTint"
            ),
        ]

        progress = 1.0
        statusMessage = "Done"

        let analysisResult = StorageAnalysisResult(
            totalBytes: total,
            availableBytes: available,
            recoverableBytes: recoverable,
            categories: categories
        )
        result = analysisResult
        return analysisResult
    }

    // MARK: - Save to DataManager

    func saveScanResult(to dataManager: DataManager, analysisResult: StorageAnalysisResult) async {
        let scanResult = ScanResult(
            totalStorage: analysisResult.totalBytes,
            usedStorage: analysisResult.usedBytes,
            recoverableStorage: analysisResult.recoverableBytes
        )

        for category in analysisResult.categories where category.id != "available" {
            let detail = ScanDetail(
                category: "storage",
                detailType: category.id,
                value: Double(category.sizeInBytes),
                unit: "bytes",
                sizeInBytes: category.sizeInBytes,
                scanResult: scanResult
            )
            scanResult.details?.append(detail)
        }

        do {
            try dataManager.save(scanResult)
            logger.info("Storage scan result saved.")
        } catch {
            logger.error("Failed to save storage scan result: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func fetchDiskCapacity() -> (total: Int64, available: Int64, recoverable: Int64)? {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try homeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityForOpportunisticUsageKey,
            ])

            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            let recoverable = values.volumeAvailableCapacityForOpportunisticUsage ?? available

            guard total > 0 else { return nil }
            return (total, available, recoverable)
        } catch {
            logger.error("Failed to read disk capacity: \(error.localizedDescription)")
            return nil
        }
    }

    private nonisolated func estimatePhotoLibrarySize() async -> Int64 {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return 0
        }

        return await Task.detached {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.includeAllBurstAssets = false

            let assets = PHAsset.fetchAssets(with: options)
            var totalSize: Int64 = 0
            let resources = PHAssetResource.self

            let batchSize = 200
            let count = assets.count
            var index = 0

            while index < count {
                let end = min(index + batchSize, count)
                for i in index..<end {
                    let asset = assets.object(at: i)
                    let assetResources = resources.assetResources(for: asset)
                    for resource in assetResources {
                        if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                            totalSize += fileSize
                        }
                    }
                }
                index = end
            }

            return totalSize
        }.value
    }

    private func estimateAppStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default

        let paths: [String?] = [
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first,
            NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first,
            NSTemporaryDirectory(),
        ]

        for path in paths.compactMap({ $0 }) {
            totalSize += directorySize(at: path, fileManager: fileManager)
        }

        return totalSize
    }

    private func directorySize(at path: String, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
        var size: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? Int64 {
                size += fileSize
            }
        }
        return size
    }
}
