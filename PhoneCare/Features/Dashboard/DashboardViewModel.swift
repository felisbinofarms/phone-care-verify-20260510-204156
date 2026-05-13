import SwiftUI
import SwiftData

@MainActor
@Observable
final class DashboardViewModel {

    // MARK: - State

    private(set) var healthScore: Int = 0
    private(set) var healthResult: HealthScoreResult?
    private(set) var quickWins: [QuickWin] = []
    private(set) var cardOrder: [String] = []
    private(set) var isLoading: Bool = false
    private(set) var lastScanDate: Date?

    // Storage summary
    private(set) var totalStorage: Int64 = 0
    private(set) var usedStorage: Int64 = 0
    private(set) var freeStorage: Int64 = 0

    // Photo summary
    private(set) var duplicatePhotoCount: Int = 0
    private(set) var duplicatePhotoSize: Int64 = 0

    // Contact summary
    private(set) var duplicateContactCount: Int = 0

    // Battery summary
    private(set) var batteryLevel: Double = 0
    private(set) var batteryHealth: Double?

    // Privacy summary
    private(set) var privacyIssueCount: Int = 0

    // MARK: - Load

    func refresh(
        dataManager: DataManager,
        permissionManager: PermissionManager,
        currentInfo: BatteryInfo? = nil
    ) {
        load(dataManager: dataManager, permissionManager: permissionManager, currentInfo: currentInfo)
    }

    func load(
        dataManager: DataManager,
        permissionManager: PermissionManager,
        currentInfo: BatteryInfo? = nil
    ) {
        isLoading = true
        defer { isLoading = false }

        do {
            let prefs = try dataManager.userPreferences()
            cardOrder = prefs.cardOrder

            if let scan = try dataManager.latestScanResult() {
                lastScanDate = scan.scanDate
                totalStorage = scan.totalStorage
                usedStorage = scan.usedStorage
                freeStorage = scan.freeStorage
                duplicatePhotoCount = scan.duplicatePhotoCount
                duplicatePhotoSize = scan.duplicatePhotoSize
                duplicateContactCount = scan.duplicateContactCount
                batteryLevel = currentInfo?.level ?? scan.batteryLevel
                batteryHealth = scan.batteryHealth
                privacyIssueCount = scan.privacyIssueCount

                let input = HealthScoreInput(
                    totalStorageBytes: scan.totalStorage,
                    usedStorageBytes: scan.usedStorage,
                    totalPhotos: scan.photoCount,
                    duplicatePhotos: scan.duplicatePhotoCount,
                    totalContacts: scan.contactCount,
                    duplicateContacts: scan.duplicateContactCount,
                    batteryHealth: scan.batteryHealth,
                    batteryLevel: batteryLevel,
                    totalPermissions: PermissionType.allCases.filter {
                        !PermissionType.unscorable.contains($0)
                    }.count,
                    appropriatelySetPermissions: PermissionType.allCases.filter {
                        !PermissionType.unscorable.contains($0) &&
                        permissionManager.status(for: $0) != .notDetermined
                    }.count
                )

                let result = HealthScoreCalculator.calculate(from: input)
                healthResult = result
                healthScore = result.compositeScore
                quickWins = generateQuickWins(from: scan)
            } else if let currentInfo {
                batteryLevel = currentInfo.level
            }
        } catch {
            // Gracefully handle — dashboard shows empty state
            if let currentInfo {
                batteryLevel = currentInfo.level
            }
        }
    }

    // MARK: - Quick Wins

