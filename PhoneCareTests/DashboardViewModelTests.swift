import Testing
@testable import PhoneCare

@Suite("DashboardViewModel")
@MainActor
struct DashboardViewModelTests {

    // MARK: - Initial State

    @Test("Initial healthScore is 0")
    func initialHealthScore_isZero() {
        let vm = DashboardViewModel()
        #expect(vm.healthScore == 0)
    }

    @Test("Initial isLoading is false")
    func initialIsLoading_isFalse() {
        let vm = DashboardViewModel()
        #expect(vm.isLoading == false)
    }

    @Test("Initial quickWins is empty")
    func initialQuickWins_isEmpty() {
        let vm = DashboardViewModel()
        #expect(vm.quickWins.isEmpty)
    }

    @Test("Initial healthResult is nil")
    func initialHealthResult_isNil() {
        let vm = DashboardViewModel()
        #expect(vm.healthResult == nil)
    }

    // MARK: - Health Score Range (0–100)

    @Test("HealthScoreCalculator.calculate returns a score in 0–100 for typical inputs")
    func healthScore_typicalInputs_inRange() {
        let input = HealthScoreInput(
            totalStorageBytes: 128_000_000_000,
            usedStorageBytes: 80_000_000_000,
            totalPhotos: 500,
            duplicatePhotos: 50,
            totalContacts: 200,
            duplicateContacts: 20,
            batteryHealth: 0.85,
            batteryLevel: 0.6,
            totalPermissions: 7,
            appropriatelySetPermissions: 5
        )
        let result = HealthScoreCalculator.calculate(from: input)
        #expect(result.compositeScore >= 0)
        #expect(result.compositeScore <= 100)
    }

    @Test("HealthScoreCalculator.calculate returns 100 for perfect inputs")
    func healthScore_perfectInputs_100() {
        let input = HealthScoreInput(
            totalStorageBytes: 100,
            usedStorageBytes: 0,
            totalPhotos: 100,
            duplicatePhotos: 0,
            totalContacts: 50,
            duplicateContacts: 0,
            batteryHealth: 1.0,
            batteryLevel: 1.0,
            totalPermissions: 7,
            appropriatelySetPermissions: 7
        )
        let result = HealthScoreCalculator.calculate(from: input)
        #expect(result.compositeScore == 100)
    }

    @Test("HealthScoreCalculator.calculate returns 0 for worst-case inputs")
    func healthScore_worstInputs_0() {
        let input = HealthScoreInput(
            totalStorageBytes: 100,
            usedStorageBytes: 100,
            totalPhotos: 10,
            duplicatePhotos: 10,
            totalContacts: 10,
            duplicateContacts: 10,
            batteryHealth: 0.0,
            batteryLevel: 0.0,
            totalPermissions: 10,
            appropriatelySetPermissions: 0
        )
        let result = HealthScoreCalculator.calculate(from: input)
        #expect(result.compositeScore == 0)
    }

    // MARK: - statusForCard (good when score > 50)

    @Test("statusForCard returns .good when storage score is above 50")
    func statusForCard_storage_goodAbove50() {
        let vm = DashboardViewModel()
        vm.injectForTesting(healthScore: 75, healthResult: makeHealthResult(storageScore: 75))
        if case .good = vm.statusForCard("storage") { }
        else { Issue.record("Expected .good for storage score 75") }
    }

    @Test("statusForCard returns .warning when storage score is 50 or below")
    func statusForCard_storage_warningAt50OrBelow() {
        let vm = DashboardViewModel()
        vm.injectForTesting(healthScore: 40, healthResult: makeHealthResult(storageScore: 40))
        if case .warning = vm.statusForCard("storage") { }
        else { Issue.record("Expected .warning for storage score 40") }
    }

    @Test("statusForCard returns .neutral when healthResult is nil")
    func statusForCard_nilHealthResult_neutral() {
        let vm = DashboardViewModel()
        vm.injectForTesting(healthScore: 0, healthResult: nil)
        if case .neutral = vm.statusForCard("storage") { }
        else { Issue.record("Expected .neutral when healthResult is nil") }
    }

