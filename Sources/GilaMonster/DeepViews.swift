import AppKit
import GilaMonsterCore
import SwiftUI

// MARK: - The preview every deep change gets

struct RenamePlanView: View {
    @Binding var plan: RenamePlan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($plan.items) { $item in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: $item.selected) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.description).foregroundStyle(Theme.ink)
                                Text(item.location).font(.body).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                        ForEach(item.changes.prefix(6), id: \.self) { change in
                            Text(change).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.ink).padding(.leading, 22)
                        }
                        if item.changes.count > 6 { Hint("and \(item.changes.count - 6) more").padding(.leading, 22) }
                        if let warning = item.warning { Callout(tone: .warning, title: warning) }
                    }
                }
                if !plan.notes.isEmpty {
                    Divider()
                    Text("Can't be changed from here").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    ForEach(plan.notes, id: \.self) { Hint($0) }
                }
                if !plan.mentions.isEmpty {
                    Divider()
                    Text("Also mention this name, and won't be changed").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    ForEach(plan.mentions, id: \.self) {
                        Text($0).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
    }
}

struct WorldRenameSheet: View {
    let server: ServerController
    let world: WorldEntry
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var plan: RenamePlan?

    private var problem: String? { WorldRename.problem(with: name, world: world, existing: server.worlds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetTitle("Rename \(world.title)")
            TextField("New name", text: $name).textFieldStyle(.roundedBorder).focusOnOpen()
                .onChange(of: name) { plan = problem == nil ? server.worldRenamePlan(world, to: name) : nil }
            if !name.isEmpty, let problem { Callout(tone: .warning, title: problem) }
            if plan != nil {
                RenamePlanView(plan: Binding(get: { plan! }, set: { plan = $0 }))
                Hint("The server stops while this happens. A restore point is made and verified first, and you can undo it afterwards.")
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
                Spacer()
                if Modules.shared.isOn(.testCopies) {
                    Button("Try on a Test Copy") {
                        let target = name
                        dismiss()
                        Task { await server.startTrial(.worldRename(worldName: world.name, to: target)) }
                    }
                    .buttonStyle(.themedPrimary).disabled(plan == nil || server.trialPhase != nil)
                }
                Button("Rename") {
                    guard let plan else { return }
                    dismiss()
                    let target = name
                    server.attempt { try await server.applyRename(plan, rebuild: { server.worldRenamePlan(world, to: target) }) }
                }
                .buttonStyle(.themed).disabled(plan == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

struct ServerRenameSheet: View {
    let model: AppModel
    let server: ServerController
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var folder = ""
    @State private var plan: RenamePlan?

    private var formats: [String] { ServerRename.folderFormats(for: name) }
    private var folderChanges: Bool { !folder.isEmpty && folder != server.paths.root.lastPathComponent }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetTitle("Rename Everywhere")
            TextField("New server name", text: $name, prompt: Text("My Server")).textFieldStyle(.roundedBorder).focusOnOpen()
                .onChange(of: name) { _, _ in
                    if !formats.contains(folder) { folder = formats.first ?? "" }
                    rebuild()
                }
            if !formats.isEmpty {
                Picker("Folder name", selection: $folder) {
                    ForEach(formats, id: \.self) { Text($0).tag($0) }
                    Text("Keep \(server.paths.root.lastPathComponent)").tag(server.paths.root.lastPathComponent)
                }
                .onChange(of: folder) { rebuild() }
            }
            if plan != nil {
                RenamePlanView(plan: Binding(get: { plan! }, set: { plan = $0 }))
                Hint("The backup folder follows too. The server stops while this happens. A restore point is made and verified first.")
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rename Everywhere") { apply() }
                    .buttonStyle(.themedPrimary).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || plan == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func rebuild() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { plan = nil; return }
        plan = server.serverRenamePlan(name: name, folder: folderChanges ? folder : nil)
    }

    private func apply() {
        guard let plan else { return }
        let (newName, newFolder) = (name, folderChanges ? folder : nil)
        dismiss()
        onDone()
        server.attempt {
            try await server.applyRename(plan, rebuild: { server.serverRenamePlan(name: newName, folder: newFolder) }, afterwards: {
                if try server.rename(to: newName, moveFolderTo: newFolder) != nil { model.pathsChanged() }
            })
        }
    }
}

// MARK: - Test copies

struct TrialBanner: View {
    let server: ServerController

    var body: some View {
        if let phase = server.trialPhase, let change = server.trialChange {
            switch phase {
            case .finished:
                finished(change)
            case .open:
                Callout(tone: .info, title: "The test copy is running", detail: "Connect at localhost:\(server.trialController?.serverPort ?? 0) to try \(change.title). It's a copy: nothing here reaches the real server.") {
                    Button("Finish Testing") { Task { await server.finishOpenTrial() } }.buttonStyle(.themed)
                }
            default:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text("\(phase.title) \(change.title)").foregroundStyle(Theme.ink)
                    Spacer()
                    Button("Cancel") { Task { await server.collapseTrial() } }.buttonStyle(.themed)
                }
                .padding(12)
                .background(Theme.infoWash, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
        }
    }

    @ViewBuilder private func finished(_ change: TrialChange) -> some View {
        let report = server.trialReport ?? TrialReport()
        Callout(tone: report.passed ? .good : .danger, title: report.passed ? "\(change.title) worked on the test copy" : "\(change.title) had problems on the test copy", detail: detail(report)) {
            VStack(alignment: .trailing, spacing: 6) {
                if report.passed {
                    Button("Back Up and Proceed") { server.attempt { try await server.proceedAfterTrial() } }.buttonStyle(.themedPrimary)
                }
                Button(report.passed ? "Not Now" : "Discard the Copy") { Task { await server.collapseTrial() } }.buttonStyle(.themed)
                if !report.passed, report.culprit == nil, report.booted || report.failure != nil {
                    Button("Find Which Plugin") { Task { await server.findTrialCulprit() } }.buttonStyle(.themed)
                }
                if !report.passed {
                    Button("Proceed Anyway") { server.attempt { try await server.proceedAfterTrial() } }.buttonStyle(.themedDanger)
                }
            }
        }
    }

    private func detail(_ report: TrialReport) -> String {
        var lines: [String] = []
        if let seconds = report.seconds { lines.append("It started in \(Int(seconds)) seconds.") }
        if let failure = report.failure { lines.append(failure) }
        if !report.blockers.isEmpty { lines.append("It couldn't start: " + report.blockers.joined(separator: ", ") + ".") }
        if !report.failedPlugins.isEmpty { lines.append("Plugins with problems: " + report.failedPlugins.joined(separator: ", ") + ".") }
        if let culprit = report.culprit { lines.append(culprit) }
        lines += report.problems.prefix(5)
        lines += report.notes
        if report.passed { lines.append("It doesn't prove every feature works, but it loaded cleanly. Proceeding removes the copy, makes a restore point and makes the change for real.") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Players

struct PlayersPage: View {
    #if DEBUG
    /// Debug snapshots only: the made-up player to pick when the page opens.
    nonisolated(unsafe) static var snapshotPick: String?
    #endif
    let server: ServerController
    @State private var selected: PlayerInfo?
    @State private var merging: MergeSuggestion?
    @FocusState private var rosterFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            if !server.knownPlayers.isEmpty {
                roster.frame(width: 280)
                Rectangle().fill(Theme.border).frame(width: 1).accessibilityHidden(true)
            }
            Group {
                if let selected {
                    PlayerDetail(server: server, player: selected, online: server.players.contains(selected.title), back: { self.selected = nil }).id(selected.id)
                } else {
                    overview
                }
            }
            .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await server.refreshPlayers()
            #if DEBUG
            if let pick = Self.snapshotPick { selected = server.knownPlayers.first { $0.title == pick } }
            #endif
        }
        .sheet(item: $merging) { MergeSheet(server: server, suggestion: $0) }
    }

    /// The roster: On now, then Seen before, each row with a made-up face, the name, and the state as its shape and word.
    /// The selected row gets an edge marker as well as its tint. ↑↓ move the selection when the roster has focus.
    private var roster: some View {
        let split = PlayerRoster.split(server.knownPlayers, online: server.players)
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                rosterHeading("On now (\(split.onNow.count))")
                if split.onNow.isEmpty { Text("Nobody is on right now.").foregroundStyle(Theme.muted).padding(.horizontal, 8) }
                ForEach(split.onNow) { row($0, online: true) }
                Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 6).accessibilityHidden(true)
                rosterHeading("Seen before (\(split.seenBefore.count))")
                ForEach(split.seenBefore) { row($0, online: false) }
                Text("Filled circle: on now. Square: offline.").foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.top, 8)
            }
            .padding(12)
        }
        .background(Theme.background)
        .overlay {
            if rosterFocused { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: 2).padding(3).accessibilityHidden(true) }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($rosterFocused)
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.escape) { selected = nil; return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Players")
    }

    private func rosterHeading(_ text: String) -> some View {
        Text(text).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).padding(.horizontal, 8).padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ player: PlayerInfo, online: Bool) -> some View {
        let on = selected?.id == player.id
        let glyph: PixelGlyph = online ? .up : .stopped
        return HStack(spacing: 8) {
            FaceView(name: player.title, size: 28)
            Text(player.title).foregroundStyle(Theme.ink).rowName(player.title)
            Spacer(minLength: 4)
            GlyphView(glyph: glyph, size: 12)
            Text(online ? "On now" : "Offline").foregroundStyle(Theme.muted).fixedSize()
        }
        .padding(.vertical, 4).padding(.leading, 10).padding(.trailing, 8)
        .background(on ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if on { UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8).fill(Theme.popText).frame(width: 4).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = player; rosterFocused = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.title), \(online ? "on now" : "offline")")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selected = player }
    }

    private func move(_ offset: Int) {
        let order = PlayerRoster.order(server.knownPlayers, online: server.players)
        guard !order.isEmpty else { return }
        guard let current = selected, let at = order.firstIndex(where: { $0.id == current.id }) else {
            selected = offset > 0 ? order.first : order.last
            return
        }
        selected = order[min(max(0, at + offset), order.count - 1)]
    }

    private var overview: some View {
        Page(title: "Players", subtitle: "Who has played here, their snapshots, and who is on right now.") {
            if server.knownPlayers.isEmpty {
                EmptyMessage(icon: "person.2", title: "No players yet", detail: "Players show up here after their first visit.")
            }
            let collisions = PlayerMerge.caseCollisions(server.paths, players: server.knownPlayers)
            if !collisions.isEmpty {
                Callout(tone: .warning, title: "These names can overwrite each other's inventories", detail: "\(collisions.map { $0.joined(separator: " and ") }.joined(separator: "; ")). This server is in offline mode, so they're separate players, but Multiverse-Inventories names its files by player, and a Mac's disk treats these as the same file. Turning on online mode or merging them avoids it.")
            }
            if !server.mergeSuggestions.isEmpty {
                Card(title: "Possibly the same person", systemImage: "person.2.badge.gearshape") {
                    ForEach(server.mergeSuggestions) { suggestion in
                        HStack {
                            Text(suggestion.reason).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Review…") { merging = suggestion }.buttonStyle(.themed)
                        }
                    }
                }
            }
            if !server.failedJoins.isEmpty {
                Card(title: "Couldn't get in", systemImage: "person.fill.xmark") {
                    ForEach(server.failedJoins.prefix(12)) { failure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(failure.name), \(failure.date.formatted(.relative(presentation: .named)))").foregroundStyle(Theme.ink)
                            Hint(failure.meaning)
                        }
                    }
                }
            }
            LeaderboardCard(server: server)
            RegularsCard(server: server)
            SnapshotSettings(server: server)
            Card(title: "Who was on", systemImage: "clock") {
                if server.playerHistory.isEmpty { Hint("Nothing in the server's logs yet.") }
                ForEach(server.playerHistory.prefix(40)) { session in
                    HStack {
                        Text(session.name).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(when(session)).font(.body).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private func when(_ session: PlayerSession) -> String {
        let start = session.start.formatted(date: .abbreviated, time: .shortened)
        guard let end = session.end else { return "\(start), no recorded end" }
        return "\(start) to \(end.formatted(date: .omitted, time: .shortened))"
    }
}

struct SnapshotSettings: View {
    @Bindable var server: ServerController

    var body: some View {
        Card(title: "Automatic snapshots", systemImage: "camera") {
            Toggle("Snapshot each player's inventory while they play", isOn: $server.profile.playerSnapshots.enabled)
            Stepper("Every \(server.profile.playerSnapshots.intervalMinutes) minutes of play", value: $server.profile.playerSnapshots.intervalMinutes, in: 5...120, step: 5)
                .disabled(!server.profile.playerSnapshots.enabled)
            Stepper("Keep the latest \(server.profile.playerSnapshots.keep) per player", value: $server.profile.playerSnapshots.keep, in: 4...1000, step: 4)
                .disabled(!server.profile.playerSnapshots.enabled)
            Hint("Also taken as a player leaves. Includes each world and group's inventory when Multiverse-Inventories is in use. The server saves players about every 5 minutes, so a snapshot can be up to that old. It costs players nothing: files are only copied.")
        }
    }
}

struct PlayerDetail: View {
    let server: ServerController
    let player: PlayerInfo
    var online = false
    var back: (() -> Void)?
    @State private var snapshots: [PlayerSnapshot] = []
    @State private var restoring: PlayerSnapshot?
    @State private var viewing: PlayerSnapshot?
    @State private var backupChoice: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                FaceView(name: player.title, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.title).font(Theme.display(26)).foregroundStyle(Theme.ink).rowName(player.title).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 5) {
                        GlyphView(glyph: online ? .up : .stopped, size: 12)
                        Text(online ? "On now" : "Offline").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                    Text(subtitle).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).help(subtitle).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                if let back { Button("All Players") { back() }.buttonStyle(.themed).helped("Back to the overview of every player (Escape in the list)") }
            }
            HStack {
                Button("Take Snapshot Now") {
                    server.attempt {
                        try server.snapshotPlayer(player)
                        reload()
                    }
                }
                .buttonStyle(.themedPrimary)
                if !server.backups.isEmpty {
                    Menu("Get from a Backup") {
                        ForEach(server.backups.prefix(30)) { record in
                            Button(record.date.formatted(date: .abbreviated, time: .shortened)) {
                                server.attempt {
                                    _ = try await PlayerSnapshots.fromBackup(record, uuid: player.uuid, name: player.title, paths: server.paths, profile: server.profile)
                                    reload()
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
            }
            if let summary = PlayerFiles.summary(of: PlayerPaths(server.paths).data(player.uuid)) {
                Card(title: "Saved now", systemImage: "backpack") { InventoryView(summary: summary) }
            }
            if let stats = server.playerStats.first(where: { $0.uuid.lowercased() == player.uuid.lowercased() }) {
                PlayerStatsCard(stats: stats)
            }
            Card(title: "Snapshots", systemImage: "camera") {
                if snapshots.isEmpty { Hint("None yet. They're taken every 15 minutes of play by default, and as players leave.") }
                ForEach(snapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(snapshot.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.ink)
                            Hint(describe(snapshot))
                        }
                        Spacer()
                        Button("View") { viewing = viewing == snapshot ? nil : snapshot }.buttonStyle(.themed)
                            .accessibilityLabel("View the snapshot from \(snapshot.date.formatted(date: .abbreviated, time: .shortened))")
                        Button("Restore…") { restoring = snapshot }.buttonStyle(.themed)
                            .accessibilityLabel("Restore the snapshot from \(snapshot.date.formatted(date: .abbreviated, time: .shortened))")
                    }
                    if viewing == snapshot {
                        let folder = PlayerSnapshots.location(snapshot, profile: server.profile)
                        if let summary = PlayerFiles.summary(of: folder.appendingPathComponent("player.dat")) {
                            InventoryView(summary: summary)
                        }
                        ForEach(snapshot.containers.filter { $0.hasPrefix("worlds/") }, id: \.self) { container in
                            if let summary = PlayerFiles.summary(ofInventoryFile: folder.appendingPathComponent("inventories/\(container)")) {
                                Text("In \(container.components(separatedBy: "/")[1])").font(.body.weight(.semibold)).foregroundStyle(Theme.ink).padding(.top, 4)
                                InventoryView(summary: summary)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 980, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: reload)
        .task { await server.refreshStats() }
        .sheet(item: $restoring) { PlayerRestoreSheet(server: server, snapshot: $0, onDone: reload) }
    }

    private func reload() { snapshots = server.playerSnapshots(player) }

    private var subtitle: String {
        var parts = [player.uuid]
        if let time = player.playTime { parts.append("\(Int(time / 3600)) hours played") }
        if let last = player.lastSeen { parts.append("last saved \(last.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: " · ")
    }

    private func describe(_ s: PlayerSnapshot) -> String {
        let kind = ["playing": "While playing", "left": "As they left", "manual": "Taken by hand", "backup": "From a backup", "before-restore": "Before a restore"][s.trigger] ?? s.trigger
        return s.containers.isEmpty ? kind : "\(kind) · \(s.containers.count) world or group inventories"
    }
}

/// A player's items as slots, each with the item's name and its count in words, so nothing rests on a picture or a tint.
struct InventoryView: View {
    let summary: InventorySummary
    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 6, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if summary.items.isEmpty { Hint("Inventory is empty.") }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) { ForEach(summary.items) { slot($0) } }
            if !summary.enderItems.isEmpty {
                Text("Ender chest").font(.body.weight(.semibold)).foregroundStyle(Theme.ink).padding(.top, 4)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) { ForEach(summary.enderItems) { slot($0) } }
            }
            if let level = summary.level { Hint("Level \(level)" + (summary.dimension.map { " · in \($0.replacingOccurrences(of: "minecraft:", with: ""))" } ?? "")) }
        }
    }

    private func slot(_ item: InventoryItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(item.title).foregroundStyle(Theme.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Text("× \(item.count)").monospacedDigit().foregroundStyle(Theme.ink).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.count)")
    }
}

struct PlayerRestoreSheet: View {
    let server: ServerController
    let snapshot: PlayerSnapshot
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var inventoryOnly = true
    @State private var chosen: Set<String> = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetTitle("Restore \(snapshot.name)")
            Hint("From \(snapshot.date.formatted(date: .abbreviated, time: .shortened)). The world isn't touched, and their current state is snapshotted first.")
            Picker("What to restore", selection: $inventoryOnly) {
                Text("Inventory and ender chest").tag(true)
                Text("Everything: position, XP, health too").tag(false)
            }
            if !snapshot.containers.isEmpty {
                Text("Worlds and groups (Multiverse-Inventories)").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                ForEach(snapshot.containers, id: \.self) { container in
                    Toggle(title(container), isOn: Binding(
                        get: { chosen.contains(container) },
                        set: { if $0 { chosen.insert(container) } else { chosen.remove(container) } }))
                    .toggleStyle(.checkbox)
                }
                Hint("Leave all of these on unless you have a reason not to: the plugin can put a world's saved inventory back when a player joins. If the server is running, this applies at the next restart.")
            }
            if inventoryOnly, let worlds = PlayerSnapshots.crossWorld(snapshot, paths: server.paths, profile: server.profile) {
                Callout(tone: .warning, title: "This was taken in \(worlds.taken), and \(snapshot.name) is now in \(worlds.now)", detail: "Restoring only the inventory puts the \(worlds.taken) items in \(worlds.now). Choose Everything to send them back to \(worlds.taken) as well.")
            }
            if server.players.contains(snapshot.name) { Callout(tone: .warning, title: "\(snapshot.name) is online, so this applies at the next restart.") }
            if let error { Callout(tone: .danger, title: error) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Restore") { restore() }.buttonStyle(.themedPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { chosen = Set(snapshot.containers) }
    }

    private func title(_ container: String) -> String {
        let parts = container.components(separatedBy: "/")
        guard parts.count >= 2 else { return container }
        return "\(parts[1]) (\(parts[0] == "groups" ? "group" : "world"))"
    }

    private func restore() {
        do {
            let outcome = try server.restorePlayer(snapshot, inventoryOnly: inventoryOnly, containers: Array(chosen))
            if outcome == .staged { server.notice = "\(snapshot.name)'s restore applies at the next restart." }
            onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct MergeSheet: View {
    let server: ServerController
    let suggestion: MergeSuggestion
    @Environment(\.dismiss) private var dismiss
    @State private var plan: MergePlan?
    @State private var targetID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetTitle("Merge \(suggestion.from.title)")
            Text(suggestion.reason).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if suggestion.to.uuid.isEmpty {
                Picker("Merge into", selection: $targetID) {
                    Text("Choose a player").tag("")
                    ForEach(server.knownPlayers) { Text($0.title).tag($0.uuid) }
                }
                .onChange(of: targetID) { _, id in
                    plan = server.knownPlayers.first { $0.uuid == id }.map {
                        MergePlan(from: suggestion.from, to: PlayerRef(uuid: $0.uuid, name: $0.name))
                    }
                }
            }
            if let current = plan {
                if !suggestion.from.uuid.isEmpty {
                    Picker("Inventory, position and XP from", selection: Binding(get: { current.keepFromSource }, set: { plan?.keepFromSource = $0 })) {
                        Text("\(current.to.title) (kept profile)").tag(false)
                        Text("\(current.from.title) (old profile)").tag(true)
                    }
                    comparison(current)
                    Hint("Statistics are added together, and advancements from both are kept.")
                }
                let refusal = PlayerMerge.refusal(current, paths: server.paths)
                if let refusal { Callout(tone: .warning, title: "This merge can't be done here", detail: refusal) }
                let conflicts = PlayerMerge.conflicts(current, paths: server.paths)
                if !conflicts.isEmpty {
                    Text("Both have an inventory in these worlds or groups").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    ForEach(conflicts, id: \.self) { container in
                        Picker(container, selection: Binding(get: { current.useOldContainer[container] ?? false }, set: { plan?.useOldContainer[container] = $0 })) {
                            Text("Keep \(current.to.title)'s").tag(false)
                            Text("Use \(current.from.title)'s").tag(true)
                        }
                    }
                }
                let others = PlayerMerge.otherFiles(uuid: current.from.uuid, paths: server.paths)
                if !others.isEmpty {
                    Text("Plugin files for the old profile, not changed").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    ForEach(others.prefix(8), id: \.self) { Text($0).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.muted) }
                }
                Hint("The server stops while this happens. A restore point is made and verified first, and what's replaced is kept beside the backups. Permissions in LuckPerms and data in plugin databases can't be merged from here.")
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Merge") {
                    guard let plan else { return }
                    dismiss()
                    server.attempt { try await server.mergePlayers(plan) }
                }
                .buttonStyle(.themedPrimary).disabled(plan == nil || plan.flatMap { PlayerMerge.refusal($0, paths: server.paths) } != nil)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            if !suggestion.to.uuid.isEmpty { plan = MergePlan(from: suggestion.from, to: suggestion.to) }
        }
    }

    private func comparison(_ current: MergePlan) -> some View {
        let p = PlayerPaths(server.paths)
        func text(_ ref: PlayerRef) -> String {
            guard let s = PlayerFiles.summary(of: p.data(ref.uuid)) else { return "\(ref.title): no saved data" }
            return "\(ref.title): \(s.items.count) inventory stacks, \(s.enderItems.count) in ender chest, level \(s.level ?? 0)"
        }
        return VStack(alignment: .leading) { Hint(text(current.from)); Hint(text(current.to)) }
    }
}

// MARK: - Cleanup

struct CleanupPage: View {
    let server: ServerController
    @State private var selected: Set<String> = []
    @State private var scanned = false
    @State private var discarding: CleanupBatch?

    var body: some View {
        Page(title: "Cleanup", subtitle: "Leftovers from a server that's been running a long time. Nothing is deleted: items move beside your backups, where you can bring them back.") {
            HStack {
                Button("Scan Again") { Task { await scan() } }.buttonStyle(.themed)
                Button(selected.isEmpty ? "Move Selected Aside" : "Move \(selected.count) Selected Aside") {
                    let items = server.cleanupItems.filter { selected.contains($0.path) }
                    server.attempt { try await server.cleanUp(items); selected = defaults }
                }
                .buttonStyle(.themedPrimary)
                .disabled(because: !server.state.canStart ? "Stop the server first." : selected.isEmpty ? "Tick what to move first." : nil)
            }
            if !server.state.canStart { Hint("Stop the server to clean up its folder.") }
            group("Known leftovers", icon: "checkmark.seal", items: server.cleanupItems.filter { $0.confidence == .safe }, empty: "Nothing obvious to clean up.")
            group("Worth a look", icon: "questionmark.circle", items: server.cleanupItems.filter { $0.confidence == .review }, empty: "Nothing here.")
            if !server.cleanupBatches.isEmpty {
                Card(title: "Moved aside", systemImage: "tray.full") {
                    ForEach(server.cleanupBatches) { batch in
                        HStack {
                            Text("\(batch.date.formatted(date: .abbreviated, time: .shortened)): \(batch.items.count) items, \(Format.bytes(batch.size))").foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Bring Back") { server.attempt { try await server.undoCleanup(batch) } }.buttonStyle(.themed).disabled(!server.state.canStart)
                            Button("Delete…") { discarding = batch }.buttonStyle(.themedDanger)
                                .accessibilityLabel("Delete the cleanup from \(batch.date.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }
            }
        }
        .task {
            if !scanned { await scan() }
        }
        .confirmationDialog("Permanently delete these?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), presenting: discarding) { batch in
            Button("Delete", role: .destructive) { server.attempt { try await server.discardCleanup(batch) } }
        } message: { batch in
            Text("\(batch.items.count) items, \(Format.bytes(batch.size)), will be permanently deleted. This can't be undone.")
        }
    }

    private var defaults: Set<String> { Set(server.cleanupItems.filter { $0.confidence == .safe }.map(\.path)) }

    private func scan() async {
        await server.scanForCleanup()
        selected = defaults
        scanned = true
    }

    private func group(_ title: String, icon: String, items: [CleanupItem], empty: String) -> some View {
        Card(title: title, systemImage: icon) {
            if items.isEmpty { Hint(empty) }
            ForEach(items) { item in
                Toggle(isOn: Binding(
                    get: { selected.contains(item.path) },
                    set: { if $0 { selected.insert(item.path) } else { selected.remove(item.path) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.path) (\(Format.bytes(item.size)))").foregroundStyle(Theme.ink)
                        Hint(item.reason)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

// MARK: - Comparing backups

struct BackupDiffSheet: View {
    let server: ServerController
    let record: BackupRecord
    @Environment(\.dismiss) private var dismiss
    @State private var otherName = ""
    @State private var diff: BackupDiff?
    @State private var working = false
    @State private var error: String?

    private var others: [BackupRecord] { server.backups.filter { $0.id != record.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetTitle("Compare Backups")
            Picker("Compare \(record.date.formatted(date: .abbreviated, time: .shortened)) with", selection: $otherName) {
                Text("Choose a backup").tag("")
                ForEach(others) { Text($0.date.formatted(date: .abbreviated, time: .shortened)).tag($0.fileName) }
            }
            .onChange(of: otherName) { run() }
            if working { HStack { ProgressView().controlSize(.small); Text("Unpacking and comparing…").foregroundStyle(Theme.ink) } }
            if let error { Callout(tone: .danger, title: error) }
            if let diff {
                ScrollView { results(diff).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 420)
            }
            HStack { Spacer(); Button("Close") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(width: 620)
    }

    private func run() {
        guard let other = others.first(where: { $0.fileName == otherName }) else { return }
        diff = nil
        error = nil
        working = true
        let (older, newer) = other.date < record.date ? (other, record) : (record, other)
        Task {
            defer { working = false }
            do { diff = try await BackupCompare.compare(older, newer, profile: server.profile, paths: server.paths) }
            catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder private func results(_ d: BackupDiff) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if d.isEmpty { Hint("No differences in settings, plugins, worlds or players.") }
            if let jar = d.serverJar { section("Server") { row(jar.name, jar.before, jar.after) } }
            if !d.plugins.isEmpty {
                section("Plugins") { ForEach(d.plugins) { row($0.name, $0.before, $0.after) } }
            }
            if !d.settings.isEmpty {
                section("Settings") {
                    ForEach(d.settings) { setting in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(setting.file): \(setting.key)").font(.body).foregroundStyle(Theme.muted)
                            Text("\(setting.before ?? "(not set)") → \(setting.after ?? "(removed)")").font(.system(.body, design: .monospaced)).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            if !d.otherSettingsFiles.isEmpty {
                section("Other files that changed") { ForEach(d.otherSettingsFiles, id: \.self) { Text($0).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.ink) } }
            }
            if !d.worlds.isEmpty {
                section("Worlds") { ForEach(d.worlds) { Text(describe($0)).foregroundStyle(Theme.ink) } }
            }
            if !d.players.isEmpty {
                section("Players") {
                    ForEach(d.players) { player in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(player.name ?? player.uuid).foregroundStyle(Theme.ink)
                            if player.added { Hint("New player") } else if player.removed { Hint("No longer present") }
                            else if player.items.isEmpty { Hint("Position or stats changed. Same items.") }
                            ForEach(player.items) { item in
                                Hint("\(ConfigForm.humanize(item.item.replacingOccurrences(of: "minecraft:", with: ""))): \(item.before) → \(item.after)")
                            }
                        }
                    }
                }
            }
            if d.otherFilesChanged > 0 { Hint("\(d.otherFilesChanged) other files changed, such as logs and libraries.") }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func row(_ name: String, _ before: String?, _ after: String?) -> some View {
        Text("\(name): \(before ?? "(none)") → \(after ?? "(removed)")").foregroundStyle(Theme.ink)
    }

    private func describe(_ w: BackupDiff.WorldChange) -> String {
        if w.added { return "\(w.name): new world" }
        if w.removed { return "\(w.name): world removed" }
        var parts: [String] = []
        if w.chunksChanged > 0 { parts.append("\(w.chunksChanged) chunks saved again") }
        if w.regionsAdded > 0 { parts.append("\(w.regionsAdded) new regions explored") }
        if w.regionsRemoved > 0 { parts.append("\(w.regionsRemoved) regions removed") }
        return "\(w.name): " + parts.joined(separator: ", ")
    }
}
