import Testing
import Foundation
@testable import PhoneCare

@Suite("PaywallViewModel re-show triggers", .serialized)
@MainActor
struct PaywallViewModelTests {

    init() {
        PaywallViewModel.resetTriggerStateForTesting()
    }

    // MARK: - userInitiated

    @Test("userInitiated trigger always shows, never gated by session or persisted cooldown")
    func userInitiated_alwaysShows() {
        #expect(PaywallViewModel.shouldShow(for: .userInitiated))
        PaywallViewModel.recordShown(for: .userInitiated)
        #expect(PaywallViewModel.shouldShow(for: .userInitiated))
    }

    // MARK: - Session-scope (batchDelete, gatedCTA)

    @Test("batchDelete: shows once per session, blocked after recordShown")
    func batchDelete_sessionScope() {
        #expect(PaywallViewModel.shouldShow(for: .batchDelete))
        PaywallViewModel.recordShown(for: .batchDelete)
        #expect(PaywallViewModel.shouldShow(for: .batchDelete) == false)
    }

    @Test("gatedCTA: shows once per session, blocked after recordShown")
    func gatedCTA_sessionScope() {
        #expect(PaywallViewModel.shouldShow(for: .gatedCTA))
        PaywallViewModel.recordShown(for: .gatedCTA)
        #expect(PaywallViewModel.shouldShow(for: .gatedCTA) == false)
    }

    // MARK: - scanMilestone (session + persisted cooldown)

    @Test("scanMilestone: blocked in same session after recordShown")
    func scanMilestone_sessionBlocks() {
        #expect(PaywallViewModel.shouldShow(for: .scanMilestone))
        PaywallViewModel.recordShown(for: .scanMilestone)
        #expect(PaywallViewModel.shouldShow(for: .scanMilestone) == false)
    }

    @Test("scanMilestone: blocked across launches when within 7-day cooldown")
    func scanMilestone_persistedCooldown_blocked() {
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 3600)
        UserDefaults.standard.set(twoDaysAgo, forKey: "PaywallLastShown_scanMilestone")
        // Session set is fresh from init; persisted timestamp is recent → blocked.
        #expect(PaywallViewModel.shouldShow(for: .scanMilestone) == false)
    }

    @Test("scanMilestone: shows again after 7-day cooldown elapses across launches")
    func scanMilestone_persistedCooldown_elapsed() {
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        UserDefaults.standard.set(eightDaysAgo, forKey: "PaywallLastShown_scanMilestone")
        // Session set is fresh; persisted timestamp is older than cooldown → shows.
        #expect(PaywallViewModel.shouldShow(for: .scanMilestone))
    }

    // MARK: - Independence

    @Test("Triggers are independent, recording one does not block others")
    func triggers_independent() {
        PaywallViewModel.recordShown(for: .batchDelete)
        #expect(PaywallViewModel.shouldShow(for: .batchDelete) == false)
        #expect(PaywallViewModel.shouldShow(for: .gatedCTA))
        #expect(PaywallViewModel.shouldShow(for: .scanMilestone))
    }

    // MARK: - Persistence

    @Test("recordShown for scanMilestone persists timestamp to UserDefaults")
    func scanMilestone_persistence() {
        PaywallViewModel.recordShown(for: .scanMilestone)
        let stored = UserDefaults.standard.object(forKey: "PaywallLastShown_scanMilestone") as? Date
        #expect(stored != nil)
    }

    @Test("recordShown for session-only triggers does not write to UserDefaults")
    func sessionOnly_noPersistence() {
        PaywallViewModel.recordShown(for: .batchDelete)
        let stored = UserDefaults.standard.object(forKey: "PaywallLastShown_batchDelete")
        #expect(stored == nil)
    }
}