    // MARK: - refresh() triggers state update

    @Test("refresh with empty in-memory store completes without crash, isLoading false")
    func refresh_emptyStore_isLoadingFalse() {
        let vm = DashboardViewModel()
        let dataManager = DataManager(inMemory: true)
        let permManager = PermissionManager()
        vm.refresh(dataManager: dataManager, permissionManager: permManager)
        // After synchronous load with no scan data, isLoading must be false
        #expect(vm.isLoading == false)
    }

    @Test("refresh sets healthScore to 0 when no scan data exists")
    func refresh_noScanData_healthScoreZero() {
        let vm = DashboardViewModel()
        let dataManager = DataManager(inMemory: true)
        let permManager = PermissionManager()
        vm.refresh(dataManager: dataManager, permissionManager: permManager)
        #expect(vm.healthScore == 0)
    }

    @Test("refresh overlays live battery level when current info is provided")
    func refresh_withCurrentInfo_overlaysBatteryLevel() {
        let vm = DashboardViewModel()
        let dataManager = DataManager(inMemory: true)
        let permManager = PermissionManager()
        let currentInfo = BatteryInfo(
            level: 0.34,
            state: .unplugged,
            thermalState: .nominal,
            isLowPowerMode: false
        )

        vm.refresh(
            dataManager: dataManager,
            permissionManager: permManager,
            currentInfo: currentInfo
        )

        #expect(vm.descriptionForCard("battery") == "Battery at 34%")
    }

    // MARK: - quickWins populated when health score is low

    @Test("quickWins injected with two items are accessible on the view model")
    func quickWins_injected_populated() {
        let vm = DashboardViewModel()
        let wins = [
            QuickWin(id: "photos",   icon: "photo",     title: "Clean duplicates", benefit: "200 MB", benefitBytes: 200_000_000),
            QuickWin(id: "contacts", icon: "person.2",  title: "Merge contacts",   benefit: "5 items", benefitBytes: 0),
        ]
        vm.injectForTesting(healthScore: 35, healthResult: nil, quickWins: wins)
        #expect(vm.quickWins.count == 2)
        #expect(vm.quickWins.first?.id == "photos")
    }

    @Test("quickWins is empty when injected as empty")
    func quickWins_empty_whenInjectedEmpty() {
        let vm = DashboardViewModel()
        vm.injectForTesting(healthScore: 90, healthResult: nil, quickWins: [])
        #expect(vm.quickWins.isEmpty)
    }

    // MARK: - formatBytes

    @Test("formatBytes returns a non-empty string for 1 GB")
    func formatBytes_1GB_nonEmpty() {
        let vm = DashboardViewModel()
        #expect(!vm.formatBytes(1_073_741_824).isEmpty)
    }

    @Test("formatBytes returns a non-empty string for zero")
    func formatBytes_zero_nonEmpty() {
        let vm = DashboardViewModel()
        #expect(!vm.formatBytes(0).isEmpty)
    }

    // MARK: - Helpers

    private func makeHealthResult(storageScore: Int) -> HealthScoreResult {
        let domains = [
            DomainScore(domain: "storage",  score: storageScore, weight: 0.40, weightedScore: Double(storageScore) * 0.40),
            DomainScore(domain: "photos",   score: 70,           weight: 0.20, weightedScore: 14.0),
            DomainScore(domain: "contacts", score: 70,           weight: 0.10, weightedScore: 7.0),
            DomainScore(domain: "battery",  score: 70,           weight: 0.20, weightedScore: 14.0),
            DomainScore(domain: "privacy",  score: 70,           weight: 0.10, weightedScore: 7.0),
        ]
        let composite = Int(domains.reduce(0.0) { $0 + $1.weightedScore })
        return HealthScoreResult(compositeScore: composite, breakdown: domains)
    }
}