    private func generateQuickWins(from scan: ScanResult) -> [QuickWin] {
        var wins: [QuickWin] = []

        if scan.duplicatePhotoCount > 0 {
            wins.append(QuickWin(
                id: "photos",
                icon: "photo.on.rectangle",
                title: "Clean up \(scan.duplicatePhotoCount) duplicate photos",
                benefit: formatBytes(scan.duplicatePhotoSize),
                benefitBytes: scan.duplicatePhotoSize
            ))
        }

        if scan.duplicateContactCount > 0 {
            wins.append(QuickWin(
                id: "contacts",
                icon: "person.2",
                title: "Merge \(scan.duplicateContactCount) duplicate contacts",
                benefit: "\(scan.duplicateContactCount) contacts",
                benefitBytes: 0
            ))
        }

        let usedPercent = scan.totalStorage > 0
            ? Double(scan.usedStorage) / Double(scan.totalStorage) * 100
            : 0
        if usedPercent > 75 {
            let reclaimable = scan.usedStorage - (scan.totalStorage * 3 / 4)
            wins.append(QuickWin(
                id: "storage",
                icon: "internaldrive",
                title: "Free up storage space",
                benefit: formatBytes(max(0, reclaimable)),
                benefitBytes: max(0, reclaimable)
            ))
        }

        if scan.privacyIssueCount > 0 {
            wins.append(QuickWin(
                id: "privacy",
                icon: "lock.shield",
                title: "Review \(scan.privacyIssueCount) privacy settings",
                benefit: "\(scan.privacyIssueCount) items",
                benefitBytes: 0
            ))
        }

        // Sort by space savings descending, then return top 3
        return Array(wins.sorted { $0.benefitBytes > $1.benefitBytes }.prefix(3))
    }

    // MARK: - Helpers

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func statusForCard(_ key: String) -> CardStatus {
        guard let result = healthResult else { return .neutral("--") }
        switch key {
        case "storage":
            let score = result.storageScore
            return score >= HealthScoreCalculator.goodThreshold ? .good("\(score)%") : .warning("\(score)%")
        case "photos":
            let score = result.photoScore
            return score >= HealthScoreCalculator.goodThreshold ? .good("\(score)%") : .warning("\(score)%")
        case "contacts":
            let score = result.contactScore
            return score >= HealthScoreCalculator.goodThreshold ? .good("\(score)%") : .warning("\(score)%")
        case "battery":
            let score = result.batteryScore
            return score >= HealthScoreCalculator.goodThreshold ? .good("\(score)%") : .warning("\(score)%")
        case "privacy":
            let score = result.privacyScore
            return score >= HealthScoreCalculator.goodThreshold ? .good("\(score)%") : .warning("\(score)%")
        default:
            return .neutral("--")
        }
    }

    func descriptionForCard(_ key: String) -> String {
        switch key {
        case "storage":
            if totalStorage == 0 { return "Tap to check your storage." }
            return "\(formatBytes(freeStorage)) free of \(formatBytes(totalStorage))"
        case "photos":
            if duplicatePhotoCount == 0 { return "Your photos look great." }
            return "\(duplicatePhotoCount) duplicate photos found"
        case "contacts":
            if duplicateContactCount == 0 { return "Your contacts are tidy." }
            return "\(duplicateContactCount) possible duplicates"
        case "battery":
            let pct = Int(batteryLevel * 100)
            return "Battery at \(pct)%"
        case "privacy":
            if privacyIssueCount == 0 { return "Your privacy looks good." }
            return "\(privacyIssueCount) settings to review"
        default:
            return ""
        }
    }

    func iconForCard(_ key: String) -> String {
        switch key {
        case "storage":  return "internaldrive.fill"
        case "photos":   return "photo.on.rectangle.fill"
        case "contacts": return "person.2.fill"
        case "battery":  return "battery.75percent"
        case "privacy":  return "lock.shield.fill"
        default:         return "questionmark.circle"
        }
    }

    func titleForCard(_ key: String) -> String {
        switch key {
        case "storage":  return "Storage"
        case "photos":   return "Photos"
        case "contacts": return "Contacts"
        case "battery":  return "Battery"
        case "privacy":  return "Privacy"
        default:         return key.capitalized
        }
    }

    // MARK: - Testing Support

    #if DEBUG
    func injectForTesting(healthScore: Int, healthResult: HealthScoreResult?, quickWins: [QuickWin] = []) {
        self.healthScore = healthScore
        self.healthResult = healthResult
        self.quickWins = quickWins
    }
    #endif
}

// MARK: - Quick Win Model

struct QuickWin: Identifiable {
    let id: String
    let icon: String
    let title: String
    let benefit: String
    let benefitBytes: Int64
}
