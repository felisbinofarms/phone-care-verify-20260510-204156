import Foundation
import Testing
@testable import PhoneCare

@MainActor
@Suite("BatteryViewModel")
struct BatteryViewModelTests {

    // MARK: - chargingIcon

    @Test("chargingIcon shows bolt when charging")
    func chargingIconCharging() {
        let vm = BatteryViewModel()
        vm.injectForTesting(level: 0.5, isCharging: true, thermalState: 0)
        #expect(vm.chargingIcon == "bolt.fill")
    }

    @Test("chargingIcon maps battery level to correct symbol")
    func chargingIconLevels() {
        let vm = BatteryViewModel()
        let cases: [(Double, String)] = [
            (0.90, "battery.100percent"),
            (0.60, "battery.75percent"),
            (0.40, "battery.50percent"),
            (0.10, "battery.25percent"),
        ]
        for (level, expected) in cases {
            vm.injectForTesting(level: level, isCharging: false, thermalState: 0)
            #expect(vm.chargingIcon == expected, "level \(level) should give \(expected)")
        }
    }

    // MARK: - thermalStateText

    @Test("thermalStateText maps thermal values to readable strings")
    func thermalStateText() {
        let vm = BatteryViewModel()
        let cases: [(Int, String)] = [
            (0, "Normal"),
            (1, "Slightly warm"),
            (2, "Warm"),
            (3, "Hot"),
            (99, "Normal"),
        ]
        for (state, expected) in cases {
            vm.injectForTesting(level: 0.5, isCharging: false, thermalState: state)
            #expect(vm.thermalStateText == expected)
        }
    }

    // MARK: - thermalStateColor (anti-scareware: never red)

    @Test("thermalStateColor never returns red for any thermal state")
    func thermalStateColorNeverRed() {
        let vm = BatteryViewModel()
        for state in 0...3 {
            vm.injectForTesting(level: 0.5, isCharging: false, thermalState: state)
            let color = vm.thermalStateColor
            // Must be pcAccent or pcWarning — never pcError/red
            #expect(color == .pcAccent || color == .pcWarning)
        }
    }

    // MARK: - levelPercentage

    @Test("levelPercentage converts 0-1 range to 0-100 Int")
    func levelPercentage() {
        let vm = BatteryViewModel()
        let cases: [(Double, Int)] = [(0.0, 0), (0.5, 50), (1.0, 100), (0.857, 85)]
        for (level, expected) in cases {
            vm.injectForTesting(level: level, isCharging: false, thermalState: 0)
            #expect(vm.levelPercentage == expected)
        }
    }

    // MARK: - capacityText

    @Test("capacityText shows Not available when nil")
    func capacityTextNil() {
        let vm = BatteryViewModel()
        #expect(vm.capacityText == "Not available")
    }

    // MARK: - filteredSnapshots

    @Test("filteredSnapshots returns only snapshots within selected range")
    func filteredSnapshotsRange() {
        let vm = BatteryViewModel()
        let recent = BatterySnapshot(date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!, level: 0.8)
        let old = BatterySnapshot(date: Calendar.current.date(byAdding: .day, value: -100, to: Date())!, level: 0.7)
        vm.injectSnapshots([recent, old])
        vm.selectedTimeRange = .thirtyDays
        let filtered = vm.filteredSnapshots
        #expect(filtered.contains { $0.id == recent.id })
        #expect(!filtered.contains { $0.id == old.id })
    }

    // MARK: - BatteryTimeRange

    @Test("BatteryTimeRange day counts are correct")
    func batteryTimeRangeDays() {
        #expect(BatteryTimeRange.oneDay.days == 1)
        #expect(BatteryTimeRange.thirtyDays.days == 30)
        #expect(BatteryTimeRange.ninetyDays.days == 90)
        #expect(BatteryTimeRange.oneYear.days == 365)
    }

    // MARK: - Error-path / resilience (#118)
    //
    // `BatteryViewModel.load(dataManager:)` does not have an injectable error
    // seam (`DataManager` is concrete), so these tests exercise the reachable
    // defensive paths: empty store and repeated calls. The behavioral contract
    // we lock in is that `load` always populates `tips`, never crashes, and
    // leaves `isLoading == false` when it returns, even with no scan history.

    @Test("load with empty DataManager populates tips and leaves isLoading false")
    func load_emptyDataManager_populatesTipsAndShowsDefaults() {
        let vm = BatteryViewModel()
        let dataManager = DataManager(inMemory: true)
        vm.load(dataManager: dataManager)

        // General tips always render regardless of data state.
        #expect(vm.tips.count > 0)
        // Defer should clear the loading flag.
        #expect(vm.isLoading == false)
        // No scan history means defaults stay.
        #expect(vm.snapshots.isEmpty)
        #expect(vm.maxCapacity == nil)
    }

    @Test("load called repeatedly does not duplicate snapshots or tips")
    func load_calledRepeatedly_remainsConsistent() {
        let vm = BatteryViewModel()
        let dataManager = DataManager(inMemory: true)

        vm.load(dataManager: dataManager)
        let firstSnapshotsCount = vm.snapshots.count
        let firstTipsCount = vm.tips.count

        vm.load(dataManager: dataManager)
        // Idempotency: repeated load must not accumulate state.
        #expect(vm.snapshots.count == firstSnapshotsCount)
        #expect(vm.tips.count == firstTipsCount)
        #expect(vm.isLoading == false)
    }
}
