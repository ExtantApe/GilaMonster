import AppKit
import LeafJuiceCore
import UserNotifications

/// The Allow notification for session actions (D217, D220). Each request gets one notification with Allow and Deny.
/// It's shown even when LeafJuice is in front and even with LeafJuice's own alerts off, since nothing happens without
/// it. If notifications are blocked in System Settings, the same request waits in Settings > Session access.
final class SessionPrompts: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SessionPrompts()
    static let category = "leafjuice.session.ask"
    static let allow = "allow"
    static let deny = "deny"

    /// Called once at launch, before any notification can be answered.
    @MainActor func install() {
        let service = SessionAccessService.shared
        service.onAsk = { approval in SessionPrompts.post(approval) }
        service.onAnswered = { id in
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        }
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let allow = UNNotificationAction(identifier: Self.allow, title: "Allow", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: Self.deny, title: "Deny", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [allow, deny], intentIdentifiers: [])])
    }

    @MainActor static func post(_ approval: SessionApproval) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = approval.sentence
        content.body = "Asked through leafjuice-session. The name is the session's own. No answer in \(Int(approval.deadline.timeIntervalSince(approval.asked) / 60)) minutes means no."
        content.sound = .default
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: approval.id.uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == Self.category, let id = UUID(uuidString: response.notification.request.identifier) else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Self.allow: SessionAccessService.shared.resolve(id, allow: true)
            case Self.deny: SessionAccessService.shared.resolve(id, allow: false)
            default:
                // Clicking the notification itself answers nothing: it brings LeafJuice forward, where Settings shows it.
                NSApp.activate()
            }
        }
    }
}
