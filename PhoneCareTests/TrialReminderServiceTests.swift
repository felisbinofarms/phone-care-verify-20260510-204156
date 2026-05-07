import Testing
import Foundation
import UserNotifications
@testable import PhoneCare

private final class MockNotificationScheduler: UserNotificationScheduling, @unchecked Sendable {
    var status: UNAuthorizationStatus = .authorized
    var requestAuthorizationResult: Bool = true
    var requestAuthorizationShouldThrow: Error?
    var addShouldThrow: Error?

    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []
    private(set) var requestAuthorizationCallCount = 0

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCallCount += 1
        if let error = requestAuthorizationShouldThrow { throw error }
        return requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let error = addShouldThrow { throw error }
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}

@Suite("TrialReminderService")
@MainActor
struct TrialReminderServiceTests {

    // MARK: - sync

    @Test("sync schedules a reminder when in trial with future expiration")
    func sync_inTrial_schedules() async {
        let mock = MockNotificationScheduler()
        let service = TrialReminderService(scheduler: mock)
        let expiration = Date().addingTimeInterval(7 * 24 * 3600) // 7 days

        await service.sync(isInTrial: true, productID: "weekly", expirationDate: expiration)

        #expect(mock.addedRequests.count == 1)
        #expect(mock.addedRequests.first?.identifier == "phonecare.trial-reminder.weekly")
    }

    @Test("sync cancels a reminder when not in trial")
    func sync_notInTrial_cancels() async {
        let mock = MockNotificationScheduler()
        let service = TrialReminderService(scheduler: mock)

        await service.sync(isInTrial: false, productID: "weekly", expirationDate: nil)

        #expect(mock.removedIdentifiers.contains("phonecare.trial-reminder.weekly"))
        #expect(mock.addedRequests.isEmpty)
    }

    @Test("sync is a no-op when productID is nil")
    func sync_nilProductID_noOp() async {
        let mock = MockNotificationScheduler()
        let service = TrialReminderService(scheduler: mock)

        await service.sync(
            isInTrial: true,
            productID: nil,
            expirationDate: Date().addingTimeInterval(7 * 86400)
        )

        #expect(mock.addedRequests.isEmpty)
        #expect(mock.removedIdentifiers.isEmpty)
    }

    // MARK: - scheduleReminder

    @Test("scheduleReminder skips when expiration is less than 48h away")
    func schedule_tooClose_skips() async {
        let mock = MockNotificationScheduler()
        let service = TrialReminderService(scheduler: mock)
        let expiration = Date().addingTimeInterval(12 * 3600) // 12 hours

        await service.scheduleReminder(productID: "monthly", expirationDate: expiration)

        #expect(mock.addedRequests.isEmpty)
    }

    @Test("scheduleReminder skips when permission is denied")
    func schedule_permissionDenied_skips() async {
        let mock = MockNotificationScheduler()
        mock.status = .denied
        let service = TrialReminderService(scheduler: mock)
        let expiration = Date().addingTimeInterval(7 * 86400)

        await service.scheduleReminder(productID: "annual", expirationDate: expiration)

        #expect(mock.addedRequests.isEmpty)
        #expect(mock.requestAuthorizationCallCount == 0)
    }

    @Test("scheduleReminder requests permission when status is notDetermined")
    func schedule_notDetermined_requests() async {
        let mock = MockNotificationScheduler()
        mock.status = .notDetermined
        mock.requestAuthorizationResult = true
        let service = TrialReminderService(scheduler: mock)
        let expiration = Date().addingTimeInterval(7 * 86400)

        await service.scheduleReminder(productID: "annual", expirationDate: expiration)

        #expect(mock.requestAuthorizationCallCount == 1)
        #expect(mock.addedRequests.count == 1)
    }

    @Test("scheduleReminder is idempotent and replaces existing reminder for same productID")
    func schedule_replacesExisting() async {
        let mock = MockNotificationScheduler()
        let service = TrialReminderService(scheduler: mock)
        let expiration = Date().addingTimeInterval(7 * 86400)

        await service.scheduleReminder(productID: "weekly", expirationDate: expiration)
        await service.scheduleReminder(productID: "weekly", expirationDate: expiration)

        #expect(mock.addedRequests.count == 2)
        // Both schedule calls remove the prior request first.
        #expect(mock.removedIdentifiers.filter { $0 == "phonecare.trial-reminder.weekly" }.count >= 1)
    }

    // MARK: - cancelReminder

    @Test("cancelReminder removes the request for the given productID")
    func cancel_removesRequest() {
        let mock = MockNotificationScheduler()
        let service = TrialReminderService(scheduler: mock)

        service.cancelReminder(productID: "monthly")

        #expect(mock.removedIdentifiers == ["phonecare.trial-reminder.monthly"])
    }
}
