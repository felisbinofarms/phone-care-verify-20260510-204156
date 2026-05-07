import Testing
import Foundation
@testable import PhoneCare

@Suite("PhotosViewModel")
@MainActor
struct PhotosViewModelTests {

    // MARK: - Initial state

    @Test("isScanning starts false")
    func initialState_notScanning() {
        let vm = PhotosViewModel()
        #expect(vm.isScanning == false)
    }

    @Test("scanComplete starts false")
    func initialState_scanNotComplete() {
        let vm = PhotosViewModel()
        #expect(vm.scanComplete == false)
    }

    @Test("selectedCategory defaults to duplicates")
    func initialState_defaultCategory() {
        let vm = PhotosViewModel()
        #expect(vm.selectedCategory == .duplicates)
    }

    @Test("selectedPhotoIDs starts empty")
    func initialState_noSelection() {
        let vm = PhotosViewModel()
        #expect(vm.selectedPhotoIDs.isEmpty)
    }

    @Test("hasResults is false when all categories are empty")
    func hasResults_falseWhenEmpty() {
        let vm = PhotosViewModel()
        #expect(vm.hasResults == false)
    }

    // MARK: - Selection

    @Test("toggleSelection adds an ID that was not selected")
    func toggleSelection_adds() {
        let vm = PhotosViewModel()
        vm.toggleSelection("photo1")
        #expect(vm.selectedPhotoIDs.contains("photo1"))
    }

    @Test("toggleSelection removes an ID that was already selected")
    func toggleSelection_removes() {
        let vm = PhotosViewModel()
        vm.toggleSelection("photo1")
        vm.toggleSelection("photo1")
        #expect(!vm.selectedPhotoIDs.contains("photo1"))
    }

    @Test("selectAll adds all provided IDs to the selection")
    func selectAll_addsAllIDs() {
        let vm = PhotosViewModel()
        vm.selectAll(in: ["a", "b", "c"])
        #expect(vm.selectedPhotoIDs == ["a", "b", "c"])
    }

    @Test("deselectAll clears the selection")
    func deselectAll_clearsSelection() {
        let vm = PhotosViewModel()
        vm.selectAll(in: ["a", "b", "c"])
        vm.deselectAll()
        #expect(vm.selectedPhotoIDs.isEmpty)
    }

    @Test("selectedCount reflects the number of selected IDs")
    func selectedCount() {
        let vm = PhotosViewModel()
        vm.selectAll(in: ["a", "b", "c"])
        #expect(vm.selectedCount == 3)
    }

    // MARK: - Batch delete intent (Q1=b: scan visible, batch action gated)

    @Test("batchDeleteIntent returns empty when no photos are selected, regardless of premium")
    func batchDeleteIntent_emptySelection_returnsEmpty() {
        let vm = PhotosViewModel()
        #expect(vm.batchDeleteIntent(isPremium: false) == .empty)
        #expect(vm.batchDeleteIntent(isPremium: true) == .empty)
    }

    @Test("batchDeleteIntent returns proceed for free user with one photo selected")
    func batchDeleteIntent_singleSelection_freeUser_returnsProceed() {
        let vm = PhotosViewModel()
        vm.toggleSelection("photo1")
        #expect(vm.batchDeleteIntent(isPremium: false) == .proceed)
    }

    @Test("batchDeleteIntent returns proceed for premium user with one photo selected")
    func batchDeleteIntent_singleSelection_premiumUser_returnsProceed() {
        let vm = PhotosViewModel()
        vm.toggleSelection("photo1")
        #expect(vm.batchDeleteIntent(isPremium: true) == .proceed)
    }

    @Test("batchDeleteIntent returns showFrictionPrompt for free user with multi-select")
    func batchDeleteIntent_multiSelection_freeUser_returnsFrictionPrompt() {
        let vm = PhotosViewModel()
        vm.selectAll(in: ["a", "b", "c"])
        #expect(vm.batchDeleteIntent(isPremium: false) == .showFrictionPrompt)
    }

    @Test("batchDeleteIntent returns proceed for premium user with multi-select")
    func batchDeleteIntent_multiSelection_premiumUser_returnsProceed() {
        let vm = PhotosViewModel()
        vm.selectAll(in: ["a", "b", "c"])
        #expect(vm.batchDeleteIntent(isPremium: true) == .proceed)
    }

    @Test("All injected duplicate groups are exposed as-is, no premium-tier filtering")
    func duplicateGroups_allVisibleRegardlessOfPremium() {
        let vm = PhotosViewModel()
        let groups = (0..<5).map { index in
            DuplicateGroup(
                id: "g\(index)",
                assetIdentifiers: ["a\(index)", "b\(index)"],
                suggestedKeepIdentifier: "a\(index)",
                estimatedSavingsBytes: 1_000_000
            )
        }
        vm.injectTestData(
            duplicateGroups: groups,
            screenshotIDs: [],
            blurryIDs: [],
            largeVideoIDs: []
        )
        #expect(vm.duplicateGroups.count == 5)
    }

    // MARK: - Category description

    @Test("currentCategoryDescription returns no-duplicates message when empty")
    func categoryDescription_duplicates_empty() {
        let vm = PhotosViewModel()
        vm.selectedCategory = .duplicates
        #expect(vm.currentCategoryDescription == "No duplicates found")
    }

