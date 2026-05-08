import Testing
import Foundation
@testable import PhoneCare

@Suite("OnboardingViewModel")
@MainActor
struct OnboardingViewModelTests {

    // MARK: - Initial State

    @Test("Initial state has no selected goals")
    func initialSelectedGoals() {
        let vm = OnboardingViewModel()
        #expect(vm.selectedGoals.isEmpty)
        #expect(vm.hasSelectedGoals == false)
    }

    @Test("Initial state has no phone feeling selected")
    func initialPhoneFeeling() {
        let vm = OnboardingViewModel()
        #expect(vm.phoneFeeling == nil)
    }

    @Test("Initial tech savvy level is intermediate")
    func initialTechSavvyLevel() {
        let vm = OnboardingViewModel()
        #expect(vm.techSavvyLevel == .intermediate)
    }

    @Test("Initial scan state is idle and not scanning")
    func initialScanState() {
        let vm = OnboardingViewModel()
        #expect(vm.scanStage == .idle)
        #expect(vm.scanProgress == 0.0)
        #expect(vm.isScanning == false)
    }

    @Test("Initial scan results have zero health score")
    func initialScanResults() {
        let vm = OnboardingViewModel()
        #expect(vm.scanResults.healthScore == 0)
        #expect(vm.scanResults.storageResult == nil)
        #expect(vm.scanResults.photoResult == nil)
        #expect(vm.scanResults.contactResult == nil)
        #expect(vm.scanResults.batteryInfo == nil)
        #expect(vm.scanResults.privacyResult == nil)
    }

    // MARK: - Goal Selection

    @Test("toggleGoal adds a goal when not selected")
    func toggleGoalAdd() {
        let vm = OnboardingViewModel()
        vm.toggleGoal(.freeUpSpace)
        #expect(vm.selectedGoals.contains(.freeUpSpace))
        #expect(vm.hasSelectedGoals == true)
    }

    @Test("toggleGoal removes a goal when already selected")
    func toggleGoalRemove() {
        let vm = OnboardingViewModel()
        vm.toggleGoal(.freeUpSpace)
        #expect(vm.selectedGoals.contains(.freeUpSpace))

        vm.toggleGoal(.freeUpSpace)
        #expect(!vm.selectedGoals.contains(.freeUpSpace))
        #expect(vm.hasSelectedGoals == false)
    }

    @Test("Multiple goals can be selected simultaneously")
    func multipleGoals() {
        let vm = OnboardingViewModel()
        vm.toggleGoal(.freeUpSpace)
        vm.toggleGoal(.cleanPhotos)
        vm.toggleGoal(.checkBattery)
        #expect(vm.selectedGoals.count == 3)
        #expect(vm.hasSelectedGoals == true)
    }

    @Test("Toggling all goals on then off leaves empty set")
    func toggleAllOnThenOff() {
        let vm = OnboardingViewModel()
        for goal in OnboardingGoal.allCases {
            vm.toggleGoal(goal)
        }
        #expect(vm.selectedGoals.count == OnboardingGoal.allCases.count)

        for goal in OnboardingGoal.allCases {
            vm.toggleGoal(goal)
        }
        #expect(vm.selectedGoals.isEmpty)
    }

    // MARK: - Card Order Computation

    @Test("Card order with no goals returns default order")
    func cardOrderNoGoals() {
        let vm = OnboardingViewModel()
        let order = vm.computeCardOrder()
        #expect(order == ["healthScore", "storage", "photos", "contacts", "battery", "privacy"])
    }

    @Test("Card order with selected goals puts them first after healthScore")
    func cardOrderWithGoals() {
        let vm = OnboardingViewModel()
        vm.toggleGoal(.checkBattery)
        vm.toggleGoal(.reviewPrivacy)

        let order = vm.computeCardOrder()

        // healthScore is always first
        #expect(order.first == "healthScore")

        // Selected goals should come before non-selected cards
        let batteryIndex = order.firstIndex(of: "battery")!
        let privacyIndex = order.firstIndex(of: "privacy")!
        let storageIndex = order.firstIndex(of: "storage")!
        let photosIndex = order.firstIndex(of: "photos")!
        let contactsIndex = order.firstIndex(of: "contacts")!

        #expect(batteryIndex < storageIndex)
        #expect(privacyIndex < storageIndex)
        #expect(batteryIndex < photosIndex)
        #expect(privacyIndex < contactsIndex)
    }

