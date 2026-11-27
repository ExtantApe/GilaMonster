import AppKit
import GilaMonsterCore
import SwiftUI

struct OverviewPage: View {
    @Bindable var model: AppModel
    let server: ServerController
    @Binding var renaming: Bool
    @State private var confirmRemove = false
    @State private var choosingIcon = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The status glyph pulses once when the state changes, and not at all with Reduce Motion.
    @State private var pulse = false

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)]
    private var factColumns: [GridItem] { [GridItem(.adaptive(minimum: 220 * Theme.grow), spacing: 12, alignment: .top)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if server.isLab { LabRunCard(model: model) }
                UpgradeBanner(server: server)
                if server.allowlistSurprise {
                    Callout(tone: .info, title: "The allowlist is on", detail: "New servers on Minecraft 26 start with it on, so only players you add can join. Turn it off in Configs under Players, or add people to the allowlist there.")
                }
                if server.needsRestart {
                    Callout(tone: .warning, title: "Restart needed", detail: pendingDetail) {
                        Button("Review") { model.page = .changes }.buttonStyle(.themed)
                    }
                }
                if let plan = server.restartPlan {
                    Callout(tone: .info, title: planTitle(plan)) {
                        Button("Cancel Restart") { server.cancelRestart() }.buttonStyle(.themed)
                    }
                }

                // Needs you and Players online side by side, stacked when the window is narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        needsYou.frame(minWidth: 300 * Theme.grow)
                        playersOnline.frame(minWidth: 260 * Theme.grow)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        needsYou
                        playersOnline
                    }
                }

                LazyVGrid(columns: factColumns, alignment: .leading, spacing: 12) {
                    connectCard
                    healthCard
                    backupsCard
                    softwareCard
                }
                if !server.isLab { ConnectionsCard(server: server) }
            }
            .padding(20)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: server.backups.first?.date) { await server.refreshDriveWarning() }
        .sheet(isPresented: $choosingIcon) {
            VStack(alignment: .trailing, spacing: 12) {
                ServerIconCard(server: server)
                Button("Done") { choosingIcon = false }.buttonStyle(.themedPrimary).keyboardShortcut(.defaultAction)
            }
            .padding(20).frame(minWidth: 460)
        }
        .confirmationDialog("Remove \(server.displayName) from GilaMonster?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { model.remove(server) }
        } message: {
            Text("The server's folder stays where it is, with all its files and worlds. Backups aren't deleted either.")
        }
    }

    private var openIssueCount: Int { server.issues.filter { $0.status == .open }.count }

    /// The status sentence with its glyph, the actions beside it, and the one muted fact line.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                GlyphView(glyph: server.state.glyph, size: 22)
                    .scaleEffect(pulse ? 1.35 : 1)
                Text(server.headline)
                    .type(.display(28)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(server.headlineSpoken)
                Spacer(minLength: 12)
                actions
            }
            // The folder's name, small, when the headline shows the server message or the owner's name (K824).
            if let folder = server.folderLine {
                Text(folder).type(.label()).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Text(NeedsYou.factLine(software: server.profile.software.label, running: server.state == .running, since: server.startedAt,
                                   lastBackup: server.backups.first?.date, isLab: server.isLab,
                                   needs: NeedsYou.items(needsYouFacts).count, openIssues: openIssueCount))
                .foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            // What last stopped it, from the server's stop file (K798), while it's down.
            if !server.state.isLive, let stop = server.lastStop {
                Text(StopLog.sentence(stop)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .onChange(of: server.state) {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.18)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.easeIn(duration: 0.2)) { pulse = false }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            // Start, Stop and Restart here and in the toolbar (owner, 2026-11-16: "Both").
            if server.state.canStart {
                Button { Task { await server.start() } } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(.themedPrimary).disabled(!server.canStartNow)
            } else {
                Button { server.stop(by: .button("Overview")) } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.themed).disabled(server.state != .running && server.state != .starting)
                Button { server.restart(by: .button("Overview")) } label: { Label("Restart", systemImage: "arrow.clockwise") }
                    .buttonStyle(.themed).disabled(server.state != .running)
            }
            Button("Show in Finder") { NSWorkspace.shared.open(server.paths.root) }.buttonStyle(.themed)
            Menu {
                // The folder path, server icon and rename live here, out of the way (K672).
                Section((server.paths.root.path as NSString).abbreviatingWithTildeInPath) {
                    Button("Copy Folder Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(server.paths.root.path, forType: .string)
                    }
                }
                if !server.isLab {
                    Button("Rename…") { renaming = true }
                    Button("Server Icon…") { choosingIcon = true }
                    Divider()
                    Button("Remove from GilaMonster…") { confirmRemove = true }.disabled(server.state.isLive)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions").help("More actions")
        }
    }

    private var needsYouFacts: NeedsYouFacts {
        var f = NeedsYouFacts()
        f.isLab = server.isLab
        f.hasBackup = !server.backups.isEmpty
        f.autoBackups = server.profile.backup.enabled
        f.driveWarning = server.backupDriveWarning
        f.seriousIssues = server.issues.filter { $0.status == .open && $0.severity >= .error }.count
        f.connectionProblems = server.connectionProblems
        f.pluginUpdates = server.plugins.filter { server.record(for: $0).available != nil }.map(\.name)
        f.softwareUpdate = server.softwareUpdate.map { u in u.build.map { "build \($0)" } ?? "version" }
        return f
    }

    /// Needs you, as one quiet card: each item with its words and its one action, or "Nothing needs you."
    private var needsYou: some View {
        let items = NeedsYou.items(needsYouFacts)
        return FactCard(title: items.isEmpty ? "Nothing needs you" : "Needs you (\(items.count))") {
            if items.isEmpty {
                Text(server.isLab ? "All clear." : "Backups are on and everything is up to date. No connection problems turned up.")
                    .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(items) { item in
                let tone: Tone = item.tone == .warning ? .warning : .info
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: tone.icon).foregroundStyle(tone.color).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).type(.label(.semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        if !item.detail.isEmpty { Text(item.detail).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                        if let action = item.action, let title = item.actionTitle {
                            Button(title) { perform(action) }
                                .buttonStyle(item.kind == .noBackup || items.count == 1 ? .themedPrimary : .themed)
                                .disabled(action == .backUpNow && server.isBackingUp)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(tone.announcement.prefix): \(item.title)")
            }
        }
    }

    /// Who's on now, with their made-up faces and how long they've been on when the log says.
    private var playersOnline: some View {
        FactCard(title: server.state == .running ? "Players online (\(server.players.count))" : "Players online") {
            if server.state != .running {
                Text("The server isn't running.").foregroundStyle(Theme.muted)
            } else if server.players.isEmpty {
                Text("Nobody is on right now.").foregroundStyle(Theme.muted)
            }
            ForEach(server.state == .running ? server.players.sorted().prefix(8).map { $0 } : [], id: \.self) { name in
                HStack(spacing: 8) {
                    FaceView(name: name, size: 24)
                    Text(name).foregroundStyle(Theme.ink).rowName(name)
                    Spacer(minLength: 8)
                    if let minutes = onFor(name) { Text(minutes).monospacedDigit().foregroundStyle(Theme.muted) }
                }
                .accessibilityElement(children: .combine)
            }
            if server.state == .running, server.players.count > 8 {
                Text("and \(server.players.count - 8) more").foregroundStyle(Theme.muted)
            }
            if !server.knownPlayers.isEmpty || !server.players.isEmpty {
                Button("Open Players") { model.page = .players }.buttonStyle(.themed).padding(.top, 2)
            }
        }
    }

    /// "41 min" from the open session in the server's log, if there is one.
    private func onFor(_ name: String) -> String? {
        guard let start = server.playerHistory.first(where: { $0.name == name && $0.end == nil })?.start else { return nil }
        let minutes = max(1, Int(Date().timeIntervalSince(start) / 60))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) m"
    }

    private func perform(_ action: NeedsYouItem.Action) {
        switch action {
        case .backUpNow: server.attempt { try await server.backupNow() }
        case .turnOnAutoBackups: server.profile.backup.enabled = true
        case .openBackups: model.page = .backups
        case .openIssues: model.showIssues = true
        case .openPlugins: model.page = .plugins
        case .openSoftware: model.page = .software
        }
    }

    private var pendingDetail: String {
        var parts: [String] = []
        if !server.pending.isEmpty { parts.append("\(server.pending.count) change\(server.pending.count == 1 ? "" : "s") waiting") }
        if server.launchChangedSinceStart { parts.append("launch settings changed") }
        return parts.joined(separator: " and ") + "."
    }

    private func planTitle(_ plan: RestartPlan) -> String {
        if plan.whenEmpty { return "Restarting when the last player leaves" }
        if let at = plan.at { return "Restarting at \(at.formatted(date: .omitted, time: .shortened))" }
        return "Restart planned"
    }

    private var connectCard: some View {
        FactCard(title: "Connect") {
            let port = server.serverPort
            // The Lab only listens on this Mac, so a network address would just fail.
            let local = server.isLab ? nil : SystemInfo.lanAddress().map { port == 25565 ? $0 : "\($0):\(port)" }
            Fact(label: "On this Mac", value: port == 25565 ? "localhost" : "localhost:\(port)")
            if let local { Fact(label: "On your network", value: local) }
            Fact(label: "Server message", value: server.serverMessage ?? "Not set")
            Fact(label: "Players online", value: server.state == .running ? "\(server.players.count)" : "None")
            if !server.players.isEmpty {
                Text(server.players.sorted().joined(separator: ", ")).type(.body).foregroundStyle(Theme.ink)
            }
            if !server.isLab { ConnectCheckRow(server: server) }
            if let local {
                Button("Copy Network Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(local, forType: .string)
                }
                .buttonStyle(.themed)
            }
        }
    }

    private var healthCard: some View {
        FactCard(title: "Health") {
            if let tps = server.tps, server.state == .running {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ticks per second").foregroundStyle(Theme.muted)
                    Spacer()
                    Badge(text: String(format: "%.1f", tps.oneMinute), tone: tps.isHealthy ? .good : .warning)
                }
                .accessibilityElement(children: .combine)
                .helped("20 is perfect. Below about 18, players start to notice lag. Last 5 and 15 minutes: \(String(format: "%.1f", tps.fiveMinutes)), \(String(format: "%.1f", tps.fifteenMinutes)).")
            }
            if let mspt = server.mspt, server.state == .running {
                Fact(label: "Time per tick", value: String(format: "%.1f ms of 50", mspt))
            }
            if let m = server.metrics {
                Fact(label: "Memory in use", value: Format.bytes(m.memoryBytes))
                ProgressView(value: min(1, Double(m.memoryBytes) / Double(server.profile.launch.maxMemoryMB * 1_048_576)))
                    .accessibilityLabel("Memory used, out of the \(Format.memory(mb: server.profile.launch.maxMemoryMB)) maximum")
                Fact(label: "CPU", value: "\(Int(m.cpuPercent))%")
                Fact(label: "Heap limit", value: Format.memory(mb: server.profile.launch.maxMemoryMB))
                Hint("100% is one CPU core. Memory includes Java's own overhead, so it can exceed the heap limit.")
            } else {
                Fact(label: "Heap limit", value: Format.memory(mb: server.profile.launch.maxMemoryMB))
                Fact(label: "This Mac", value: Format.memory(mb: SystemInfo.memoryMB))
                Hint("Live figures appear while the server runs.")
            }
        }
    }

    /// The server software and its plugins in one card, since plugin updates also show under Needs you.
    private var softwareCard: some View {
        FactCard(title: "Software") {
            Fact(label: "Running", value: server.profile.software.label)
            if let java = server.resolvedJava() { Fact(label: "Java", value: java.major > 0 ? String(java.major) : "Custom") }
            if let update = server.softwareUpdate {
                Badge(text: "Build \(update.build.map(String.init) ?? "") available", tone: .info, icon: "arrow.down.circle.fill")
            } else if server.profile.software.supportStatus == "UNSUPPORTED" {
                Badge(text: "This version no longer gets updates", tone: .warning)
            }
            let updates = server.plugins.filter { server.record(for: $0).available != nil }.count
            Fact(label: "Plugins installed", value: "\(server.plugins.filter(\.enabled).count)")
            Fact(label: "Plugin updates", value: "\(updates)")
            Fact(label: "Plugins without a source", value: "\(server.plugins.filter { !server.record(for: $0).source.isSet }.count)")
            WrapRow {
                Button("Open Software") { model.page = .software }.buttonStyle(.themed)
                Button("Open Plugins") { model.page = .plugins }.buttonStyle(.themed)
            }
        }
    }

    private var backupsCard: some View {
        FactCard(title: "Backups") {
            if let latest = server.backups.first {
                Fact(label: "Latest", value: latest.date.formatted(.relative(presentation: .named)))
                Fact(label: "Size", value: Format.bytes(latest.size))
            } else {
                Fact(label: "Latest", value: "None yet")
            }
            Fact(label: "Automatic", value: server.profile.backup.enabled ? "Every \(server.profile.backup.intervalHours) h" : "Off")
            if let drill = server.profile.lastDrill {
                Fact(label: drill.passed ? "Last proven" : "Last drill", value: drill.passed ? drill.date.formatted(.relative(presentation: .named)) : "Failed")
            }
            Button("Back Up Now") { server.attempt { try await server.backupNow() } }
                .buttonStyle(.themed).disabled(server.isBackingUp)
        }
    }
}

/// Only runs when pressed, because it sends this Mac's public address to outside services.
struct ConnectCheckRow: View {
    let server: ServerController
    @State private var checking = false

    var body: some View {
        if let result = server.connectResult {
            Callout(tone: result.reachable ? .good : .warning, title: result.reachable ? "Reachable from the internet" : "Not reachable from the internet", detail: result.detail)
        }
        HStack {
            Button("Can Friends Connect?") { run() }.buttonStyle(.themed).disabled(checking)
                .disabled(because: server.state != .running && !checking ? "Start the server first. This checks it from the internet." : nil)
            if checking { ProgressView().controlSize(.small).accessibilityLabel("Checking") }
        }
        .helped("Asks an outside service to try connecting. This shares your public address with api.ipify.org and api.mcsrvstat.us.")
    }

    private func run() {
        checking = true
        server.attempt {
            defer { checking = false }
            try await server.checkConnection()
        }
    }
}


/// Icons to rotate between: the ones in the server's server-icons folder, with the one in use marked.
struct ServerIconCard: View {
    let server: ServerController
    @State private var icons: [ServerIconChoice] = []
    @State private var unsaved = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        Card(title: "Server icon", systemImage: "photo") {
            if icons.isEmpty {
                Text(unsaved ? "The icon in use isn't in the icon folder yet." : "No icons in the icon folder yet.").foregroundStyle(Theme.ink)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), alignment: .top)], alignment: .leading, spacing: 10) {
                    ForEach(icons) { icon in tile(icon) }
                }
            }
            if unsaved {
                HStack {
                    Hint("The icon in use isn't one of these. It's saved into the folder before another is picked.")
                    Button("Keep It Now") { act { _ = try ServerIcons.keepCurrent(server.paths) } }.buttonStyle(.themed)
                }
            }
            Hint("Minecraft reads the icon when the server starts, so a new one shows in players' server lists after the next restart. Icons are 64×64 PNGs.")
            if let message { Callout(tone: .good, title: message) }
            if let error { Callout(tone: .warning, title: error) }
            HStack {
                Button("Add Icon…") { add() }.buttonStyle(.themed)
                Button("Open Icon Folder") {
                    try? FileOps.ensureDir(ServerIcons.folder(server.paths))
                    NSWorkspace.shared.open(ServerIcons.folder(server.paths))
                }
                .buttonStyle(.themed)
                Button("Refresh") { reload() }.buttonStyle(.themed)
            }
        }
        .onAppear { reload() }
    }

    private func tile(_ icon: ServerIconChoice) -> some View {
        Button {
            act {
                try ServerIcons.use(icon, paths: server.paths)
                message = "\(icon.name) is the icon now" + (server.state.isLive ? ". Players see it after the next restart." : ".")
            }
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let image = NSImage(contentsOf: icon.file) {
                        Image(nsImage: image).interpolation(.none).resizable().frame(width: 64, height: 64)
                    } else {
                        Color.clear.frame(width: 64, height: 64)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(icon.inUse ? Theme.accent : Theme.controlBorder, lineWidth: icon.inUse ? 3 : 1))
                Text(icon.name).type(.body).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.center).frame(width: 76)
                if icon.inUse { Text("In use").type(.label(.semibold)).foregroundStyle(Theme.accent) }
                else if !icon.fits { Text("\(icon.width)×\(icon.height)").type(.body).foregroundStyle(Theme.warning) }
            }
        }
        .buttonStyle(.plain)
        .disabled(icon.inUse || !icon.fits)
        .accessibilityLabel("\(icon.name)\(icon.inUse ? ", in use" : "")\(icon.fits ? "" : ", \(icon.width) by \(icon.height), not usable")")
        .accessibilityHint(icon.inUse || !icon.fits ? "" : "Makes this the server icon")
        .help(icon.fits ? (icon.inUse ? "In use" : "Use this icon") : "Minecraft needs 64×64. Add it again to have it scaled.")
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp, .tiff, .heic]
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        act {
            var notes: [String] = []
            for url in panel.urls {
                switch try ServerIcons.add(url, paths: server.paths) {
                case let .added(file): notes.append("Added \(file.deletingPathExtension().lastPathComponent).")
                case let .scaled(file, from): notes.append("Added \(file.deletingPathExtension().lastPathComponent), scaled from \(from)×\(from) to 64×64.")
                case let .alreadyThere(file): notes.append("\(url.lastPathComponent) is already there as \(file.deletingPathExtension().lastPathComponent).")
                }
            }
            message = notes.joined(separator: " ")
        }
    }

    private func act(_ work: () throws -> Void) {
        error = nil
        message = nil
        do { try work() } catch { self.error = error.localizedDescription }
        reload()
    }

    private func reload() {
        icons = ServerIcons.list(server.paths)
        unsaved = ServerIcons.activeIsUnsaved(server.paths)
    }
}
