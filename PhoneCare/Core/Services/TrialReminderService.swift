import Foundation
import OSLog
import UserNotifications

// MARK: - Test seam

protocol UserNotificationScheduling: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

struct DefaultUserNotificationScheduler: UserNotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

// MARK: - Service

@MainActor
@Observable
final class TrialReminderService {
    private let scheduler: UserNotificationScheduling
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PhoneCare",
        category: "TrialReminder"
    )

    /// Identifier prefix for our scheduled reminders. Suffix is the productID.
    private static let identifierPrefix = "phonecare.trial-reminder."

    /// How far before trial expiration the reminder fires. 48 hours per Q8.
    private static let leadTime: TimeInterval = 48 * 60 * 60

    init(scheduler: UserNotificationScheduling = DefaultUserNotificationScheduler()) {
        self.scheduler = scheduler
    }

    /// Sync the reminder against current subscription state. Called from the
    /// app's entitlement-changed observation. If currently in a trial with a
    /// known expiration, schedule (or reschedule). Otherwise cancel.
    func sync(isInTrial: Bool, productID: String?, expirationDate: Date?) async {
        guard let productID else { return }
        if isInTrial, let expiration = expirationDate {
            await scheduleReminder(productID: productID, expirationDate: expiration)
        } else {
            cancelReminder(productID: productID)
        }
    }

    /// Schedule a pre-charge reminder ~48h before `expirationDate`.
    /// Idempotent: replaces any existing reminder for the same productID.
    /// Requests notification permission if not already granted.
    func scheduleReminder(productID: String, expirationDate: Date) async {
        let id = identifier(for: productID)

        let fireDate = expirationDate.addingTimeInterval(-Self.leadTime)
        guard fireDate > Date() else {
            logger.info("Trial expiration too close; skipping reminder.")
            scheduler.removePendingNotificationRequests(withIdentifiers: [id])
            return
        }

        guard await ensurePermission() else {
            logger.info("Notification permission not granted; skipping trial reminder.")
            return
        }

        // Cancel any prior request for this product (idempotent reschedule).
        scheduler.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Your free trial ends soon"
        content.body = "PhoneCare Premium will start in 2 days. Cancel anytime in Settings if you want to stay on the free version."

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSinceNow,
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await scheduler.add(request)
            logger.info("Scheduled trial reminder.")
        } catch {
            logger.error("Failed to schedule trial reminder: \(error.localizedDescription)")
        }
    }

    /// Cancel any scheduled reminder for the given productID.
    func cancelReminder(productID: String) {
        scheduler.removePendingNotificationRequests(withIdentifiers: [identifier(for: productID)])
        logger.info("Cancelled trial reminder.")
    }

    // MARK: - Helpers

    private func identifier(for productID: String) -> String {
        Self.identifierPrefix + productID
    }

    private func ensurePermission() async -> Bool {
        let status = await scheduler.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await scheduler.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                logger.error("Notification permission request failed: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }
}
