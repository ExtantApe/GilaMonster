import AppKit
import LeafJuiceCore
import os
import SwiftUI
import UserNotifications

/// How a session's ask reaches the owner (D217, D220). Every ask opens a small LeafJuice window with Allow and Deny,
/// kept in front of other windows, and the menu bar leaf shows how many are waiting. A notification with the same two
/// buttons goes out too, when macOS lets LeafJuice show one. The window is there because notifications can be off,
/// hidden by a Focus, or shown as nothing at all: on 2026-11-16 two asks reached macOS and were "presented as none"
/// because the build had no alert permission, so they timed out unseen (K679). No answer in 2 minutes is still a no.
final class SessionPrompts: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SessionPrompts()
    static let category = "leafjuice.session.ask"
    static let allow = "allow"
    static let deny = "deny"
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LeafJuice", category: "session-ask")

    /// Called once at launch, before any notification can be answered.
    @MainActor func install() {
        let service = SessionAccessService.shared
        service.onAsk = { approval in
            SessionAskWindow.shared.show()
            SessionPrompts.post(approval)
        }
        service.onAnswered = { id in
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
            if service.waiting.isEmpty { SessionAskWindow.shared.hide() }
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
        let center = UNUserNotificationCenter.current()
        let id = approval.id.uuidString
        // Each ask records whether macOS would show it, so a missed ask can be explained afterwards.
        center.getNotificationSettings { settings in
            let line = SessionAskStatus.describe(authorization: settings.authorizationStatus.rawValue, alertStyle: settings.alertStyle.rawValue)
            log.notice("Session ask \(id, privacy: .public): notifications \(line, privacy: .public)")
            Task { @MainActor in SessionAskStatus.shared.last = line }
        }
        let content = UNMutableNotificationContent()
        content.title = approval.sentence
        content.body = "Asked through leafjuice-session. The name is the session's own. No answer in \(Int(approval.deadline.timeIntervalSince(approval.asked) / 60)) minutes means no."
        content.sound = .default
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { log.error("Session ask \(id, privacy: .public): notification not added: \(error.localizedDescription, privacy: .public)") }
        }
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
                // Clicking the notification itself answers nothing: it brings the ask window forward.
                SessionAskWindow.shared.show()
                NSApp.activate()
            }
        }
    }
}

/// What macOS said about LeafJuice's notifications at the last ask, for Settings.
@MainActor @Observable final class SessionAskStatus {
    static let shared = SessionAskStatus()
    var last: String?

    /// UNAuthorizationStatus and UNAlertStyle raw values, in words.
    nonisolated static func describe(authorization: Int, alertStyle: Int) -> String {
        let allowed: String = switch authorization {
        case 0: "not asked yet"
        case 1: "turned off"
        case 2: "allowed"
        case 3: "allowed quietly"
        default: "unknown"
        }
        let style: String = switch alertStyle {
        case 0: "no banners or alerts"
        case 1: "banners"
        case 2: "alerts"
        default: "unknown style"
        }
        return "\(allowed), \(style)"
    }
}

/// The ask window: a small panel that stays in front without taking focus from whatever the owner is doing.
@MainActor final class SessionAskWindow {
    static let shared = SessionAskWindow()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "A session is asking"
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: SessionAskList(service: .shared).padding(16).frame(width: 480).tint(Juice.pulp))
            p.center()
            panel = p
        }
        panel?.orderFrontRegardless()
        NSAccessibility.post(element: panel as Any, notification: .windowCreated)
    }

    func hide() { panel?.orderOut(nil) }
}

/// Each waiting ask with Deny and Allow. Used by the ask window and by Settings.
struct SessionAskList: View {
    let service: SessionAccessService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if service.waiting.isEmpty {
                Text("Nothing is waiting.").foregroundStyle(Juice.muted)
            }
            ForEach(service.waiting) { ask in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ask.sentence).foregroundStyle(Juice.ink).fixedSize(horizontal: false, vertical: true)
                        Text("The name is the session's own. No answer by \(ask.deadline.formatted(date: .omitted, time: .shortened)) means no.")
                            .font(.caption).foregroundStyle(Juice.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button("Deny") { service.resolve(ask.id, allow: false) }.buttonStyle(.juice)
                        .accessibilityLabel("Deny: \(ask.sentence)")
                    Button("Allow") { service.resolve(ask.id, allow: true) }.buttonStyle(.juicePrimary)
                        .accessibilityLabel("Allow: \(ask.sentence)")
                }
            }
        }
    }
}
