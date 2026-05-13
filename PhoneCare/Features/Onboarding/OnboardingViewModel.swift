import Foundation
import OSLog

// MARK: - Onboarding Goal

enum OnboardingGoal: String, CaseIterable, Identifiable, Sendable {
    case freeUpSpace
    case cleanPhotos
    case organizeContacts
    case checkBattery
    case reviewPrivacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeUpSpace: return "Free up space"
        case .cleanPhotos: return "Clean up photos"
        case .organizeContacts: return "Organize contacts"
        case .checkBattery: return "Check battery"
        case .reviewPrivacy: return "Review privacy"
        }
    }

    var icon: String {
        switch self {
        case .freeUpSpace: return "externaldrive.fill"
        case .cleanPhotos: return "photo.on.rectangle.fill"
        case .organizeContacts: return "person.2.fill"
        case .checkBattery: return "battery.75percent"
        case .reviewPrivacy: return "lock.shield.fill"
        }
    }

    /// Maps this goal to a dashboard card ID for ordering
    var cardID: String {
        switch self {
        case .freeUpSpace: return "storage"
        case .cleanPhotos: return "photos"
        case .organizeContacts: return "contacts"
        case .checkBattery: return "battery"
        case .reviewPrivacy: return "privacy"
        }
    }
}

// MARK: - Phone Feeling

