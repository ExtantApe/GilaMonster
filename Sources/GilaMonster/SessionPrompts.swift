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
            Announcer.say("\(approval.sentence). Press Option-Command-R, or choose Requests Waiting for You in the Window menu or the GilaMonster menu bar item, to answer. No answer means no.", urgent: true, force: true)
            SessionPrompts.post(approval)
            SessionAskWindow.shared.scheduleReminder(for: approval.id, from: approval.asked)
        }
        service.onOutcome = { ask, answer in
            let word: String = switch answer {
            case .allowed: "Allowed"
            case .denied: "Denied"
            case .noAnswer: "No answer, so it was not allowed"
            }
            Announcer.say("\(word): \(ask.sentence)", urgent: answer != .allowed, force: true)
        }
        service.onAutoAllowed = { text in
            SessionPrompts.log.notice("Allowed for today: \(text, privacy: .public)")
            SessionPrompts.notice(text)
        }
        service.onAnswered = { id in
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
            SessionAskWindow.shared.cancelReminder(id)
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
        /// Escape denies the first waiting ask, which is the one Deny has focus on. It never allows anything.
        override func cancelOperation(_ sender: Any?) {
            if let first = SessionAccessService.shared.waiting.first { SessionAccessService.shared.resolve(first.id, allow: false) }
            else { orderOut(nil) }
        }
    }

    private var reminders: [UUID: Task<Void, Never>] = [:]

    /// The reminder sound and Dock bounce, a minute before the ask's current deadline. Called when the ask arrives and
    /// again whenever it's given more time, so the reminder follows the new deadline.
    func scheduleReminder(for id: UUID, from asked: Date) {
        reminders[id]?.cancel()
        reminders[id] = nil
        let service = SessionAccessService.shared
        guard let ask = service.waiting.first(where: { $0.id == id }),
              let at = SessionAskPlacement.reminder(asked: asked, deadline: ask.deadline) else { return }
        reminders[id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow)))
            guard !Task.isCancelled, service.waiting.contains(where: { $0.id == id }) else { return }
            show()
            callAttention(critical: false)
        }
    }

    func cancelReminder(_ id: UUID) { reminders[id]?.cancel(); reminders[id] = nil }

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
            p.contentView = NSHostingView(rootView: AskPanelLook { SessionAskList(service: .shared, focusFirst: true) }.tint(Theme.accent))
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

/// How the ask window looks (K786): a thin bead band across the top and the sand surface below it. Looks only: the list
/// inside, its wording, buttons, focus and guard are SessionAskList's, unchanged.
struct AskPanelLook<Content: View>: View {
    static var minWidth: CGFloat { 580 * Theme.grow }
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            BeadBandView(height: 6)
            content.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 18)
        }
        // 580 pt at the 13 pt text size. In SessionAskList every button is `.fixedSize()`, so it is as wide as its
        // label and never clips it (K800), and the words on the left ask for a 262 pt column, which is what they had
        // at 580 pt. The window is sized from those, so larger text makes it wider instead of squeezing a button.
        .frame(minWidth: AskPanelLook.minWidth)
        .background(Theme.surface)
        .typeRoot()
    }
}

extension Notification.Name {
    /// Sent when the ask panel was opened by the owner, so the first Deny takes focus.
    static let askPanelFocus = Notification.Name("gilamonster.askPanelFocus")
}

/// The ask's sentence, with the server's name always whole (K820). This is a security prompt, so the name is never
/// broken across lines. A name that fits on a line is kept together by no-break spaces and hyphens, and the sentence
/// wraps before it. A longer name gets a line to itself and the window grows to show it. Only a name wider than the
/// widest window is cut in the middle, with the whole name in its tooltip. VoiceOver always gets the plain sentence.
struct AskSentence: View {
    let sentence: String
    let server: String

    /// The words' column at the default text size, and the widest it grows for a long name.
    static var normalColumn: CGFloat { 262 * Theme.grow }
    static var widestColumn: CGFloat { 560 * Theme.grow }