    @Test("Card order always contains all six cards")
    func cardOrderContainsAll() {
        let vm = OnboardingViewModel()
        vm.toggleGoal(.freeUpSpace)
        vm.toggleGoal(.cleanPhotos)

        let order = vm.computeCardOrder()
        #expect(order.count == 6)
        #expect(order.contains("healthScore"))
        #expect(order.contains("storage"))
        #expect(order.contains("photos"))
        #expect(order.contains("contacts"))
        #expect(order.contains("battery"))
        #expect(order.contains("privacy"))
    }

    @Test("Card order with all goals selected")
    func cardOrderAllGoals() {
        let vm = OnboardingViewModel()
        for goal in OnboardingGoal.allCases {
            vm.toggleGoal(goal)
        }
        let order = vm.computeCardOrder()
        #expect(order.count == 6)
        #expect(order.first == "healthScore")
        // No duplicates
        #expect(Set(order).count == 6)
    }

    @Test("Card order has no duplicates")
    func cardOrderNoDuplicates() {
        let vm = OnboardingViewModel()
        vm.toggleGoal(.freeUpSpace)
        let order = vm.computeCardOrder()
        #expect(order.count == Set(order).count)
    }

    // MARK: - Personal Plan

    @Test("Personal plan with no scan results shows 'phone looks good' fallback")
    func personalPlanNoResults() {
        let vm = OnboardingViewModel()
        let plan = vm.personalPlan
        #expect(plan.count == 1)
        #expect(plan.first?.title == "Your phone looks good!")
    }

    @Test("Personal plan items are sorted by priority ascending")
    func personalPlanSorted() {
        let vm = OnboardingViewModel()
        // Even with no results the plan is sorted
        let plan = vm.personalPlan
        for i in 0..<plan.count - 1 {
            #expect(plan[i].priority <= plan[i + 1].priority)
        }
    }

