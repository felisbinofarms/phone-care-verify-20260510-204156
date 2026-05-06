import SwiftUI

struct PrivacyPermissionInfo: Identifiable {
    let id: String
    let type: PermissionType
    let status: PermissionStatus
    let statusColor: Color
    let statusText: String
    let icon: String
}

@MainActor
@Observable
final class PrivacyViewModel {

    // MARK: - State

    private(set) var privacyScore: Int = 0
    private(set) var permissions: [PrivacyPermissionInfo] = []
    private(set) var isLoading: Bool = false
    var selectedPermission: PermissionType?

    // MARK: - Load

    func load(permissionManager: PermissionManager) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await permissionManager.checkAllStatuses()

        var infos: [PrivacyPermissionInfo] = []
        for type in PermissionType.allCases {
            let status = permissionManager.status(for: type)
            infos.append(PrivacyPermissionInfo(
                id: type.rawValue,
                type: type,
                status: status,
                statusColor: colorForStatus(status),
                statusText: textForStatus(status, type: type),
                icon: iconForPermission(type)
            ))
        }

        permissions = infos
        privacyScore = computeScore(permissions: infos)
    }

    // MARK: - Score

    private func computeScore(permissions: [PrivacyPermissionInfo]) -> Int {
        // Exclude unscorable permissions (e.g. localNetwork) — iOS has no API to query them.
        let scorable = permissions.filter { !PermissionType.unscorable.contains($0.type) }
        guard !scorable.isEmpty else { return 100 }
        // "Reviewed" = user made an intentional choice (any status except notDetermined).
        // Matches PermissionSummary.isAppropriate in PrivacyAuditor — the canonical scoring policy.
        let reviewed = scorable.filter { $0.status != .notDetermined }.count
        let ratio = Double(reviewed) / Double(scorable.count) * 100
        return max(0, min(100, Int(ratio.rounded())))
    }

    // MARK: - Helpers

    private func colorForStatus(_ status: PermissionStatus) -> Color {
        switch status {
        case .authorized:     return .pcAccent
        case .denied:         return .pcTextSecondary
        case .notDetermined:  return .pcTextSecondary
        case .restricted:     return .pcTextSecondary
        case .limited:        return .pcAccent
        }
    }

    private func textForStatus(_ status: PermissionStatus, type: PermissionType) -> String {
        if PermissionType.unscorable.contains(type) {
            return "Review in Settings"
        }
        switch status {
        case .authorized:     return "Allowed"
        case .denied:         return "Denied"
        case .notDetermined:  return "Not Set"
        case .restricted:     return "Restricted"
        case .limited:        return "Limited"
        }
    }

    func iconForPermission(_ type: PermissionType) -> String {
        switch type {
        case .camera:       return "camera.fill"
        case .microphone:   return "mic.fill"
        case .location:     return "location.fill"
        case .contacts:     return "person.crop.circle.fill"
        case .photos:       return "photo.fill"
        case .calendar:     return "calendar"
        case .reminders:    return "checklist"
        case .bluetooth:    return "wave.3.right"
        case .localNetwork: return "network"
        case .health:       return "heart.fill"
        case .tracking:     return "hand.raised.fill"
        }
    }

    var scoreSummary: String {
        if privacyScore >= 76 {
            return "Your privacy settings look great. Most permissions have been reviewed."
        } else if privacyScore >= 51 {
            return "Your privacy is in good shape. A few permissions haven't been reviewed yet."
        } else {
            return "Several permissions haven't been reviewed yet. Tap any to learn more."
        }
    }

    var authorizedCount: Int {
        permissions.filter { $0.status == .authorized }.count
    }

    var deniedCount: Int {
        permissions.filter { $0.status == .denied }.count
    }

    var notSetCount: Int {
        permissions.filter { $0.status == .notDetermined }.count
    }
}