    @Test("currentCategoryDescription returns no-screenshots message when empty")
    func categoryDescription_screenshots_empty() {
        let vm = PhotosViewModel()
        vm.selectedCategory = .screenshots
        #expect(vm.currentCategoryDescription == "No screenshots found")
    }

    @Test("currentCategoryDescription returns no-blurry message when empty")
    func categoryDescription_blurry_empty() {
        let vm = PhotosViewModel()
        vm.selectedCategory = .blurry
        #expect(vm.currentCategoryDescription == "No blurry photos found")
    }

    @Test("currentCategoryDescription returns no-large-videos message when empty")
    func categoryDescription_largeVideos_empty() {
        let vm = PhotosViewModel()
        vm.selectedCategory = .largeVideos
        #expect(vm.currentCategoryDescription == "No large videos found")
    }

    // MARK: - Batch delete

    @Test("prepareBatchDelete does nothing when selection is empty")
    func prepareBatchDelete_noOp() {
        let vm = PhotosViewModel()
        vm.prepareBatchDelete()
        #expect(vm.showBatchDeleteSheet == false)
    }

    @Test("prepareBatchDelete shows sheet when IDs are selected")
    func prepareBatchDelete_showsSheet() {
        let vm = PhotosViewModel()
        vm.toggleSelection("photo1")
        vm.prepareBatchDelete()
        #expect(vm.showBatchDeleteSheet == true)
    }

    // MARK: - applyDeletion

    @Test("applyDeletion clears selection, records count and size, shows toast")
    func applyDeletion_clearsSelectionAndShowsToast() {
        let vm = PhotosViewModel()
        vm.selectAll(in: ["a", "b", "c"])
        vm.applyDeletion(deletedIDs: ["a", "b", "c"], count: 3, bytes: 9_000_000)
        #expect(vm.selectedPhotoIDs.isEmpty)
        #expect(vm.lastDeletedCount == 3)
        #expect(vm.lastDeletedSize == 9_000_000)
        #expect(vm.showUndoToast == true)
        #expect(vm.showBatchDeleteSheet == false)
    }

    @Test("applyDeletion removes deleted IDs from screenshotIDs and blurryIDs")
    func applyDeletion_removesFromFlatLists() {
        let vm = PhotosViewModel()
        vm.injectTestData(
            duplicateGroups: [],
            screenshotIDs: ["s1", "s2", "s3"],
            blurryIDs: ["b1", "b2"],
            largeVideoIDs: []
        )
        vm.applyDeletion(deletedIDs: ["s1", "b1"], count: 2, bytes: 0)
        #expect(!vm.screenshotIDs.contains("s1"))
        #expect(vm.screenshotIDs.contains("s2"))
        #expect(!vm.blurryIDs.contains("b1"))
        #expect(vm.blurryIDs.contains("b2"))
    }

    @Test("applyDeletion removes deleted IDs from duplicate groups, keeps groups with 2+ remaining")
    func applyDeletion_removesFromDuplicateGroups() {
        let vm = PhotosViewModel()
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a", "b", "c"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 5_000_000
        )
        vm.injectTestData(
            duplicateGroups: [group],
            screenshotIDs: [],
            blurryIDs: [],
            largeVideoIDs: []
        )
        // Delete one duplicate — group still has 2 remaining, should survive
        vm.applyDeletion(deletedIDs: ["b"], count: 1, bytes: 0)
        #expect(vm.duplicateGroups.count == 1)
        #expect(!vm.duplicateGroups[0].assetIdentifiers.contains("b"))
    }

    @Test("applyDeletion drops groups that fall below 2 assets after deletion")
    func applyDeletion_dropsGroupsBelow2() {
        let vm = PhotosViewModel()
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a", "b"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 3_000_000
        )
        vm.injectTestData(
            duplicateGroups: [group],
            screenshotIDs: [],
            blurryIDs: [],
            largeVideoIDs: []
        )
        // Delete one photo — group falls to 1 asset, should be removed
        vm.applyDeletion(deletedIDs: ["b"], count: 1, bytes: 0)
        #expect(vm.duplicateGroups.isEmpty)
    }

    @Test("applyDeletion reassigns suggestedKeepIdentifier when the kept asset is deleted")
    func applyDeletion_reassignsKeepWhenKeptAssetDeleted() {
        let vm = PhotosViewModel()
        let group = DuplicateGroup(
            id: "g1",
            assetIdentifiers: ["a", "b", "c"],
            suggestedKeepIdentifier: "a",
            estimatedSavingsBytes: 5_000_000
        )
        vm.injectTestData(
            duplicateGroups: [group],
            screenshotIDs: [],
            blurryIDs: [],
            largeVideoIDs: []
        )
        // Delete the suggested-keep asset
        vm.applyDeletion(deletedIDs: ["a"], count: 1, bytes: 0)
        #expect(vm.duplicateGroups.count == 1)
        #expect(vm.duplicateGroups[0].suggestedKeepIdentifier != "a")
    }

    // MARK: - dismissDeletedToast

    @Test("dismissDeletedToast clears the undo toast")
    func dismissDeletedToast_clearsToast() {
        let vm = PhotosViewModel()
        vm.applyDeletion(deletedIDs: ["x"], count: 1, bytes: 1_000_000)
        #expect(vm.showUndoToast == true)
        vm.dismissDeletedToast()
        #expect(vm.showUndoToast == false)
    }
}
