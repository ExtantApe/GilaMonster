import AppKit
import GilaMonsterCore
import os
import SwiftUI
import UserNotifications

/// How a session's ask reaches the owner (D217, D220). Every ask opens a small GilaMonster window with Allow and Deny,
/// kept in front of other windows, and the menu bar leaf shows how many are waiting. A notification with the same two
/// buttons goes out too, when macOS lets GilaMonster show one. The window is there because notifications can be off,
/// hidden by a Focus, or shown as nothing at all: on 2026-11-16 two asks reached macOS and were "presented as none"
/// because the build had no alert permission, so they timed out unseen (K679). No answer in 2 minutes is still a no.
/// On 2026-11-17 three more timed out with the owner at the Mac: the Sleep Focus held every notification back, and
/// the window sat silent on the other screen. So each ask now also moves the window to the pointer's screen, plays a
/// sound GilaMonster makes itself, bounces the Dock icon, and plays the sound again with a minute left.
final class SessionPrompts: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SessionPrompts()
    static let category = "gilamonster.session.ask"
    static let categoryToday = "gilamonster.session.ask.today"
    static let allowToday = "allow-today"
    static let allow = "allow"
    static let deny = "deny"
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GilaMonster", category: "session-ask")

    /// Called once at launch, before any notification can be answered.
    @MainActor func install() {
        let service = SessionAccessService.shared
        service.onAsk = { approval in
            SessionAskWindow.shared.show()
            SessionAskWindow.shared.callAttention(critical: true)
            Announcer.say("\(approval.sentence). Open the request window from the GilaMonster menu to answer. No answer means no.", urgent: true, force: true)
            SessionPrompts.post(approval)
            if let at = SessionAskPlacement.reminder(asked: approval.asked, deadline: approval.deadline) {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow)))
                    guard service.waiting.contains(where: { $0.id == approval.id }) else { return }
                    SessionAskWindow.shared.show()
                    SessionAskWindow.shared.callAttention(critical: false)
                }
            }
        }
        service.onAutoAllowed = { text in
            SessionPrompts.log.notice("Allowed for today: \(text, privacy: .public)")
            SessionPrompts.notice(text)
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
        let today = UNNotificationAction(identifier: Self.allowToday, title: "Allow for Today", options: [.authenticationRequired])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [allow, deny], intentIdentifiers: []),
                                          UNNotificationCategory(identifier: Self.categoryToday, actions: [allow, today, deny], intentIdentifiers: [])])
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
        let reach = approval.action.todayFamily.map { " Allow for Today covers \($0.words) on every server until midnight." } ?? ""
        content.body = "Asked through gilamonster-session. The name is the session's own. No answer in \(Int(approval.deadline.timeIntervalSince(approval.asked) / 60)) minutes means no.\(reach)"
        content.sound = .default
        content.categoryIdentifier = approval.canAllowForToday ? categoryToday : category
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { log.error("Session ask \(id, privacy: .public): notification not added: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// A plain notice, no buttons: an action went ahead under Allow for today.
    @MainActor static func notice(_ text: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Allowed for today"
        content.body = text
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { log.error("Allowed-for-today notice not shown: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard [Self.category, Self.categoryToday].contains(content.categoryIdentifier), let id = UUID(uuidString: response.notification.request.identifier) else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Self.allow: SessionAccessService.shared.resolve(id, allow: true)
            case Self.allowToday: SessionAccessService.shared.resolveForToday(id)
            case Self.deny: SessionAccessService.shared.resolve(id, allow: false)
            default:
                // Clicking the notification itself answers nothing: it brings the ask window forward.
                SessionAskWindow.shared.show(activate: true)
            }
        }
    }
}

/// What macOS said about GilaMonster's notifications at the last ask, for Settings.
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

/// The ask window: a panel that stays in front without taking focus from whatever the owner is doing. It opens at the
/// top of whichever screen the pointer is on, every time, so it lands where the owner is looking.
@MainActor final class SessionAskWindow {
    static let shared = SessionAskWindow()
    private var panel: NSPanel?
    private var attention: Int?

    /// A panel that can take keyboard focus, which a non-activating utility panel won't do by itself.
    private final class AskPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    /// `activate` is for when the owner asked for it (the menu, a key, a notification click): the panel becomes the
    /// key window, GilaMonster comes forward, and focus lands on the first Deny. A new ask arriving on its own leaves
    /// whatever the owner is typing alone, and announces itself instead.
    func show(activate: Bool = false) {
        if panel == nil {
            let p = AskPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 180),
                             styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
            p.title = "A session is asking"
            p.level = .statusBar
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.setAccessibilityLabel("A session is asking")
            p.contentView = NSHostingView(rootView: SessionAskList(service: .shared, focusFirst: true).padding(18).frame(width: 520).tint(Theme.accent))
            panel = p
        }
        guard let panel else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let screens = NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
        if let content = SessionAskPlacement.frame(size: size, pointer: NSEvent.mouseLocation, screens: screens) {
            panel.setFrame(panel.frameRect(forContentRect: content), display: true)
        }
        if activate {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .askPanelFocus, object: nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAccessibility.post(element: panel as Any, notification: .windowCreated)
    }

    /// A sound GilaMonster plays itself, so a Focus that holds notifications back doesn't silence it, and a Dock bounce
    /// that lasts until GilaMonster is brought forward (critical) or bounces once (the reminder).
    func callAttention(critical: Bool) {
        (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
        if let attention { NSApp.cancelUserAttentionRequest(attention) }
        attention = NSApp.requestUserAttention(critical ? .criticalRequest : .informationalRequest)
    }

    func hide() {
        panel?.orderOut(nil)
        if let attention { NSApp.cancelUserAttentionRequest(attention); self.attention = nil }
    }
}

extension Notification.Name {
    /// Sent when the ask panel was opened by the owner, so the first Deny takes focus.
    static let askPanelFocus = Notification.Name("gilamonster.askPanelFocus")
}

/// Each waiting ask with Deny and Allow. Used by the ask window and by Settings.
struct SessionAskList: View {
    let service: SessionAccessService
    /// True in the ask window: the first Deny takes focus when the window opens, and Return means Deny.
    var focusFirst = false
    /// When the rows last changed. A pointer click in the moment after is ignored, so a row that lapses and lets the
    /// next one move up under the pointer can't take a click meant for it (K721 review). Key presses go straight
    /// through: they can't land on the wrong row that way.
    @State private var changed = Date.distantPast
    @FocusState private var focused: UUID?

    /// Whether this press counts. A click that comes from the pointer waits out the guard; the keyboard doesn't.
    private func settled() -> Bool {
        let type = NSApp.currentEvent?.type
        let pointer = type == .leftMouseDown || type == .leftMouseUp || type == .rightMouseDown || type == .rightMouseUp || type == .otherMouseDown || type == .otherMouseUp
        return SessionAskPlacement.accepts(pointer: pointer, sinceChange: Date().timeIntervalSince(changed))
    }

    private func focusTop() {
        guard focusFirst, let first = service.waiting.first else { return }
        focused = first.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if service.waiting.isEmpty {
                Text("Nothing is waiting.").foregroundStyle(Theme.muted)
            }
            ForEach(Array(service.waiting.enumerated()), id: \.element.id) { index, ask in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ask.sentence).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        if let family = ask.action.todayFamily {
                            Text("Allow for Today covers \(family.words) on every server until midnight.")
                                .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = max(0, Int(ask.deadline.timeIntervalSince(context.date).rounded(.up)))
                            Text("The name is the session's own. No answer in \(left / 60):\(String(format: "%02d", left % 60)) means no.")
                                .font(.caption).monospacedDigit().foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                // A second-by-second label would make VoiceOver chatter, so it says the minutes.
                                .accessibilityLabel("The name is the session's own. No answer in about \(max(1, (left + 30) / 60)) minutes means no.")
                        }
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack {
                            Button("Deny") { if settled() { service.resolve(ask.id, allow: false) } }.buttonStyle(.themed)
                                .keyboardShortcut(index == 0 && focusFirst ? .defaultAction : nil)
                                .focused($focused, equals: ask.id)
                                .accessibilityLabel("Deny: \(ask.sentence)")
                            Button("Allow") { if settled() { service.resolve(ask.id, allow: true) } }.buttonStyle(.themedPrimary)
                                .accessibilityLabel("Allow: \(ask.sentence)")
                            if let family = ask.action.todayFamily {
                                Divider().frame(height: 18).padding(.horizontal, 6)
                                Button("Allow for Today") { if settled() { service.resolveForToday(ask.id) } }.buttonStyle(.themed)
                                    .help("Allows \(family.words) on every server without asking again until midnight. Each one still checks nobody is online.")
                                    .accessibilityLabel("Allow for today: \(ask.sentence). Covers \(family.words) on every server until midnight.")
                            }
                        }
                        Button("Need More Time") { _ = service.extend(ask.id) }.buttonStyle(.link).font(.caption)
                            .disabled(ask.extensions >= SessionAccessService.maxExtensions)
                            .help("Waits another minute before the answer becomes no. Nothing is allowed by this.")
                            .accessibilityLabel("Need more time for: \(ask.sentence). Adds a minute. Nothing is allowed.")
                    }
                }
            }
        }
        .onChange(of: service.waiting.map(\.id)) { changed = Date(); focusTop() }
        .onAppear { focusTop() }
        .onReceive(NotificationCenter.default.publisher(for: .askPanelFocus)) { _ in focusTop() }
    }
}
