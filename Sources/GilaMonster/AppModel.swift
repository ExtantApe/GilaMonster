import AppKit
import OSLog
import GilaMonsterCore
import Observation
import SwiftUI
import UserNotifications

enum PageID: String, CaseIterable, Identifiable, Hashable {
    case overview, console, history, players, allowlist, worlds, plugins, software, lab, configs, resourcePacks, links, advisor, launch, backups, changes, cleanup
    var id: String { rawValue }
    /// The module a page belongs to. Nil for the essentials, which are always there.
    var module: AppModule? {
        switch self {
        case .worlds: .worlds
        case .players, .allowlist: .players
        case .history: .history
        case .cleanup: .cleanup
        case .resourcePacks: .resourcePacks
        case .links: .links
        case .advisor: .advisor
        case .lab: .lab
        default: nil
        }
    }
    @MainActor static var visible: [PageID] { allCases.filter { ($0.module.map(Modules.shared.isOn) ?? true) && !($0 == .lab && AdvisorTrial.isOn) } }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .console: "Console"
        case .history: "History"
        case .players: "Players"
        case .allowlist: "Allowlist"
        case .worlds: "Worlds"
        case .cleanup: "Cleanup"
        case .plugins: "Plugins"
        case .resourcePacks: "Resource Packs"
        case .links: "Plugin Links"
        case .advisor: "Advisor"
        case .software: "Software"
        case .lab: "Lab"
        case .configs: "Configs"
        case .launch: "Launch"
        case .backups: "Backups"
        case .changes: "Changes"
        }
    }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .console: "terminal"
        case .history: "chart.xyaxis.line"
        case .players: "person.2"
        case .allowlist: "person.badge.plus"
        case .worlds: "globe.americas"
        case .cleanup: "sparkles"
        case .plugins: "puzzlepiece.extension"
        case .resourcePacks: "photo.stack"
        case .links: "link"
        case .advisor: "sparkle.magnifyingglass"
        case .software: "shippingbox"
        case .lab: "flask"
        case .configs: "slider.horizontal.3"
        case .launch: "bolt"
        case .backups: "externaldrive"
        case .changes: "clock.arrow.2.circlepath"
        }
    }
}

struct LabSetupRequest: Identifiable {
    let id = UUID()
    let then: @MainActor () -> Void
}

