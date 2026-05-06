import SwiftUI
import SwiftData

@MainActor
@Observable
final class StorageViewModel {

    // MARK: - State

    private(set) var totalStorage: Int64 = 0
    private(set) var usedStorage: Int64 = 0
    private(set) var freeStorage: Int64 = 0
    private(set) var recoverableStorage: Int64 = 0
    private(set) var usedPercentage: Double = 0
    private(set) var categories: [StorageCategory] = []
    private(set) var recommendations: [StorageRecommendation] = []
    private(set) var isLoading: Bool = false
    private(set) var lastScanDate: Date?
    private(set) var errorMessage: String?

    // MARK: - Load

    func load(dataManager: DataManager) {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let scan = try dataManager.latestScanResult() {
                guard scan.totalStorage > 0 else {
                    // Cached scan was a failed-fetch zero-result; try live system fetch instead.
                    loadSystemStorage()
                    return
                }
                totalStorage = scan.totalStorage
                usedStorage = scan.usedStorage
                freeStorage = scan.freeStorage
                recoverableStorage = max(scan.recoverableStorage, scan.freeStorage)
                usedPercentage = scan.usedStoragePercentage
                lastScanDate = scan.scanDate

                categories = buildCategories(from: scan, dataManager: dataManager)
                recommendations = buildRecommendations(from: scan)
            } else {
                loadSystemStorage()
            }
        } catch {
            loadSystemStorage()
        }
    }

    // MARK: - System Fallback

    private func loadSystemStorage() {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
        ]) {
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            let recoverable = values.volumeAvailableCapacityForOpportunisticUsage ?? free
            if total == 0 {
                errorMessage = "Unable to read storage information"
                return
            }
            totalStorage = total
            freeStorage = free
            recoverableStorage = max(recoverable, free)
            usedStorage = total - free
            usedPercentage = total > 0 ? Double(usedStorage) / Double(total) * 100 : 0
        } else {
            errorMessage = "Unable to read storage information"
        }
    }

    // MARK: - Categories

    private func buildCategories(from scan: ScanResult, dataManager: DataManager) -> [StorageCategory] {
        var cats: [StorageCategory] = []

        // Gather details by category
        let details = scan.details ?? []
        var categoryBytes: [String: Int64] = [:]
        for detail in details where detail.category == "storage" {
            categoryBytes[detail.detailType, default: 0] += detail.sizeInBytes
        }

        let knownCategories: [(String, String, String, Color)] = [
            ("photos", "Photos & Videos", "photo.fill", .blue),
            ("apps", "Apps", "square.grid.2x2.fill", Color.pcAccent),
            ("messages", "Messages", "message.fill", .purple),
            ("system", "System", "gearshape.fill", .gray),
            ("other", "Other", "doc.fill", Color.pcTextSecondary),
        ]

        for (key, name, icon, color) in knownCategories {
            let bytes = categoryBytes[key] ?? 0
            if bytes > 0 {
                cats.append(StorageCategory(
                    id: key,
                    name: name,
                    icon: icon,
                    color: color,
                    sizeInBytes: bytes,
                    percentage: totalStorage > 0 ? Double(bytes) / Double(totalStorage) * 100 : 0
                ))
            }
        }

        // If no details, create a simple used/free breakdown
        if cats.isEmpty && usedStorage > 0 {
            cats.append(StorageCategory(
                id: "used",
                name: "Used",
                icon: "internaldrive.fill",
                color: .blue,
                sizeInBytes: usedStorage,
                percentage: usedPercentage
            ))
        }

        return cats.sorted { $0.sizeInBytes > $1.sizeInBytes }
    }

    // MARK: - Recommendations

    private func buildRecommendations(from scan: ScanResult) -> [StorageRecommendation] {
        var recs: [StorageRecommendation] = []

        if scan.duplicatePhotoCount > 0 {
            recs.append(StorageRecommendation(
                id: "duplicatePhotos",
                icon: "photo.on.rectangle",
                title: "Remove duplicate photos",
                description: "You have \(scan.duplicatePhotoCount) duplicate photos that can be cleaned up.",
                potentialSavings: scan.duplicatePhotoSize,
                destination: .photos
            ))
        }

        let freePercent = scan.totalStorage > 0
            ? Double(scan.freeStorage) / Double(scan.totalStorage) * 100
            : 100
        if freePercent < 20 {
            recs.append(StorageRecommendation(
                id: "lowStorage",
                icon: "exclamationmark.triangle",
                title: "Storage is getting full",
                description: "You have less than 20% free. Cleaning up files can help your phone run smoothly.",
                potentialSavings: 0,
                destination: nil
            ))
        }

        if scan.duplicateContactCount > 0 {
            recs.append(StorageRecommendation(
                id: "contacts",
                icon: "person.2",
                title: "Merge duplicate contacts",
                description: "\(scan.duplicateContactCount) contacts could be merged.",
                potentialSavings: 0,
                destination: .contacts
            ))
        }

        return recs
    }

    // MARK: - Formatting

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Models

struct StorageCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let sizeInBytes: Int64
    let percentage: Double
}

struct StorageRecommendation: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let potentialSavings: Int64
    let destination: StorageDestination?
}

enum StorageDestination {
    case photos
    case contacts
    case settings
}