enum PhoneFeeling: String, CaseIterable, Identifiable, Sendable {
    case great
    case aLittleSlow
    case reallyStruggling
    case notSure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .great: return "Great"
        case .aLittleSlow: return "A little slow"
        case .reallyStruggling: return "Really struggling"
        case .notSure: return "Not sure"
        }
    }

    var icon: String {
        switch self {
        case .great: return "face.smiling.fill"
        case .aLittleSlow: return "tortoise.fill"
        case .reallyStruggling: return "exclamationmark.circle.fill"
        case .notSure: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Tech Savvy Level

enum TechSavvyLevel: Int, CaseIterable, Identifiable, Sendable {
    case beginner = 0
    case intermediate = 1
    case advanced = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    var description: String {
        switch self {
        case .beginner: return "I like things simple and easy to follow."
        case .intermediate: return "I know my way around, but could use some help."
        case .advanced: return "I am comfortable with most phone settings."
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .intermediate: return "star.fill"
        case .advanced: return "bolt.fill"
        }
    }
}

// MARK: - Scan Stage

enum ScanStage: String, Sendable {
    case idle
    case storage
    case photos
    case contacts
    case battery
    case privacy
    case complete

    var message: String {
        switch self {
        case .idle: return "Getting ready..."
        case .storage: return "Checking storage..."
        case .photos: return "Scanning photos..."
        case .contacts: return "Reviewing contacts..."
        case .battery: return "Checking battery..."
        case .privacy: return "Reviewing privacy..."
        case .complete: return "All done!"
        }
    }
}

// MARK: - Onboarding Scan Results

struct OnboardingScanResults: Sendable {
    var storageResult: StorageAnalysisResult?
    var photoResult: PhotoAnalysisResult?
    var contactResult: ContactAnalysisResult?
    var batteryInfo: BatteryInfo?
    var privacyResult: PrivacyAuditResult?
    var healthScore: Int = 0
}

// MARK: - View Model

@MainActor
@Observable
final class OnboardingViewModel {

    // MARK: - Personalization State

    var selectedGoals: Set<OnboardingGoal> = []
    var phoneFeeling: PhoneFeeling?
    var techSavvyLevel: TechSavvyLevel = .intermediate

    // MARK: - Scan State

    private(set) var scanStage: ScanStage = .idle
    private(set) var scanProgress: Double = 0.0
    private(set) var isScanning: Bool = false
    private(set) var scanResults: OnboardingScanResults = OnboardingScanResults()

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhoneCare", category: "OnboardingViewModel")

    // MARK: - Goal Helpers

    func toggleGoal(_ goal: OnboardingGoal) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else {
            selectedGoals.insert(goal)
        }
    }

    var hasSelectedGoals: Bool {
        !selectedGoals.isEmpty
    }

    // MARK: - Card Order from Goals

    /// Computes dashboard card order based on selected goals.
    /// Selected goals appear first, remaining cards follow in default order.
    func computeCardOrder() -> [String] {
        let defaultOrder = ["healthScore", "storage", "photos", "contacts", "battery", "privacy"]

        let goalCardIDs = OnboardingGoal.allCases
            .filter { selectedGoals.contains($0) }
            .map(\.cardID)

        var ordered: [String] = ["healthScore"]
        ordered.append(contentsOf: goalCardIDs)

        for card in defaultOrder where !ordered.contains(card) {
            ordered.append(card)
        }

        return ordered
    }

    // MARK: - Personal Plan

    struct PlanItem: Identifiable, Sendable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let priority: Int
    }

    var personalPlan: [PlanItem] {
        var items: [PlanItem] = []
        var priority = 0

        // Storage-based items
        if let storage = scanResults.storageResult {
            let usedPercent = storage.usedPercentage
            if usedPercent > 80 {
                priority += 1
                items.append(PlanItem(
                    icon: "externaldrive.fill",
                    title: "Free up storage space",
                    detail: "Your phone is \(Int(usedPercent))% full. Let's find things to clean up.",
                    priority: priority
                ))
            }
        }

        // Photo-based items
        if let photos = scanResults.photoResult {
            if photos.duplicateCount > 0 {
                priority += 1
                items.append(PlanItem(
                    icon: "photo.on.rectangle.fill",
                    title: "Clean up \(photos.duplicateCount) duplicate photos",
                    detail: "We found photos that look the same. Removing extras could save space.",
                    priority: priority
                ))
            }
            if photos.screenshotCount > 10 {
                priority += 1
                items.append(PlanItem(
                    icon: "camera.viewfinder",
                    title: "Review \(photos.screenshotCount) screenshots",
                    detail: "Old screenshots can add up. Take a look and keep the ones you need.",
                    priority: priority
                ))
            }
        }

        // Contact-based items
        if let contacts = scanResults.contactResult, contacts.duplicateCount > 0 {
            priority += 1
            items.append(PlanItem(
                icon: "person.2.fill",
                title: "Merge \(contacts.duplicateCount) duplicate contacts",
                detail: "Some contacts appear more than once. We can combine them for you.",
                priority: priority
            ))
        }

        // Battery items
        if let battery = scanResults.batteryInfo {
            if battery.isLowPowerMode {
                priority += 1
                items.append(PlanItem(
                    icon: "battery.25percent",
                    title: "Battery tips",
                    detail: "Low Power Mode is on right now. We will show tips to help your battery last longer.",
                    priority: priority
                ))
            }
        }

        // Privacy items
        if let privacy = scanResults.privacyResult, privacy.notDeterminedCount > 0 {
            priority += 1
            items.append(PlanItem(
                icon: "lock.shield.fill",
                title: "Review \(privacy.notDeterminedCount) privacy settings",
                detail: "Some permissions have not been reviewed. A quick check keeps you in control.",
                priority: priority
            ))
        }

        // If no specific items, add a general one
        if items.isEmpty {
            items.append(PlanItem(
                icon: "checkmark.circle.fill",
                title: "Your phone looks good!",
                detail: "Keep it that way with regular check-ups. We will remind you.",
                priority: 1
            ))
        }

        return items.sorted { $0.priority < $1.priority }
    }

    // MARK: - Run Scan

    func runScan(
        storageAnalyzer: StorageAnalyzer,
        photoAnalyzer: PhotoAnalyzer,
        contactAnalyzer: ContactAnalyzer,
        batteryMonitor: BatteryMonitor,
        privacyAuditor: PrivacyAuditor,
        permissionManager: PermissionManager
    ) async {
        isScanning = true
        scanProgress = 0.0

        // Stage 1: Storage
        scanStage = .storage
        scanProgress = 0.05
        let storageResult = await storageAnalyzer.analyze()
        scanResults.storageResult = storageResult
        scanProgress = 0.2

        // Stage 2: Photos
        scanStage = .photos
        scanProgress = 0.25
        let photoResult = await photoAnalyzer.analyze()
        scanResults.photoResult = photoResult
        scanProgress = 0.5

        // Stage 3: Contacts
        scanStage = .contacts
        scanProgress = 0.55
        let contactResult = await contactAnalyzer.analyze()
        scanResults.contactResult = contactResult
        scanProgress = 0.7

        // Stage 4: Battery
        scanStage = .battery
        scanProgress = 0.75
        batteryMonitor.startMonitoring()
        batteryMonitor.readCurrentState()
        scanResults.batteryInfo = batteryMonitor.currentInfo
        batteryMonitor.stopMonitoring()
        scanProgress = 0.8

        // Stage 5: Privacy
        scanStage = .privacy
        scanProgress = 0.85
        let privacyResult = await privacyAuditor.performAudit(permissionManager: permissionManager)
        scanResults.privacyResult = privacyResult
        scanProgress = 0.95

        // Calculate health score
        let healthInput = HealthScoreInput(
            totalStorageBytes: storageResult.totalBytes,
            usedStorageBytes: storageResult.usedBytes,
            totalPhotos: photoResult.totalPhotos,
            duplicatePhotos: photoResult.duplicateCount,
            totalContacts: contactResult.totalContacts,
            duplicateContacts: contactResult.duplicateCount,
            batteryHealth: nil,
            batteryLevel: batteryMonitor.currentInfo.level,
            totalPermissions: privacyResult.summaries.count,
            appropriatelySetPermissions: privacyResult.summaries.filter(\.isAppropriate).count
        )

        let healthResult = HealthScoreCalculator.calculate(from: healthInput)
        scanResults.healthScore = healthResult.compositeScore

        scanStage = .complete
        scanProgress = 1.0
        isScanning = false

        logger.info("Onboarding scan complete. Health score: \(healthResult.compositeScore)")
    }

    // MARK: - Save to DataManager

    func savePreferences(to dataManager: DataManager, appState: AppState) async {
        do {
            let prefs = try dataManager.userPreferences()
            prefs.goals = selectedGoals.map(\.rawValue)
            prefs.phoneFeeling = phoneFeeling?.rawValue ?? ""
            prefs.techSavvyLevel = techSavvyLevel.rawValue
            prefs.cardOrder = computeCardOrder()
            prefs.onboardingCompleted = true
            prefs.onboardingCompletedAt = Date()

            try dataManager.saveContext()

            // Save scan result
            if let storage = scanResults.storageResult,
               let photos = scanResults.photoResult,
               let contacts = scanResults.contactResult {
                if let battery = scanResults.batteryInfo {
                    let snapshot = BatterySnapshot(
                        level: battery.level,
                        isCharging: battery.state == .charging || battery.state == .full,
                        thermalState: battery.thermalState.rawValue,
                        maxCapacity: nil,
                        isLowPowerMode: battery.isLowPowerMode
                    )
                    try dataManager.save(snapshot)
                }

                let scanResult = ScanResult(
                    totalStorage: storage.totalBytes,
                    usedStorage: storage.usedBytes,
                    photoCount: photos.totalPhotos,
                    duplicatePhotoCount: photos.duplicateCount,
                    duplicatePhotoSize: photos.estimatedDuplicateSavings,
                    contactCount: contacts.totalContacts,
                    duplicateContactCount: contacts.duplicateCount,
                    batteryLevel: scanResults.batteryInfo?.level ?? 0,
                    privacyIssueCount: scanResults.privacyResult?.notDeterminedCount ?? 0,
                    healthScore: scanResults.healthScore
                )
                try dataManager.save(scanResult)
            }

            // Mark onboarding complete
            appState.hasCompletedOnboarding = true

            logger.info("Onboarding preferences saved successfully.")
        } catch {
            logger.error("Failed to save onboarding preferences: \(error.localizedDescription)")
        }
    }
}
