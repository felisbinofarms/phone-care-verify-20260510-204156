import SwiftUI
import SwiftData

enum BatteryTimeRange: String, CaseIterable, Identifiable {
    case oneDay = "1 Day"
    case thirtyDays = "30 Days"
    case ninetyDays = "90 Days"
    case oneYear = "1 Year"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .oneDay:      return 1
        case .thirtyDays:  return 30
        case .ninetyDays:  return 90
        case .oneYear:     return 365
        }
    }
}

struct BatteryTip: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
}

@MainActor
@Observable
final class BatteryViewModel {

    // MARK: - State

    private(set) var currentLevel: Double = 0 // 0-1
    private(set) var isCharging: Bool = false
    private(set) var thermalState: Int = 0
    private(set) var isLowPowerMode: Bool = false
    private(set) var maxCapacity: Double?
    private(set) var snapshots: [BatterySnapshot] = []
    private(set) var tips: [BatteryTip] = []
    private(set) var isLoading: Bool = false

    var selectedTimeRange: BatteryTimeRange = .oneDay

    // MARK: - Computed

    var levelPercentage: Int {
        Int(currentLevel * 100)
    }

    var chargingStateText: String {
        if isCharging { return "Charging" }
        return "On Battery"
    }

    var chargingIcon: String {
        if isCharging { return "bolt.fill" }
        if currentLevel > 0.75 { return "battery.100percent" }
        if currentLevel > 0.5 { return "battery.75percent" }
        if currentLevel > 0.25 { return "battery.50percent" }
        return "battery.25percent"
    }

    var thermalStateText: String {
        switch thermalState {
        case 0: return "Normal"
        case 1: return "Slightly warm"
        case 2: return "Warm"
        case 3: return "Hot"
        default: return "Normal"
        }
    }

    var thermalStateColor: Color {
        switch thermalState {
        case 0, 1: return .pcAccent
        case 2: return .pcWarning
        case 3: return .pcWarning
        default: return .pcAccent
        }
    }

    var filteredSnapshots: [BatterySnapshot] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -selectedTimeRange.days,
            to: Date()
        ) ?? Date()
        return snapshots.filter { $0.date >= cutoff }
    }

    var capacityText: String {
        if let cap = maxCapacity {
            return "\(Int(cap * 100))%"
        }
        return "Not available"
    }

    // MARK: - Load

    func load(dataManager: DataManager) {
        isLoading = true
        defer { isLoading = false }

        // Load current state from latest scan
        do {
            if let scan = try dataManager.latestScanResult() {
                currentLevel = scan.batteryLevel
                maxCapacity = scan.batteryHealth
            }

            // Load snapshot history
            snapshots = try dataManager.fetch(
                BatterySnapshot.self,
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )

            // Use most recent snapshot for current state details
            if let latest = snapshots.first {
                currentLevel = latest.level
                isCharging = latest.isCharging
                thermalState = latest.thermalState
                isLowPowerMode = latest.isLowPowerMode
                if let cap = latest.maxCapacity {
                    maxCapacity = cap
                }
            }

            tips = generateTips()
        } catch {
            // Show defaults
            tips = generateTips()
        }
    }

    // MARK: - Tips

    private func generateTips() -> [BatteryTip] {
        var result: [BatteryTip] = []

        // Condition-based tips (highest priority first)

        if thermalState >= 2 {
            result.append(BatteryTip(
                id: "thermal",
                icon: "thermometer.sun.fill",
                title: "Phone is warm",
                description: "Try removing the case and moving to a cooler spot. Avoid using it while charging."
            ))
        }

        if let cap = maxCapacity, cap < 0.8 {
            result.append(BatteryTip(
                id: "replace",
                icon: "wrench.and.screwdriver.fill",
                title: "Battery has aged",
                description: "Your battery capacity is at \(Int(cap * 100))%. Avoid draining to 0% to slow further wear. You may want to get it replaced."
            ))
        } else if let cap = maxCapacity, cap >= 0.9 {
            result.append(BatteryTip(
                id: "healthy",
                icon: "heart.fill",
                title: "Battery is in great shape",
                description: "Your battery capacity is at \(Int(cap * 100))%. Keep it healthy by avoiding extreme heat and cold."
            ))
        }

        if isCharging && currentLevel > 0.8 {
            result.append(BatteryTip(
                id: "unplug",
                icon: "powerplug.fill",
                title: "Good time to unplug",
                description: "Your battery is at \(levelPercentage)%. Unplugging around 80% helps preserve long-term battery health."
            ))
        }

        if !isLowPowerMode && currentLevel < 0.3 {
            result.append(BatteryTip(
                id: "lowPower",
                icon: "bolt.slash.fill",
                title: "Try Low Power Mode",
                description: "Low Power Mode reduces background activity and can help your battery last longer."
            ))
        }

        // Always-shown general tips

        result.append(BatteryTip(
            id: "charging",
            icon: "battery.100percent.bolt",
            title: "Charge between 20% and 80%",
            description: "Keeping your battery in this range can help maintain its long-term health."
        ))

        result.append(BatteryTip(
            id: "optimized",
            icon: "gearshape.fill",
            title: "Enable Optimized Charging",
            description: "Turn on Optimized Battery Charging in Settings > Battery to let your iPhone learn your routine and reduce battery aging."
        ))

        result.append(BatteryTip(
            id: "brightness",
            icon: "sun.max.fill",
            title: "Use auto-brightness",
            description: "Auto-brightness adjusts your screen to save battery based on your surroundings."
        ))

        result.append(BatteryTip(
            id: "overnight",
            icon: "moon.fill",
            title: "Avoid overnight charging without Optimized Charging",
            description: "Charging all night can add heat stress. If you charge overnight, make sure Optimized Charging is on."
        ))

        return result
    }

    // MARK: - Testing Support

    #if DEBUG
    func injectForTesting(level: Double, isCharging: Bool, thermalState: Int) {
        currentLevel = level
        self.isCharging = isCharging
        self.thermalState = thermalState
    }
    func injectSnapshots(_ shots: [BatterySnapshot]) {
        snapshots = shots
    }
    #endif
}