    @Test("Personal plan items have unique IDs")
    func personalPlanUniqueIDs() {
        let vm = OnboardingViewModel()
        let plan = vm.personalPlan
        let ids = plan.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    // MARK: - OnboardingGoal Model

    @Test("All OnboardingGoal cases have non-empty titles")
    func goalTitles() {
        for goal in OnboardingGoal.allCases {
            #expect(!goal.title.isEmpty)
        }
    }

    @Test("All OnboardingGoal cases have non-empty icons")
    func goalIcons() {
        for goal in OnboardingGoal.allCases {
            #expect(!goal.icon.isEmpty)
        }
    }

    @Test("All OnboardingGoal cases have non-empty cardIDs")
    func goalCardIDs() {
        for goal in OnboardingGoal.allCases {
            #expect(!goal.cardID.isEmpty)
        }
    }

    @Test("Goal cardID mappings are correct")
    func goalCardIDMappings() {
        #expect(OnboardingGoal.freeUpSpace.cardID == "storage")
        #expect(OnboardingGoal.cleanPhotos.cardID == "photos")
        #expect(OnboardingGoal.organizeContacts.cardID == "contacts")
        #expect(OnboardingGoal.checkBattery.cardID == "battery")
        #expect(OnboardingGoal.reviewPrivacy.cardID == "privacy")
    }

    @Test("OnboardingGoal has 5 cases")
    func goalCaseCount() {
        #expect(OnboardingGoal.allCases.count == 5)
    }

    // MARK: - PhoneFeeling Model

    @Test("All PhoneFeeling cases have non-empty titles")
    func phoneFeelingTitles() {
        for feeling in PhoneFeeling.allCases {
            #expect(!feeling.title.isEmpty)
        }
    }

    @Test("PhoneFeeling has 4 cases")
    func phoneFeelingCaseCount() {
        #expect(PhoneFeeling.allCases.count == 4)
    }

    // MARK: - TechSavvyLevel Model

    @Test("TechSavvyLevel raw values are 0, 1, 2")
    func techSavvyRawValues() {
        #expect(TechSavvyLevel.beginner.rawValue == 0)
        #expect(TechSavvyLevel.intermediate.rawValue == 1)
        #expect(TechSavvyLevel.advanced.rawValue == 2)
    }

    @Test("All TechSavvyLevel cases have non-empty titles and descriptions")
    func techSavvyProperties() {
        for level in TechSavvyLevel.allCases {
            #expect(!level.title.isEmpty)
            #expect(!level.description.isEmpty)
            #expect(!level.icon.isEmpty)
        }
    }

    // MARK: - ScanStage Model

    @Test("All ScanStage values have non-empty messages")
    func scanStageMessages() {
        let stages: [ScanStage] = [.idle, .storage, .photos, .contacts, .battery, .privacy, .complete]
        for stage in stages {
            #expect(!stage.message.isEmpty)
        }
    }

    @Test("ScanStage complete message")
    func scanStageComplete() {
        #expect(ScanStage.complete.message == "All done!")
    }

    @Test("ScanStage idle message")
    func scanStageIdle() {
        #expect(ScanStage.idle.message == "Getting ready...")
    }

    // MARK: - savePreferences error / edge paths (#118)
    //
    // `runScan` cannot be exercised in unit tests because it requires concrete
    // analyzers tied to Photos/Contacts permissions; cancellation and timeout
    // surfaces therefore cannot be driven directly. The two tests below cover
    // the reachable defensive paths for `savePreferences`: a save call that
    // happens before any scan ran, and a repeated save that must remain
    // idempotent.

    @Test("savePreferences without scan results marks onboarding done and persists prefs")
    func savePreferences_withoutScanResults_completesAndMarksOnboardingDone() async throws {
        // AppState reads `hasCompletedOnboarding` from UserDefaults in init;
        // clear before the test so this run is deterministic, and clear after
        // so it does not leak to other tests sharing the suite UserDefaults.
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding") }

        let vm = OnboardingViewModel()
        vm.toggleGoal(.cleanPhotos)
        vm.phoneFeeling = .great
        vm.techSavvyLevel = .advanced

        let dataManager = DataManager(inMemory: true)
        let appState = AppState()

        await vm.savePreferences(to: dataManager, appState: appState)

        #expect(appState.hasCompletedOnboarding == true)
        let prefs = try dataManager.userPreferences()
        #expect(prefs.onboardingCompleted == true)
        #expect(prefs.goals.contains("cleanPhotos"))
        #expect(prefs.phoneFeeling == "great")
        #expect(prefs.techSavvyLevel == TechSavvyLevel.advanced.rawValue)

        // No scan ran, so no ScanResult should have been written.
        let scans = try dataManager.fetch(ScanResult.self)
        #expect(scans.isEmpty)
    }

    @Test("savePreferences called twice does not create duplicate UserPreferences")
    func savePreferences_calledTwice_remainsIdempotent() async throws {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        defer { UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding") }

        let dataManager = DataManager(inMemory: true)
        let appState = AppState()

        let vm1 = OnboardingViewModel()
        vm1.toggleGoal(.freeUpSpace)
        await vm1.savePreferences(to: dataManager, appState: appState)

        let vm2 = OnboardingViewModel()
        vm2.toggleGoal(.checkBattery)
        await vm2.savePreferences(to: dataManager, appState: appState)

        // userPreferences() is the single-row contract; a second save must
        // overwrite, not duplicate. fetch must return at most one row.
        let allPrefs = try dataManager.fetch(UserPreferences.self)
        #expect(allPrefs.count == 1)
        // The second call wins.
        #expect(allPrefs.first?.goals.contains("checkBattery") == true)
    }
}