/// The list of servers and app-wide state.
@MainActor @Observable
final class AppModel {
    private(set) var servers: [ServerController] = []
    let lab: LabController
    /// Asks for the EULA before something that needs the Lab, then carries on with it.
    var labSetup: LabSetupRequest?
    var selectedID: UUID? { didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedServer") } }
    var page: PageID = .overview
    /// Opened from the toolbar while nothing is open, to look at ignored issues. Not saved: the panel goes back to
    /// showing itself only when there's something open (UX audit finding 2).
    var issuesOpenedByHand = false
    var showIssues = UserDefaults.standard.object(forKey: "showIssues") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showIssues, forKey: "showIssues") }
    }
    var showAddServer = false
    /// The file open on the Configs page, so other pages can jump to one.
    var configPath: String?
    var showFolderSetup = AppPaths.needsServersFolderChoice
    var appUpdate: (version: String, url: URL)?
    var checkAppUpdates = UserDefaults.standard.object(forKey: "checkAppUpdates") as? Bool ?? true {
        didSet { UserDefaults.standard.set(checkAppUpdates, forKey: "checkAppUpdates") }
    }

    var selected: ServerController? { listed.first { $0.id == selectedID } ?? listed.first }
    /// The Lab stays on disk when its module is off, but isn't shown.
    var listed: [ServerController] { Modules.shared.isOn(.lab) && !AdvisorTrial.isOn ? servers : servers.filter { !$0.isLab } }
    /// The page to show, in case the one asked for belongs to a module that's off.
    var visiblePage: PageID { page.module.map(Modules.shared.isOn) ?? true ? page : .overview }
    var anyLive: Bool { servers.contains { $0.state.isLive || $0.trialIsLive } }
    /// Servers an earlier GilaMonster started and left running when it went away (K692). Their pid file is GilaMonster's
    /// own and the process runs in the server's folder, so stopping them with a SIGTERM (which saves) is safe.
    var leftOver: [ServerController] { servers.filter { if case .external = $0.state { true } else { false } } }

    init() {
        let paths: [String] = JSONStore.load(AppPaths.registry, defaults: [])
        var opened = paths.compactMap { ServerController.open(root: URL(fileURLWithPath: $0, isDirectory: true)) }
        let lab = LabController(existing: opened.first(where: \.isLab))
        self.lab = lab
        if let found = lab.server, !opened.contains(where: { $0.id == found.id }) { opened.append(found) }
        servers = opened
        selectedID = UserDefaults.standard.string(forKey: "selectedServer").flatMap(UUID.init) ?? servers.first?.id
        // Only servers with "Start when GilaMonster opens" on, which is off by default (owner, 2026-11-16).
        for server in LaunchStart.servers(servers, advisorTrial: AdvisorTrial.isOn,
                                          snapshot: ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT"] != nil) {
            Task { await server.start() }
        }
        // Its own switch, off until someone turns it on. A snapshot only draws screens.
        if ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT"] == nil {
            servers.forEach { $0.tidySignInLog() }
            for server in servers where server.linksPageSettings.on && !server.isLab {
                do { try server.startLinksPage() } catch { server.linksPageError = error.localizedDescription }
            }
            // A server can be running when the app opens, and its players still need the pack's address to answer.
            servers.forEach { $0.startPackHostIfWanted() }
        }
        servers.forEach(Alerts.connect)
        // Session access: off until the owner turns it on in Settings, and never in a snapshot or the Advisor trial.
        SessionAccessService.shared.servers = { [weak self] in self?.servers ?? [] }
        SessionPrompts.shared.install()
        if ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT"] == nil, !AdvisorTrial.isOn {
            // After the window is up, so a Keychain prompt can't hold up the launch.
            Task { await SessionAccessService.shared.apply(SessionAccess.loadSettings()) }
        }
        if !AdvisorTrial.isOn { Alerts.ask() }
        if checkAppUpdates, !AdvisorTrial.isOn { Task { await lookForAppUpdate() } }
        // A run's lab is listed while it exists, and dropped when it's deleted.
        lab.onServerChanged = { [weak self] old, new in
            guard let self else { return }
            let wasSelected = self.selectedID == old?.id
            self.servers.removeAll { $0.id == old?.id || $0.id == new?.id }
            if let new { self.servers.append(new) }
            if wasSelected || self.selectedID == nil { self.selectedID = new?.id }
            self.saveRegistry()
        }
        // A lab left by a quit or crash in the middle of a run goes now, if it's GilaMonster's own and not running (D229).
        if ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT"] == nil, !AdvisorTrial.isOn {
            Task { await lab.removeLeftover() }
        }
    }

    /// Runs something that needs the Lab, asking for the EULA first if it hasn't been accepted.
    func withLab(_ work: @escaping @MainActor () -> Void) {
        if lab.eulaAccepted { work() } else { labSetup = LabSetupRequest(then: work) }
    }

    /// The Lab page of the server it's modeled on. The lab itself is built only for a run.
    func openLabBoard() {
        guard let real = lab.model(from: servers) else { return }
        selectedID = real.id
        page = .lab
    }

    private func saveRegistry() {
        try? JSONStore.save(servers.map(\.paths.root.path), to: AppPaths.registry)
    }

    func add(_ controller: ServerController) {
        Alerts.connect(controller)
        if !servers.contains(where: { $0.id == controller.id }) { servers.append(controller) }
        selectedID = controller.id
        page = .overview
        saveRegistry()
    }

    /// Forgets a server. Its folder stays exactly where it is.
    func remove(_ controller: ServerController) {
        guard !controller.isLab else { return }
        AdvisorCenter.shared.share(controller, false)
        controller.stopTicker()
        servers.removeAll { $0.id == controller.id }
        if selectedID == controller.id { selectedID = servers.first?.id }
        saveRegistry()
    }

    func pathsChanged() { saveRegistry() }

    func stopAll() async {
        for server in servers {
            server.stopTrialCopy()
            if server.isLab, lab.isBusy { server.forceStop() }
            if server.state.isLive { server.stop() }
        }
        // Left-over servers stop alongside, each asked to save and shut down (K692).
        await withTaskGroup(of: Void.self) { group in
            for server in leftOver { group.addTask { await server.stopExternalServer() } }
        }
        for _ in 0..<(180 * 4) where anyLive { try? await Task.sleep(for: .milliseconds(250)) }
    }

    /// Unsigned apps can't update themselves safely, so this only tells you where the new build is.
    func lookForAppUpdate() async {
        struct Release: Decodable { let tag_name: String; let html_url: String }
        guard let url = URL(string: "https://api.github.com/repos/\(GilaMonster.repository)/releases/latest"),
              let release = try? await HTTP.decode(Release.self, url),
              let latest = LooseVersion(release.tag_name), let current = LooseVersion(GilaMonster.version),
              latest > current, let page = URL(string: release.html_url) else { return }
        appUpdate = (release.tag_name, page)
    }
}

