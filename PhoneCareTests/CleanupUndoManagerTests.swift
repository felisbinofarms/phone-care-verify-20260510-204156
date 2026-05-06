import Testing
import Foundation
@testable import PhoneCare

private actor CallTracker {
    var wasCalled = false
    func markCalled() { wasCalled = true }
}

private actor AttemptCounter {
    var value = 0
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

@Suite("CleanupUndoManager")
@MainActor
struct CleanupUndoManagerTests {

    // MARK: - Register

    @Test("Registering an action adds it to activeUndoActions")
    func registerAction() {
        let manager = CleanupUndoManager()
        let id = UUID()

        manager.registerAction(
            id: id,
            actionType: .photoDelete,
            itemCount: 5,
            duration: 60
        ) {
            // no-op
        }

        #expect(manager.activeUndoActions.count == 1)
        #expect(manager.activeUndoActions.first?.id == id)
        #expect(manager.activeUndoActions.first?.actionType == .photoDelete)
        #expect(manager.activeUndoActions.first?.itemCount == 5)
    }

    @Test("Registering multiple actions stores all of them")
    func registerMultipleActions() {
        let manager = CleanupUndoManager()

        manager.registerAction(id: UUID(), actionType: .photoDelete, itemCount: 1, duration: 60) {}
        manager.registerAction(id: UUID(), actionType: .contactMerge, itemCount: 2, duration: 60) {}
        manager.registerAction(id: UUID(), actionType: .videoCompress, itemCount: 3, duration: 60) {}

        #expect(manager.activeUndoActions.count == 3)
    }

    // MARK: - Undo Within Window

    @Test("Undo within window succeeds and removes the action")
    func undoWithinWindow() async throws {
        let manager = CleanupUndoManager()
        let id = UUID()
        let tracker = CallTracker()

        manager.registerAction(
            id: id,
            actionType: .photoDelete,
            itemCount: 3,
            duration: 60
        ) {
            await tracker.markCalled()
        }

        let result = try await manager.undo(id: id)
        #expect(result == true)
        let wasCalled = await tracker.wasCalled
        #expect(wasCalled == true)
        #expect(manager.activeUndoActions.isEmpty)
    }

    // MARK: - Undo After Window

    @Test("Undo after window expires returns false")
    func undoAfterWindow() async throws {
        let manager = CleanupUndoManager()
        let id = UUID()

        // Register with a duration that is effectively already expired.
        // We use a very short duration and then wait.
        manager.registerAction(
            id: id,
            actionType: .photoDelete,
            itemCount: 1,
            duration: 0.001
        ) {
            // Should not be called
        }

        // Give the tiny duration time to expire
        try await Task.sleep(for: .milliseconds(50))

        let result = try await manager.undo(id: id)
        #expect(result == false)
    }

    @Test("Undo for non-existent ID returns false")
    func undoNonExistentID() async throws {
        let manager = CleanupUndoManager()
        let result = try await manager.undo(id: UUID())
        #expect(result == false)
    }

    // MARK: - Cancel

    @Test("cancelUndo removes the action without executing handler")
    func cancelUndo() async {
        let manager = CleanupUndoManager()
        let id = UUID()
        let tracker = CallTracker()

        manager.registerAction(
            id: id,
            actionType: .contactMerge,
            itemCount: 2,
            duration: 60
        ) {
            await tracker.markCalled()
        }

        manager.cancelUndo(id: id)
        #expect(manager.activeUndoActions.isEmpty)
        let wasCalled = await tracker.wasCalled
        #expect(wasCalled == false)
    }

    @Test("cancelUndo for non-existent ID does not crash")
    func cancelNonExistent() {
        let manager = CleanupUndoManager()
        manager.cancelUndo(id: UUID())
        #expect(manager.activeUndoActions.isEmpty)
    }

    // MARK: - Clear All

    @Test("clearAll removes all actions")
    func clearAll() {
        let manager = CleanupUndoManager()

        manager.registerAction(id: UUID(), actionType: .photoDelete, itemCount: 1, duration: 60) {}
        manager.registerAction(id: UUID(), actionType: .contactMerge, itemCount: 2, duration: 60) {}
        manager.registerAction(id: UUID(), actionType: .videoCompress, itemCount: 3, duration: 60) {}

        #expect(manager.activeUndoActions.count == 3)

        manager.clearAll()
        #expect(manager.activeUndoActions.isEmpty)
    }

    @Test("clearAll on empty manager does nothing")
    func clearAllEmpty() {
        let manager = CleanupUndoManager()
        manager.clearAll()
        #expect(manager.activeUndoActions.isEmpty)
    }

    // MARK: - isUndoAvailable

    @Test("isUndoAvailable returns true for active non-expired action")
    func isUndoAvailableTrue() {
        let manager = CleanupUndoManager()
        let id = UUID()

        manager.registerAction(
            id: id,
            actionType: .photoDelete,
            itemCount: 1,
            duration: 60
        ) {}

        #expect(manager.isUndoAvailable(id: id) == true)
    }

    @Test("isUndoAvailable returns false for unknown ID")
    func isUndoAvailableFalseUnknown() {
        let manager = CleanupUndoManager()
        #expect(manager.isUndoAvailable(id: UUID()) == false)
    }

    @Test("isUndoAvailable returns false after cancel")
    func isUndoAvailableFalseAfterCancel() {
        let manager = CleanupUndoManager()
        let id = UUID()

        manager.registerAction(id: id, actionType: .photoDelete, itemCount: 1, duration: 60) {}
        manager.cancelUndo(id: id)

        #expect(manager.isUndoAvailable(id: id) == false)
    }

    @Test("isUndoAvailable returns false after undo is executed")
    func isUndoAvailableFalseAfterUndo() async throws {
        let manager = CleanupUndoManager()
        let id = UUID()

        manager.registerAction(id: id, actionType: .photoDelete, itemCount: 1, duration: 60) {}

        _ = try await manager.undo(id: id)
        #expect(manager.isUndoAvailable(id: id) == false)
    }

    // MARK: - UndoAction Model

    @Test("UndoAction isExpired is true when deadline is past")
    func undoActionExpired() {
        let action = UndoAction(
            id: UUID(),
            actionType: .photoDelete,
            itemCount: 1,
            deadline: Date().addingTimeInterval(-10),
            registeredAt: Date().addingTimeInterval(-20)
        )
        #expect(action.isExpired == true)
    }

    @Test("UndoAction isExpired is false when deadline is in the future")
    func undoActionNotExpired() {
        let action = UndoAction(
            id: UUID(),
            actionType: .photoDelete,
            itemCount: 1,
            deadline: Date().addingTimeInterval(60),
            registeredAt: Date()
        )
        #expect(action.isExpired == false)
    }

    @Test("UndoAction remainingSeconds is non-negative")
    func undoActionRemainingSeconds() {
        let action = UndoAction(
            id: UUID(),
            actionType: .contactMerge,
            itemCount: 5,
            deadline: Date().addingTimeInterval(-100),
            registeredAt: Date().addingTimeInterval(-200)
        )
        #expect(action.remainingSeconds >= 0)
    }

    @Test("UndoAction remainingSeconds is positive for future deadline")
    func undoActionRemainingSecondsFuture() {
        let action = UndoAction(
            id: UUID(),
            actionType: .contactMerge,
            itemCount: 5,
            deadline: Date().addingTimeInterval(30),
            registeredAt: Date()
        )
        #expect(action.remainingSeconds > 0)
        #expect(action.remainingSeconds <= 30)
    }

    // MARK: - Default Durations

    @Test("Default durations are configured correctly")
    func defaultDurations() {
        #expect(CleanupUndoManager.photoDeletionUndoDuration == 30)
        #expect(CleanupUndoManager.contactMergeUndoDuration == 30 * 24 * 3600)
        #expect(CleanupUndoManager.videoCompressUndoDuration == 30)
    }

    // MARK: - undoAction(for:)

    @Test("undoAction(for:) returns the action for a known ID")
    func undoActionForKnownID() {
        let manager = CleanupUndoManager()
        let id = UUID()

        manager.registerAction(id: id, actionType: .videoCompress, itemCount: 7, duration: 60) {}

        let retrieved = manager.undoAction(for: id)
        #expect(retrieved != nil)
        #expect(retrieved?.id == id)
        #expect(retrieved?.actionType == .videoCompress)
        #expect(retrieved?.itemCount == 7)
    }

    @Test("undoAction(for:) returns nil for unknown ID")
    func undoActionForUnknownID() {
        let manager = CleanupUndoManager()
        #expect(manager.undoAction(for: UUID()) == nil)
    }

    // MARK: - Error paths (#118)

    @Test("undo rethrows when handler throws and leaves action available")
    func undoHandlerThrows_rethrowsAndLeavesActionInList() async {
        let manager = CleanupUndoManager()
        let id = UUID()
        enum HandlerError: Error { case boom }

        manager.registerAction(
            id: id, actionType: .photoDelete, itemCount: 1, duration: 60
        ) {
            throw HandlerError.boom
        }

        do {
            _ = try await manager.undo(id: id)
            Issue.record("Expected undo to rethrow handler error")
        } catch {
            // Expected — handler threw, manager rethrew.
        }

        // The action should still be available so the user can retry.
        #expect(manager.isUndoAvailable(id: id))
        #expect(manager.activeUndoActions.contains(where: { $0.id == id }))
    }

    @Test("undo can be retried after a previous handler threw")
    func undoHandlerThrows_canBeRetried() async throws {
        let manager = CleanupUndoManager()
        let id = UUID()
        let counter = AttemptCounter()
        enum HandlerError: Error { case transient }

        manager.registerAction(
            id: id, actionType: .photoDelete, itemCount: 1, duration: 60
        ) {
            let n = await counter.increment()
            if n == 1 { throw HandlerError.transient }
        }

        // First attempt: throws.
        do {
            _ = try await manager.undo(id: id)
            Issue.record("Expected first undo to throw")
        } catch {}

        // Second attempt: succeeds, action is cleaned up.
        let success = try await manager.undo(id: id)
        #expect(success == true)
        #expect(manager.isUndoAvailable(id: id) == false)
        #expect(await counter.value == 2)
    }
}
