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
    static let shared = SessionAskWindow(service: .shared)
    private let service: SessionAccessService
    init(service: SessionAccessService) { self.service = service }
    #if DEBUG
    /// The snapshot's made-up screen, far off every real one. With it set the window is invisible, takes no clicks and
    /// isn't held to a real screen, so the snapshot can drive the real window without showing anything.
    var previewScreen: CGRect?
    /// Where the top of the content is in the window. Below zero means the top, with the name, is out of view.
    private(set) var previewContentTop: CGFloat = 0
    var previewPanel: NSPanel? { panel }
    #endif
    private var panel: NSPanel?
    private var attention: Int?

    /// A panel that can take keyboard focus, which a non-activating utility panel won't do by itself.
    private final class AskPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        #if DEBUG
        var unconstrained = false
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            unconstrained ? frameRect : super.constrainFrameRect(frameRect, to: screen)
        }
        #endif
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
            // The content keeps its own height and sits at the top of the window, so it says when that height changes,
            // and on a screen too short for all of it the name and the top of the prompt are what stays in view.
            let host = NSHostingController(rootView: AnyView(content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { [weak self] frame in self?.contentChanged(frame) }
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .background(Theme.surface)))
            host.sizingOptions = []   // sized below, when it opens and whenever its content changes size
            p.contentViewController = host
            panel = p
            #if DEBUG
            if previewScreen != nil { p.unconstrained = true; p.level = .normal; p.alphaValue = 0; p.ignoresMouseEvents = true }
            #endif
        }
        guard let panel else { return }
        // Never wider than the usable screen it opens on (K820 review). Narrower than it asks for, the words wrap and
        // the buttons go under them, so the height is asked for again at the width it will really have.
        let (pointer, screens) = place()
        let visible = (screens.first { $0.frame.contains(pointer) } ?? screens.first)?.visible.width ?? 1280
        AskPanelSize.shared.widest = visible
        let size = neededSize(visible: visible)
        if let content = SessionAskPlacement.frame(size: size, pointer: pointer, screens: screens) {
            let frame = panel.frameRect(forContentRect: content)
            // A window that appears or moves puts buttons where they weren't, so clicks wait out the guard.
            if !panel.isVisible || frame != panel.frame { AskPanelSize.shared.moved = Date() }
            panel.setFrame(frame, display: true)
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

    private var content: some View { AskPanelLook { SessionAskList(service: service, focusFirst: true) }.tint(Theme.accent) }

    /// What the content asks for on a screen this wide, from a fresh copy that no window has sized.
    private func neededSize(visible: CGFloat) -> CGSize {
        let fresh = NSHostingController(rootView: content)
        let width = SessionAskPlacement.contentWidth(ideal: fresh.view.fittingSize.width, visible: visible)
        return CGSize(width: width, height: fresh.sizeThatFits(in: CGSize(width: width, height: 10_000)).height)
    }

    #if DEBUG
    /// The height the content needs at this width.
    func previewNeededHeight(width: CGFloat) -> CGFloat { NSHostingController(rootView: content).sizeThatFits(in: CGSize(width: width, height: 10_000)).height }
    #endif

    /// The content changed size: buttons may have moved, so clicks wait out the guard, and the window is sized again.
    private func contentChanged(_ frame: CGRect) {
        #if DEBUG
        previewContentTop = frame.minY
        #endif
        AskPanelSize.shared.moved = Date()
        DispatchQueue.main.async { [weak self] in self?.resize() }   // after this layout pass, not during it
    }

    /// Sizes the open window to its content again. It only changes the frame: the window keeps its screen and top
    /// edge, and nothing here takes focus, makes it key or brings it forward.
    private func resize() {
        guard let panel, panel.isVisible else { return }
        let screens = place().screens
        guard let area = SessionAskPlacement.area(of: panel.frame, screens: screens) else { return }
        AskPanelSize.shared.widest = area.width
        let wanted = panel.frameRect(forContentRect: NSRect(origin: .zero, size: neededSize(visible: area.width))).size
        guard let frame = SessionAskPlacement.resized(panel.frame, to: wanted, screens: screens),
              abs(frame.height - panel.frame.height) > 0.5 || abs(frame.width - panel.frame.width) > 0.5 else { return }
        AskPanelSize.shared.moved = Date()
        panel.setFrame(frame, display: true)
    }

    /// Where the pointer is and what screens there are.
    private func place() -> (pointer: CGPoint, screens: [(frame: CGRect, visible: CGRect)]) {
        #if DEBUG
        if let previewScreen { return (CGPoint(x: previewScreen.midX, y: previewScreen.midY), [(previewScreen, previewScreen)]) }
        #endif
        return (NSEvent.mouseLocation, NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) })
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
    /// 580 pt at the default text size, more with larger text.
    static var minWidth: CGFloat { 580 * Theme.grow }
    /// The widest it may be. Nil means the screen the window last opened on.
    var widest: CGFloat?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            BeadBandView(height: 6)
            content.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 18)
        }
        // 580 pt at the 13 pt text size. In SessionAskList every button is `.fixedSize()`, so it is as wide as its
        // label and never clips it (K800), and the words on the left ask for a 262 pt column, which is what they had
        // at 580 pt. The window is sized from those, so larger text makes it wider instead of squeezing a button.
        // Never wider than the screen: the minimum gives way to it.
        .frame(minWidth: min(AskPanelLook.minWidth, widest ?? AskPanelSize.shared.widest), maxWidth: widest ?? AskPanelSize.shared.widest)
        .background(Theme.surface)
        .typeRoot()
    }
}

