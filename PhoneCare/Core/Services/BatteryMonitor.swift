import UIKit
import Foundation
import OSLog

// MARK: - Battery Info

struct BatteryInfo: Sendable {
    let level: Double
    let state: BatteryState
    let thermalState: ThermalState
    let isLowPowerMode: Bool

    enum BatteryState: String, Sendable {
        case unknown
        case unplugged
        case charging
        case full

        var displayName: String {
            switch self {
            case .unknown: return "Unknown"
            case .unplugged: return "Not Charging"
            case .charging: return "Charging"
            case .full: return "Fully Charged"
            }
        }

        var icon: String {
            switch self {
            case .unknown: return "battery.0percent"
            case .unplugged: return "battery.50percent"
            case .charging: return "battery.100percent.bolt"
            case .full: return "battery.100percent"
            }
        }
    }

    enum ThermalState: Int, Sendable {
        case nominal = 0
        case fair = 1
        case serious = 2
        case critical = 3

        var displayName: String {
            switch self {
            case .nominal: return "Normal"
            case .fair: return "Slightly Warm"
            case .serious: return "Warm"
            case .critical: return "Very Warm"
            }
        }
    }

    var levelPercentage: Int {
        Int((level * 100).rounded())
    }

    var levelIcon: String {
        switch levelPercentage {
        case 0..<10: return "battery.0percent"
        case 10..<35: return "battery.25percent"
        case 35..<65: return "battery.50percent"
        case 65..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

}

// MARK: - Battery Monitor

@MainActor
@Observable
final class BatteryMonitor {

    // MARK: - State

    private(set) var currentInfo: BatteryInfo = BatteryInfo(
        level: 0,
        state: .unknown,
        thermalState: .nominal,
        isLowPowerMode: false
    )

    private(set) var snapshots: [BatterySnapshot] = []
    private(set) var isMonitoring: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhoneCare", category: "BatteryMonitor")
    private var levelObservation: NSObjectProtocol?
    private var stateObservation: NSObjectProtocol?
    private var thermalObservation: NSObjectProtocol?
    private var powerModeObservation: NSObjectProtocol?

    // MARK: - Start Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        UIDevice.current.isBatteryMonitoringEnabled = true
        readCurrentState()

        let center = NotificationCenter.default

        levelObservation = center.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentState()
            }
        }

        stateObservation = center.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentState()
            }
        }

        thermalObservation = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentState()
            }
        }

        powerModeObservation = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentState()
            }
        }

        logger.info("Battery monitoring started.")
    }

    // MARK: - Stop Monitoring

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        let center = NotificationCenter.default
        if let obs = levelObservation { center.removeObserver(obs) }
        if let obs = stateObservation { center.removeObserver(obs) }
        if let obs = thermalObservation { center.removeObserver(obs) }
        if let obs = powerModeObservation { center.removeObserver(obs) }

        levelObservation = nil
        stateObservation = nil
        thermalObservation = nil
        powerModeObservation = nil

        UIDevice.current.isBatteryMonitoringEnabled = false
        logger.info("Battery monitoring stopped.")
    }

    // MARK: - Deinit

    // MARK: - Read Current State

    func readCurrentState() {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo

        let level = Double(device.batteryLevel)
        let state: BatteryInfo.BatteryState = {
            switch device.batteryState {
            case .unknown: return .unknown
            case .unplugged: return .unplugged
            case .charging: return .charging
            case .full: return .full
            @unknown default: return .unknown
            }
        }()

        let thermal: BatteryInfo.ThermalState = {
            BatteryInfo.ThermalState(rawValue: processInfo.thermalState.rawValue) ?? .nominal
        }()

        currentInfo = BatteryInfo(
            level: max(0, level),
            state: state,
            thermalState: thermal,
            isLowPowerMode: processInfo.isLowPowerModeEnabled
        )
    }

    // MARK: - Take Snapshot

    func takeSnapshot(dataManager: DataManager) async {
        readCurrentState()

        let snapshot = BatterySnapshot(
            level: currentInfo.level,
            isCharging: currentInfo.state == .charging || currentInfo.state == .full,
            thermalState: currentInfo.thermalState.rawValue,
            maxCapacity: nil,  // iOS does not expose max capacity via public API
            isLowPowerMode: currentInfo.isLowPowerMode
        )

        do {
            try dataManager.save(snapshot)
            let levelPercent = Int(self.currentInfo.level * 100)
            logger.info("Battery snapshot saved: \(levelPercent)%")
        } catch {
            logger.error("Failed to save battery snapshot: \(error.localizedDescription)")
        }
    }

    // MARK: - Take Daily Snapshot (only if none today)

    func takeDailySnapshotIfNeeded(dataManager: DataManager) async {
        do {
            let today = Calendar.current.startOfDay(for: Date())
            let existing = try dataManager.fetch(
                BatterySnapshot.self,
                predicate: #Predicate<BatterySnapshot> { $0.date >= today }
            )

            if existing.isEmpty {
                await takeSnapshot(dataManager: dataManager)
            }
        } catch {
            logger.error("Failed to check for existing snapshot: \(error.localizedDescription)")
            await takeSnapshot(dataManager: dataManager)
        }
    }

    // MARK: - Load History

    func loadHistory(from dataManager: DataManager) async {
        do {
            snapshots = try dataManager.fetch(
                BatterySnapshot.self,
                sortBy: [SortDescriptor(\BatterySnapshot.date, order: .reverse)]
            )
        } catch {
            logger.error("Failed to load battery history: \(error.localizedDescription)")
            snapshots = []
        }
    }

    // MARK: - Trend Data

    /// Returns snapshots from the last N days for chart display
    func recentSnapshots(days: Int = 30) -> [BatterySnapshot] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        return snapshots.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    /// Average battery level over recent history
    var averageLevel: Double {
        let recent = recentSnapshots(days: 7)
        guard !recent.isEmpty else { return currentInfo.level }
        return recent.reduce(0.0) { $0 + $1.level } / Double(recent.count)
    }

}