    /// How wide the name is on one line in the prompt's font.
    static func width(of name: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: TypeToken.prompt.size, weight: .semibold)
        return ceil(NSAttributedString(string: name, attributes: [.font: font]).size().width) + 2
    }

    /// The column the words ask for: wider than usual only when the name needs it.
    static func column(for name: String) -> CGFloat { min(widestColumn, max(normalColumn, width(of: name))) }

    var body: some View {
        if Self.width(of: server) > Self.normalColumn, let parts = PixelType.split(sentence, around: server) {
            VStack(alignment: .leading, spacing: 2) {
                if !parts.before.isEmpty { Text(parts.before).type(.prompt).fixedSize(horizontal: false, vertical: true) }
                Text(server).type(.prompt).lineLimit(1).truncationMode(.middle).help(server)
                if !parts.after.isEmpty { Text(parts.after).type(.prompt).fixedSize(horizontal: false, vertical: true) }
            }
            .foregroundStyle(Theme.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sentence)
        } else {
            Text(PixelType.unbroken(sentence, name: server))
                .type(.prompt).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true).accessibilityLabel(sentence)
        }
    }
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
    /// True for a moment after a pointer click was dropped by the guard, so the buttons look unavailable and VoiceOver
    /// is told why.
    @State private var dropped = false

    /// Whether this press counts. A click that comes from the pointer waits out the guard; the keyboard doesn't.
    private func settled() -> Bool {
        let type = NSApp.currentEvent?.type
        let pointer = type == .leftMouseDown || type == .leftMouseUp || type == .rightMouseDown || type == .rightMouseUp || type == .otherMouseDown || type == .otherMouseUp
        let ok = SessionAskPlacement.accepts(pointer: pointer, sinceChange: Date().timeIntervalSince(changed))
        if !ok {
            dropped = true
            Announcer.say("The list just changed, so that click was ignored. Press again.", urgent: true, force: true)
            Task { @MainActor in try? await Task.sleep(for: .seconds(SessionAskPlacement.clickGuard)); dropped = false }
        }
        return ok
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
                        AskSentence(sentence: ask.sentence, server: ask.server)
                        if let family = ask.action.todayFamily {
                            Text("Allow for Today covers \(family.words) on every server until midnight.")
                                .type(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = max(0, Int(ask.deadline.timeIntervalSince(context.date).rounded(.up)))
                            Text("The name is the session's own. No answer in \(left / 60):\(String(format: "%02d", left % 60)) means no.")
                                .type(.body).monospacedDigit().foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                // A second-by-second label would make VoiceOver chatter, so it says the minutes.
                                .accessibilityLabel("The name is the session's own. No answer in about \(max(1, (left + 30) / 60)) minutes means no.")
                        }
                    }.frame(idealWidth: AskSentence.column(for: ask.server), alignment: .leading)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack {
                            Button("Deny") { if settled() { service.resolve(ask.id, allow: false) } }.buttonStyle(.themed).fixedSize()
                                .keyboardShortcut(index == 0 && focusFirst ? .defaultAction : nil)
                                .focused($focused, equals: ask.id)
                                .accessibilityLabel("Deny: \(ask.sentence)").opacity(dropped ? 0.4 : 1)
                            Button("Allow") { if settled() { service.resolve(ask.id, allow: true) } }.buttonStyle(.themedPrimary).fixedSize()
                                .accessibilityLabel("Allow: \(ask.sentence)").opacity(dropped ? 0.4 : 1)
                            if let family = ask.action.todayFamily {
                                Divider().frame(height: 18 * Theme.grow).padding(.horizontal, 6)
                                Button("Allow for Today") { if settled() { service.resolveForToday(ask.id) } }.buttonStyle(.themed).fixedSize()
                                    .helped("Allows \(family.words) on every server without asking again until midnight. Each one still checks nobody is online.")
                                    .accessibilityLabel("Allow for today: \(ask.sentence). Covers \(family.words) on every server until midnight.")
                            }
                        }
                        let left = SessionAccessService.maxExtensions - ask.extensions
                        Button("Need More Time (\(left) left)") {
                            if service.extend(ask.id) {
                                SessionAskWindow.shared.scheduleReminder(for: ask.id, from: Date())
                                Announcer.say("One minute added, \(left - 1) left", force: true)
                            }
                        }
                        .buttonStyle(.disclosureLink("plus")).type(.body).fixedSize()
                        .disabled(left <= 0)
                        .help("Waits another minute before the answer becomes no. Nothing is allowed by this.")
                        .accessibilityLabel("Need more time for: \(ask.sentence). Adds a minute, \(left) left. Nothing is allowed.")
                        if left <= 0 {
                            Text("No more time can be added. No answer means no.").type(.body).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .onChange(of: service.waiting.map(\.id)) { changed = Date(); focusTop() }
        .onAppear { focusTop() }
        .onReceive(NotificationCenter.default.publisher(for: .askPanelFocus)) { _ in focusTop() }
    }
}