extension Notification.Name {
    /// Sent when the ask panel was opened by the owner, so the first Deny takes focus.
    static let askPanelFocus = Notification.Name("gilamonster.askPanelFocus")
}

/// The ask's sentence, with the server's name always shown whole (K820). This is a security prompt, so the name is
/// never cut short and never hidden in a tooltip. It gets lines of its own under the words before it, and a long one
/// wraps at its spaces, or anywhere only when a single word is wider than the window. Nothing is measured: the layout
/// decides, with the font as it is really drawn, Bold Text included. VoiceOver gets the plain sentence.
struct AskSentence: View {
    let sentence: String
    let server: String

    /// The column the words ask for beside the buttons, and the narrowest they are kept at before the buttons move
    /// under them.
    static var column: CGFloat { 262 * Theme.grow }
    static var narrowest: CGFloat { 200 * Theme.grow }

    var body: some View {
        if let parts = PixelType.split(sentence, around: server) {
            VStack(alignment: .leading, spacing: 2) {
                if !parts.before.isEmpty { Text(parts.before).type(.prompt).fixedSize(horizontal: false, vertical: true) }
                Text(server).type(.prompt).fixedSize(horizontal: false, vertical: true)
                if !parts.after.isEmpty { Text(parts.after).type(.prompt).fixedSize(horizontal: false, vertical: true) }
            }
            .foregroundStyle(Theme.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sentence)
        } else {
            Text(sentence).type(.prompt).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One ask's row: its words, then its buttons. Side by side when the buttons and a readable column of words both
/// fit; otherwise the buttons go under the words, so the window can be as narrow as the screen and Deny and Allow
/// are still fully in view (`SessionAskPlacement.sideBySide`). Side by side, the words' first line sits on the
/// buttons' text line, as before.
struct AskRow: Layout {
    var gap: CGFloat = 12

    private func parts(_ subviews: Subviews) -> (words: LayoutSubview, buttons: LayoutSubview)? {
        guard let words = subviews.first, let buttons = subviews.last, subviews.count >= 2 else { return nil }
        return (words, buttons)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let (words, buttons) = parts(subviews) else { return .zero }
        let b = buttons.sizeThatFits(.unspecified)
        guard let width = proposal.width, width.isFinite else {
            let w = words.sizeThatFits(.unspecified)
            return CGSize(width: w.width + gap + b.width, height: max(w.height, b.height))
        }
        if SessionAskPlacement.sideBySide(width: width, wordsAtLeast: AskSentence.narrowest, buttons: b.width, gap: gap) {
            let w = words.sizeThatFits(ProposedViewSize(width: width - gap - b.width, height: nil))
            return CGSize(width: width, height: max(w.height, b.height) + 6)
        }
        let w = words.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let under = buttons.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: w.height + gap + under.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let (words, buttons) = parts(subviews) else { return }
        for extra in subviews.dropFirst().dropLast() { extra.place(at: bounds.origin, proposal: .zero) }   // the spacer between them
        let b = buttons.sizeThatFits(.unspecified)
        if SessionAskPlacement.sideBySide(width: bounds.width, wordsAtLeast: AskSentence.narrowest, buttons: b.width, gap: gap) {
            let room = ProposedViewSize(width: bounds.width - gap - b.width, height: nil)
            // The words' first line on the buttons' text line.
            let drop = max(0, buttons.dimensions(in: .unspecified)[.firstTextBaseline] - words.dimensions(in: room)[.firstTextBaseline])
            words.place(at: CGPoint(x: bounds.minX, y: bounds.minY + min(drop, 6)), proposal: room)
            buttons.place(at: CGPoint(x: bounds.maxX - b.width, y: bounds.minY), proposal: ProposedViewSize(b))
        } else {
            let room = ProposedViewSize(width: bounds.width, height: nil)
            let w = words.sizeThatFits(room)
            words.place(at: bounds.origin, proposal: room)
            buttons.place(at: CGPoint(x: bounds.minX, y: bounds.minY + w.height + gap), proposal: room)
        }
    }
}

/// The widest the Allow window's content may be: the usable width of the screen it opens on. Set each time it opens.
@Observable final class AskPanelSize: @unchecked Sendable {
    static let shared = AskPanelSize()
    var widest: CGFloat = .greatestFiniteMagnitude
    /// When the window's layout last changed, for the click guard.
    @ObservationIgnored var moved = Date.distantPast
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
        let ok = SessionAskPlacement.accepts(pointer: pointer, sinceChange: Date().timeIntervalSince(max(changed, AskPanelSize.shared.moved)))
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
                AskRow {
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
                    }.frame(idealWidth: AskSentence.column, alignment: .leading)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        WrapRow(trailing: true) {
                            Button("Deny") { if settled() { service.resolve(ask.id, allow: false) } }.buttonStyle(.themed).fixedSize()
                                .keyboardShortcut(index == 0 && focusFirst ? .defaultAction : nil)
                                .focused($focused, equals: ask.id)
                                .accessibilityLabel("Deny: \(ask.sentence)").opacity(dropped ? 0.4 : 1)
                            Button("Allow") { if settled() { service.resolve(ask.id, allow: true) } }.buttonStyle(.themedPrimary).fixedSize()
                                .accessibilityLabel("Allow: \(ask.sentence)").opacity(dropped ? 0.4 : 1)
                            if let family = ask.action.todayFamily {
                                Button("Allow for Today") { if settled() { service.resolveForToday(ask.id) } }.buttonStyle(.themed).fixedSize()
                                    .padding(.leading, 20 * Theme.grow)   // kept apart from Allow
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
                                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.trailing)
                                .frame(idealWidth: 180 * Theme.grow, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .onChange(of: service.waiting.map(\.id)) { changed = Date(); focusTop() }
        // A row that runs out of extra time gains a line, which moves what is under it. Focus is left alone.
        .onChange(of: service.waiting.map { $0.extensions >= SessionAccessService.maxExtensions }) { AskPanelSize.shared.moved = Date() }
        .onAppear { focusTop() }
        .onReceive(NotificationCenter.default.publisher(for: .askPanelFocus)) { _ in focusTop() }
    }
}