/// Tells you when something goes wrong and GilaMonster isn't in front of you.
@MainActor enum Alerts {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "macAlerts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "macAlerts") }
    }

    static func connect(_ server: ServerController) {
        server.onAlert = { title, detail in show(title, detail) }
    }

    static func ask() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func show(_ title: String, _ detail: String) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = detail
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The last stop on every way out: nothing half-written is left behind (D213).
    func applicationWillTerminate(_ notification: Notification) { Backups.cancelInFlight(wait: 2) }

    /// Every build, release included: the quit handler reads why macOS is quitting the app (K650).
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    /// Kept alive for the app's life: the handlers for being told to quit by a signal.
    private static var signalSources: [DispatchSourceSignal] = []
    private static var signalled = false

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        // Killed with SIGTERM, SIGHUP or SIGINT (killall, a script, a terminal), the app used to vanish and leave its
        // servers running with nobody to stop them (K692). Now it stops them with a save first, as at a shutdown.
        for sig in [SIGTERM, SIGHUP, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { AppDelegate.quitOnSignal(sig) } }
            source.resume()
            Self.signalSources.append(source)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            AppDelegate.poweringOff = true
        }
        #if DEBUG
        snapshotIfAsked()
        #endif
    }

    #if DEBUG
    /// Debug builds only: draws every page of every listed server to images, off screen, then quits.
    /// `GILAMONSTER_SNAPSHOT=<folder>`, for checking screens nobody has clicked yet. Starts nothing.
    @MainActor private func snapshotIfAsked() {
        guard let folder = ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT"], let model = Self.model else { return }
        // GILAMONSTER_SNAPSHOT_THEME=bold|quiet picks the theme for this run, without saving it.
        if let name = ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_THEME"], let flavor = Palette.Flavor(rawValue: name) { Theme.flavor = flavor }
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.close() }
        Task { @MainActor in
            model.showFolderSetup = false
            try? FileOps.ensureDir(URL(fileURLWithPath: folder))
            var windows: [NSWindow] = []   // Kept until the end: closing them while SwiftUI settles isn't safe.
            // The no-overflow report: a page whose fitting width is wider than the window it's drawn in has something that
            // can't shrink (a long name on one line, say). Read by gilamonster-check --snapshot.
            let windowWidth: CGFloat = 1280
            var pagesChecked = 0
            var overflowing: [String] = []
            // GILAMONSTER_SNAPSHOT_FIRST draws only the first server's pages (the others still show in the sidebar).
            let drawn = ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_FIRST"] != nil ? Array(model.servers.prefix(1)) : model.servers
            for server in drawn where ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_DIALOGS_ONLY"] == nil {
                for page in PageID.allCases {
                    model.selectedID = server.id
                    model.page = page
                    // GILAMONSTER_SNAPSHOT_FORCE_WIDE=1 makes every page too wide on purpose, to prove the report catches it.
                    let wide = ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_FORCE_WIDE"] != nil
                    let host = NSHostingView(rootView: AnyView(RootView(model: model).tint(Theme.accent).frame(minWidth: wide ? 1700 : 0)))
                    if ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_LIGHT"] != nil { host.appearance = NSAppearance(named: .aqua) }
                    if ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_DARK"] != nil { host.appearance = NSAppearance(named: .darkAqua) }
                    let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 1280, height: ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_HEIGHT"].flatMap(Double.init).map { CGFloat($0) } ?? 1000), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    window.orderBack(nil)
                    try? await Task.sleep(for: .seconds(page == .overview ? 5 : page == .resourcePacks ? 12 : 2.5))
                    host.layoutSubtreeIfNeeded()
                    pagesChecked += 1
                    let fitting = host.fittingSize.width
                    if fitting > windowWidth + 0.5 { overflowing.append("OVERFLOW \(page.rawValue): fitting width \(Int(fitting.rounded())) is over the window's \(Int(windowWidth))") }
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        let name = "\(server.profile.name.replacingOccurrences(of: " ", with: "-"))-\(page.rawValue).png"
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
                    }
                    window.orderOut(nil)
                    windows.append(window)
                }
            }
            let report = (["checked \(pagesChecked) of \(drawn.count * PageID.allCases.count) pages"] + overflowing).joined(separator: "\n") + "\n"
            try? report.write(to: URL(fileURLWithPath: folder).appendingPathComponent("overflow-report.txt"), atomically: true, encoding: .utf8)
            // The dialogs too, which otherwise only appear after a click.
            // The quit question needs no server (D215).
            let quitDialogs: [(String, AnyView)] = [
                    ("quit-during-backup", AnyView(QuitDuringBackupView(state: QuitDuringBackupState(reason: .restart, progress: [
                        BackupProgress(server: "Made-up Server", written: 12_300_000_000, expected: 47_000_000_000, started: Date().addingTimeInterval(-600))]), choose: { _ in }))),
                    ("quit-during-backup-waiting", AnyView(QuitDuringBackupView(state: { let s = QuitDuringBackupState(reason: .user, progress: [
                        BackupProgress(server: "Made-up Server", written: 40_000_000_000, expected: 47_000_000_000, started: Date().addingTimeInterval(-1800))]); s.waiting = true; return s }(), choose: { _ in })))
            ]
            var serverDialogs: [(String, AnyView)] = []
            if let server = model.servers.first(where: { !$0.isLab }) {
                let build = PackVersion(file: "new.zip", version: "2.0", sha1: "abc", added: Date(), size: 1000, format: 75, description: "", fileCount: 3, imageCount: 1)
                let pack = LibraryPack(id: "zig-zag", title: "Zig Zag", license: PackLicense(id: "LicenseRef-All-Rights-Reserved"), authors: ["Jamizzle"], versions: [build])
                var changes = PackChanges()
                changes.changed = [.init(path: "assets/minecraft/textures/block/stone.png", detail: "zig-zag updated it")]
                changes.added = [.init(path: "assets/minecraft/textures/block/pale_oak_planks.png", detail: "From zig-zag")]
                changes.hidden = [.init(path: "assets/minecraft/items/bricks.json", detail: "zig-zag changed, but tardis-resource-pack still wins")]
                changes.lostPicks = ["assets/minecraft/textures/block/old.png"]
                let recipe = ResourcePacks.loadRecipe(ResourcePacks.recipeNames().first ?? "combined")
                serverDialogs = [
                    ("settings", AnyView(SettingsView(model: model))),
                    ("lab-setup", AnyView(LabSetupSheet(model: model, then: {}))),
                    ("share", AnyView(ShareSheet(recipe: recipe, history: []))),
                    ("update-review", AnyView(UpdateReviewSheet(pending: .init(pack: pack, version: build, changes: changes), onAccept: {}, onCancel: {}))),
                    ("servers-folder", AnyView(ServersFolderSheet())),
                    ("add-server", AnyView(AddServerSheet(model: model))),
                    ("rename", AnyView(RenameSheet(model: model, server: server))),
                    ("server-rename", AnyView(ServerRenameSheet(model: model, server: server, onDone: {}))),
                    ("add-plugin", AnyView(AddPluginSheet(server: server))),
                    ("welcome", AnyView(WelcomeView(model: model).frame(width: 1000, height: 700))),
                ]
            }
            for (name, view) in quitDialogs + serverDialogs {
                    let host = NSHostingView(rootView: view.tint(Theme.accent).background(Theme.background))
                    if ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_LIGHT"] != nil { host.appearance = NSAppearance(named: .aqua) }
                    if ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_DARK"] != nil { host.appearance = NSAppearance(named: .darkAqua) }
                    let size = host.fittingSize
                    host.frame = NSRect(origin: .zero, size: NSSize(width: max(size.width, 320), height: max(min(size.height, 1100), 200)))
                    let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: host.frame.width, height: host.frame.height), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    window.orderBack(nil)
                    try? await Task.sleep(for: .seconds(2))
                    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("dialog-\(name).png"))
                    }
                    window.orderOut(nil)
                    windows.append(window)
            }
            exit(0)
        }
    }
    #endif

    /// Set when macOS says it's about to power off, so the quit that follows doesn't wait for a click (K650).
    static var poweringOff = false

    /// Set once the backup question has been answered with Wait or Cancel, so the rest of that quit doesn't ask again.
    static var quitApproved = false

    /// Quitting is logged to the system log under the app's own bundle id, to look back on after a shutdown.
    static let quitLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "GilaMonster", category: "quit")

    /// The reason on the last quit request macOS sent, read when it arrives (see `handleQuit`).
    static var pendingQuitReason: QuitReason = .user

    static func reason(of event: NSAppleEventDescriptor?) -> QuitReason {
        let why = AEKeyword(QuitReason.code("why?"))
        let found = event?.attributeDescriptor(forKeyword: why) ?? event?.paramDescriptor(forKeyword: why)
        return QuitReason(code: found?.enumCodeValue)
    }

    /// The reason on the quit request macOS sends at a shutdown, restart or log out, or `.user` for an ordinary quit.
    @MainActor static func quitReason() -> QuitReason {
        let now = reason(of: NSAppleEventManager.shared().currentAppleEvent)
        return now.unattended ? now : pendingQuitReason
    }

    /// GilaMonster's own handler for macOS's quit request (K650). At a shutdown, restart or log out it doesn't go through
    /// the usual question: it holds macOS's request, stops every server with a save, answers, and quits. AppKit's own
    /// terminate is asked first; if the app is still here two seconds later, it exits, since the servers are saved.
    @MainActor @objc func handleQuit(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let reason = Self.reason(of: event)
        Self.pendingQuitReason = reason
        // A backup running at a shutdown, restart or log out: ask first (D215). macOS waits while the request is held.
        if reason.unattended, Backups.writing, !Self.quitApproved {
            Self.quitLog.notice("\(reason.words, privacy: .public) during a backup: asking first")
            let held = NSAppleEventManager.shared().suspendCurrentAppleEvent()
            QuitDuringBackup.ask(reason) { [weak self] choice in
                if choice == .keepUsing {
                    // Tells macOS the app declined, so the shutdown, restart or log out stops here.
                    held.map { NSAppleEventManager.shared().replyAppleEvent(forSuspensionID: $0) }?
                        .setParam(NSAppleEventDescriptor(int32: Int32(userCanceledErr)), forKeyword: keyErrorNumber)
                    if let held { NSAppleEventManager.shared().resume(withSuspensionID: held) }
                    return
                }
                Self.quitApproved = true
                if let held { NSAppleEventManager.shared().resume(withSuspensionID: held) }
                self?.handleQuit(event, withReplyEvent: reply)
            }
            return
        }
        guard reason.unattended, let model = Self.model, model.anyLive || !model.leftOver.isEmpty else { NSApp.terminate(nil); return }
        Self.quitLog.notice("\(reason.words, privacy: .public): stopping servers with a save, without asking")
        for server in model.servers where server.state.isLive {
            server.appendWrapper("\(reason.words), so GilaMonster is stopping this server with a save.", level: .info)
        }
        let held = NSAppleEventManager.shared().suspendCurrentAppleEvent()
        Backups.cancelInFlight()
        Task { @MainActor in
            await model.stopAll()
            if let held { NSAppleEventManager.shared().resume(withSuspensionID: held) }
            NSApp.terminate(nil)
            try? await Task.sleep(for: .seconds(2))
            exit(0)
        }
    }

    /// A signal asked the app to quit: stop every server with a save, without asking (nobody may be there to answer),
    /// then exit. A second signal while stopping changes nothing; the stops already have their own time limits.
    @MainActor static func quitOnSignal(_ sig: Int32) {
        guard !signalled else { return }
        signalled = true
        let name = sig == SIGTERM ? "SIGTERM" : sig == SIGHUP ? "SIGHUP" : "SIGINT"
        quitLog.notice("Asked to quit by \(name, privacy: .public): stopping servers with a save")
        guard let model else { exit(0) }
        for server in model.servers where server.state.isLive {
            server.appendWrapper("GilaMonster was asked to quit (\(name)), so it's stopping this server with a save.", level: .info)
        }
        Backups.cancelInFlight()
        Task { @MainActor in
            await model.stopAll()
            exit(0)
        }
    }

    /// A running server must get the chance to save before the app goes away.
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A backup is running: ask first, with its progress (D215). Wait and Cancel both mean "quit", servers included.
        if Backups.writing, !Self.quitApproved {
            QuitDuringBackup.ask(Self.quitReason()) { choice in
                guard choice != .keepUsing else { sender.reply(toApplicationShouldTerminate: false); return }
                Self.quitApproved = true
                Task { @MainActor in
                    if let model = Self.model, model.anyLive { await model.stopAll() }
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        }
        guard let model = Self.model, model.anyLive || !model.leftOver.isEmpty else {
            // A backup can run with every server stopped. Quitting mid-way used to leave its partial file (D213).
            Backups.cancelInFlight()
            return .terminateNow
        }
        // At a shutdown, restart or log out nobody is there to click, and a waiting box would make macOS cancel the
        // shutdown or force-quit without the save. So every server is stopped with a save, and the Mac carries on.
        var reason = Self.quitReason()
        if Self.poweringOff, !reason.unattended { reason = .shutdown }
        Self.quitLog.notice("Asked to quit with servers running: \(reason.words, privacy: .public)")
        if reason.unattended {
            for server in model.servers where server.state.isLive {
                server.appendWrapper("\(reason.words), so GilaMonster is stopping this server with a save.", level: .info)
            }
            Backups.cancelInFlight()
            Task { @MainActor in
                await model.stopAll()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        // K728 (owner, 2026-11-24: "Build and install (Recommended)"): a quit stopped a live server with one keypress, because
        // Return chose Stop and Quit. Now the alert names what stops, and Return keeps everything running.
        let text = QuitWording.make(running: model.servers.filter { $0.state.isLive }.map(\.profile.name),
                                    leftOver: model.leftOver.map(\.profile.name),
                                    packHost: model.servers.contains { $0.packHostIsListening },
                                    sessionAccess: SessionAccessService.shared.isListening)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.title
        alert.informativeText = text.detail
        let keep = alert.addButton(withTitle: "Keep Running")
        keep.keyEquivalent = "\r"
        let stop = alert.addButton(withTitle: text.stopButton)
        stop.keyEquivalent = ""
        stop.hasDestructiveAction = true
        alert.window.initialFirstResponder = keep
        NSAccessibility.post(element: alert.window, notification: .announcementRequested,
                             userInfo: [.announcement: "\(text.title) \(text.detail)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Backups.cancelInFlight()
        Task { @MainActor in
            await model.stopAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct GilaMonsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage(ThemeChoice.key) private var themeFlavor = Palette.Flavor.bold.rawValue

    init() {
        // GILAMONSTER_SAMPLE_TICKET=<file.png>: draws a ticket with made-up data and quits, to look at the layout.
        if let out = ProcessInfo.processInfo.environment["GILAMONSTER_SAMPLE_TICKET"] {
            MainActor.assumeIsolated { InviteTicketSheet.writeSample(to: URL(fileURLWithPath: out)) }
            exit(0)
        }
        let model = AppModel()
        AppDelegate.model = model
        _model = State(initialValue: model)
    }

    private var scheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        Window("GilaMonster", id: "main") {
            RootView(model: model)
                .frame(minWidth: 1120, minHeight: 640)
                .tint(Theme.accent)
                .preferredColorScheme(scheme)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { if !AdvisorTrial.isOn { ServerCommands(model: model) } }

        Settings {
            if AdvisorTrial.isOn {
                Text("This trial has no settings.").padding(40)
            } else {
                SettingsView(model: model).tint(Theme.accent).preferredColorScheme(scheme)
            }
        }

        MenuBarExtra(isInserted: .constant(!AdvisorTrial.isOn)) {
            StatusMenu(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
    }
}

struct ServerCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Server…") { model.showAddServer = true }.keyboardShortcut("n")
        }
        CommandMenu("Server") {
            Button("Start") { if let s = model.selected { Task { await s.start() } } }
                .keyboardShortcut("r").disabled(model.selected?.canStartNow != true)
            Button("Stop") { model.selected?.stop() }
                .keyboardShortcut(".", modifiers: [.command, .control]).disabled(model.selected?.state != .running && model.selected?.state != .starting)
            Button("Restart") { model.selected?.restart() }
                .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.selected?.state != .running)
            Divider()
            Button("Back Up Now") {
                if let s = model.selected { s.attempt { try await s.backupNow() } }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(model.selected == nil)
        }
        CommandGroup(after: .windowList) {
            Button("Requests Waiting for You") { SessionAskWindow.shared.show(activate: true) }
                .keyboardShortcut("r", modifiers: [.command, .option])
        }
        CommandGroup(after: .sidebar) {
            Button(model.showIssues ? "Hide Issues" : "Show Issues") { model.showIssues.toggle(); model.issuesOpenedByHand = model.showIssues }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            ForEach(Array(PageID.visible.prefix(9).enumerated()), id: \.element) { index, page in
                Button(page.title) { model.page = page }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
        }
    }
}

/// The menu bar mark: Brand's template, with a dot while a server runs. While a session's ask waits for the owner,
/// it shows how many (K679).
struct MenuBarLabel: View {
    let model: AppModel
    private let service = SessionAccessService.shared

    var body: some View {
        let waiting = service.waiting.count
        if waiting > 0 {
            HStack(spacing: 2) {
                Image(nsImage: Self.mark(dot: false))
                Text("\(waiting)").monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("GilaMonster, \(waiting) \(waiting == 1 ? "request" : "requests") waiting for you")
        } else {
            Image(nsImage: Self.mark(dot: model.anyLive))
                .accessibilityLabel(model.anyLive ? "GilaMonster, server running" : "GilaMonster")
        }
    }

    /// The template from brand/ (copied into the app by build-app.sh), drawn as a template so macOS colors it for the
    /// menu bar. A running server adds a dot in its lower right corner, in the same template color.
    static func mark(dot: Bool) -> NSImage {
        let base = NSImage(named: "MenuBarTemplate") ?? NSImage(systemSymbolName: "square.fill", accessibilityDescription: nil) ?? NSImage()
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            if dot {
                NSColor.black.setFill()  // theme-exempt: a template image; macOS colors it for the menu bar
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: 0, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct StatusMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !SessionAccessService.shared.waiting.isEmpty {
            Button("Requests Waiting for You (\(SessionAccessService.shared.waiting.count))…") { SessionAskWindow.shared.show(activate: true) }
            Divider()
        }
        let today = SessionAccessService.shared.today.active(now: Date())
        let went = SessionAccessService.shared.wentAhead.filter { Calendar.autoupdatingCurrent.isDateInToday($0.at) }.prefix(5)
        if !today.isEmpty || !went.isEmpty {
            if !today.isEmpty {
                Text("Allowed for today: \(today.map(\.family.words).joined(separator: "; "))")
                Button("Revoke Today's Allows") { SessionAccessService.shared.revokeToday() }
            }
            if !went.isEmpty {
                Text("Went ahead without asking:")
                ForEach(Array(went.enumerated()), id: \.offset) { _, w in
                    Text("\(w.at.formatted(date: .omitted, time: .shortened)) \(w.text)")
                }
            }
            Divider()
        }
        ForEach(model.listed) { server in
            Text("\(server.profile.name): \(server.state.title)")
            if server.state.canStart {
                Button("Start \(server.profile.name)") { Task { await server.start() } }.disabled(!server.canStartNow)
            } else if server.state == .running {
                Button("Stop \(server.profile.name)") { server.stop() }
            }
            Divider()
        }
        Button("Open GilaMonster") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var serversFolder = AppPaths.servers.path
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage(ThemeChoice.key) private var themeFlavor = Palette.Flavor.bold.rawValue
    var body: some View {
        Form {
            Picker("Theme", selection: Binding(get: { Palette.Flavor(rawValue: themeFlavor) ?? .bold }, set: { flavor in
                Announcer.pageChanged()   // the page redraws in the new colors; its callouts aren't news
                Theme.flavor = flavor
                themeFlavor = flavor.rawValue
                Announcer.say("\(flavor == .quiet ? "Quiet" : "Bold") theme", force: true)
            })) {
                Text("Bold").tag(Palette.Flavor.bold)
                Text("Quiet").tag(Palette.Flavor.quiet)
            }
            .pickerStyle(.segmented)
            Hint("Bold uses the red-orange and turquoise strongly. Quiet keeps them for what matters. Both meet the same contrast rules, in light and dark.")
            Picker("Appearance", selection: $appearance) {
                Text("Match System").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Toggle("Tell me when a new GilaMonster is on GitHub", isOn: $model.checkAppUpdates)
            Toggle("Notify me about crashes, failed backups and low disk space", isOn: Binding(get: { Alerts.enabled }, set: { Alerts.enabled = $0 }))
            LabeledContent("Version", value: GilaMonster.version)
            LabeledContent("Servers folder") {
                HStack {
                    Text((serversFolder as NSString).abbreviatingWithTildeInPath).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    Button("Change…") { chooseServersFolder() }
                }
            }
            LabeledContent("Custom issue rules") {
                Button("Show Folder") {
                    try? FileOps.ensureDir(AppPaths.rules)
                    NSWorkspace.shared.open(AppPaths.rules)
                }
            }
            Hint("Add your own log rules as JSON files in that folder. See the README for the format.")
            Section {
                ForEach(AppModule.allCases) { module in
                    Toggle(isOn: Binding(get: { Modules.shared.isOn(module) }, set: { on in
                        Modules.shared.set(module, on: on)
                        // Off means off straight away, including a check that's already running.
                        if module == .advisor, !on { AdvisorCenter.shared.cancelAll() }
                    })) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.title).foregroundStyle(Theme.ink)
                                Text(module.summary).font(.caption).foregroundStyle(Theme.muted)
                            }
                        } icon: {
                            Image(systemName: module.icon).foregroundStyle(Theme.accent)
                        }
                    }
                }
            } header: {
                Text("Features")
            } footer: {
                Text("Turning one off hides it and stops its background work. Nothing it has saved is deleted, and turning it back on picks up where it left off.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            SessionAccessSection()
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 720)
    }

    private func chooseServersFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = AppPaths.servers
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            try? AppPaths.chooseServers(url)
            serversFolder = url.path
        }
    }
}
