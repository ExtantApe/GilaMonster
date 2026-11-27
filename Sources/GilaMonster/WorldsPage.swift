import AppKit
import GilaMonsterCore
import SwiftUI

/// Worlds on this server, managed through Multiverse-Core when it's installed.
struct WorldsPage: View {
    @Bindable var model: AppModel
    let server: ServerController
    @State private var creating = false
    @State private var importing: WorldEntry?
    @State private var editing: WorldEntry?
    @State private var cloning: WorldEntry?
    @State private var removing: WorldEntry?
    @State private var renaming: WorldEntry?
    @State private var deleting: WorldEntry?
    @State private var filter = ""
    @State private var showNotLoaded = false

    var body: some View {
        Page(title: "Worlds", subtitle: subtitle) {
            multiverseStatus
            if let operation = server.worldOperation { OperationCard(server: server, operation: operation) }
            worldLists
            Hint("Backups include every world, wherever it's stored. A world's folder name and environment can't be changed after it's created.")
        }
        .task { await server.refreshWorlds() }
        .onChange(of: server.plugins) { Task { await server.refreshWorlds() } }
        .sheet(isPresented: $creating) { CreateWorldSheet(server: server) }
        .sheet(item: $importing) { ImportWorldSheet(server: server, world: $0) }
        .sheet(item: $editing) { EditWorldSheet(server: server, world: $0) }
        .sheet(item: $renaming) { WorldRenameSheet(server: server, world: $0) }
        .sheet(item: $cloning) { CloneWorldSheet(server: server, world: $0) }
        .sheet(item: $deleting) { DeleteWorldSheet(server: server, world: $0) }
        .confirmationDialog("Remove \(removing?.title ?? "") from Multiverse?", isPresented: removeShown, presenting: removing) { world in
            Button("Remove") { server.attempt { try await server.removeWorldFromMultiverse(world) } }
        } message: { _ in
            Text("Multiverse stops loading it. Its folder and all its data stay on disk, and you can import it again later.")
        }
    }

    private func row(_ world: WorldEntry) -> some View {
        WorldRow(
            server: server, world: world, onImport: { importing = world }, onEdit: { editing = world },
            onClone: { cloning = world }, onRemove: { removing = world }, onDelete: { deleting = world }, onRename: { renaming = world })
    }

    /// Worlds in two groups: the ones that load at startup, and the rest, collapsed. A filter appears past ten worlds.
    @ViewBuilder private var worldLists: some View {
        let all = server.worlds
        let filtering = Overflow.showsWorldsFilter(worlds: all.count)
        let shown = filtering ? Overflow.matching(all, filter) { "\($0.title) \($0.name)" } : all
        let loaded = shown.filter(Overflow.loadsAtStartup)
        let notLoaded = shown.filter { !Overflow.loadsAtStartup($0) }
        if filtering {
            TextField("Filter worlds", text: $filter, prompt: ThemedPrompt("Filter worlds")).textFieldStyle(.themed).frame(maxWidth: 260)
                .accessibilityLabel("Filter worlds by name")
            if shown.isEmpty { Hint("No world matches \u{201C}\(filter)\u{201D}.") }
        }
        if !loaded.isEmpty || all.isEmpty || notLoaded.isEmpty {
            if !notLoaded.isEmpty || filtering { GroupHeading("Loaded (\(loaded.count))", help: "Worlds the server loads when it starts.") }
            ForEach(loaded) { row($0) }
        }
        if !notLoaded.isEmpty {
            DisclosureGroup(isExpanded: Binding(get: { showNotLoaded || !filter.isEmpty }, set: { showNotLoaded = $0 })) {
                VStack(spacing: 10) { ForEach(notLoaded) { row($0) } }.padding(.top, 6)
            } label: {
                HeadingText("Not loaded (\(notLoaded.count))").foregroundStyle(Theme.ink)
            }
            .accessibilityHint("Folders Multiverse doesn't load at startup, or that are missing")
        }
    }

    private var subtitle: String {
        let count = server.worlds.count
        return "\(count) world\(count == 1 ? "" : "s")"
            + (server.multiverseMajor.map { ", managed with Multiverse-Core \($0)" } ?? "")
    }

    private var removeShown: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    @ViewBuilder private var multiverseStatus: some View {
        if !server.profile.software.flavor.supportsPlugins {
            Callout(tone: .info, title: "Multiple worlds need plugins", detail: "Multiverse-Core runs on Paper, Purpur and Spigot. Vanilla servers have one world.")
        } else if server.multiverseMajor == nil {
            if let disabled = server.plugins.first(where: { $0.key == Multiverse.pluginKey }) {
                Callout(tone: .info, title: "Multiverse-Core is disabled") {
                    Button("Enable") { server.attempt { try await server.setEnabled(true, plugin: disabled) } }.buttonStyle(.themed)
                }
            } else if server.pending.contains(where: { $0.target == "plugin:\(Multiverse.pluginKey)" }) {
                Callout(tone: .warning, title: "Multiverse-Core installs at the next restart") {
                    Button("Review") { model.page = .changes }.buttonStyle(.themed)
                }
            } else {
                Callout(tone: .info, title: "Run many worlds with Multiverse-Core", detail: "The standard plugin for creating and managing extra worlds. GilaMonster checks it fits your Minecraft version, then works with it from here.") {
                    Button("Install") { server.attempt { try await server.addPlugin(source: Multiverse.source) } }
                        .buttonStyle(.themedPrimary).disabled(server.activity != nil)
                }
            }
        } else {
            FlowRow(spacing: 8) {
                Button("New World…") { creating = true }.buttonStyle(.themedPrimary).disabled(server.state != .running)
                Button("Refresh") { Task { await server.refreshWorlds() } }.buttonStyle(.themed)
                addOnsMenu
            }
            if server.state != .running {
                Callout(tone: .info, title: "Start the server to change worlds", detail: "Multiverse does this work from inside the running server.")
            }
        }
    }

    private var addOnsMenu: some View {
        Menu("Add-ons") {
            ForEach(Multiverse.addOns, id: \.title) { addOn in
                let name = "Multiverse-\(addOn.title.replacingOccurrences(of: " ", with: ""))".lowercased()
                Button("\(addOn.title): \(addOn.detail)") {
                    server.attempt { try await server.addPlugin(source: addOn.source) }
                }
                .disabled(server.plugins.contains { $0.key == name })
            }
        }
        .fixedSize()
        .frame(height: Theme.controlHeight)
    }
}

private struct OperationCard: View {
    let server: ServerController
    let operation: ServerController.WorldOperation

    var body: some View {
        Card {
            HStack {
                if !operation.finished { ProgressView().controlSize(.small).accessibilityHidden(true) }
                if operation.finished {
                    Badge(text: operation.succeeded ? "Done" : "Check the output", tone: operation.succeeded ? .good : .warning)
                }
                HeadingText(operation.title).foregroundStyle(Theme.ink)
                Spacer()
                if operation.finished {
                    Button("Dismiss") { server.dismissWorldOperation() }.buttonStyle(.themed)
                }
            }
            Text(output)
                .type(.mono).foregroundStyle(Theme.ink).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Multiverse output")
        }
    }

    private var output: String {
        let lines = server.console.filter { $0.id >= operation.firstLineID }.suffix(8).map(\.text)
        return lines.isEmpty ? "Waiting for the server…" : lines.joined(separator: "\n")
    }
}

private struct WorldRow: View {
    let server: ServerController
    let world: WorldEntry
    let onImport: () -> Void
    let onEdit: () -> Void
    let onClone: () -> Void
    let onRemove: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void

    private var canAct: Bool { server.state == .running && server.multiverseMajor != nil && (server.worldOperation?.finished ?? true) }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(world.title).type(.dataHeading).foregroundStyle(Theme.ink).rowName(world.title)
                if world.title != world.name, world.multiverse?.alias.isEmpty == false { Text(world.name).type(.body).foregroundStyle(Theme.muted).rowName(world.name) }
                Spacer()
                badges
            }
            Hint(details)
            if !world.folderMissing {
                Button("Rename…", action: onRename).buttonStyle(.themed)
                    .disabled(server.activity != nil || server.trialPhase != nil)
            }
            if server.multiverseMajor != nil { actions }
        }
    }

    private var icon: String {
        switch environment {
        case .nether: "flame"
        case .theEnd: "moon.stars"
        case .normal: "globe.americas"
        }
    }

    private var environment: WorldEnvironment {
        if let env = world.multiverse?.environment?.lowercased() {
            return WorldEnvironment(rawValue: env) ?? .guess(from: env)
        }
        return .guess(from: world.name)
    }

    @ViewBuilder private var badges: some View {
        if world.isMain {
            Badge(text: "Main world", tone: .good, icon: "house.fill")
        } else if world.folderMissing {
            Badge(text: "Folder missing", tone: .warning)
        } else if !world.isManaged, server.multiverseMajor != nil {
            Badge(text: "Not in Multiverse", tone: .neutral)
        } else if world.multiverse?.autoLoad == false {
            Badge(text: "Doesn't load at startup", tone: .neutral, icon: "pause.circle")
        }
    }

    private var details: String {
        var parts = [environment.title]
        if !world.folderMissing { parts.append(Format.bytes(world.size)) }
        if let mode = world.multiverse?.gamemode { parts.append(mode.capitalized) }
        if let difficulty = world.multiverse?.difficulty { parts.append(difficulty.capitalized) }
        if world.multiverse?.hidden == true { parts.append("Hidden") }
        if let path = world.relativePath, path != world.name { parts.append(path) }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        FlowRow(spacing: 6) {
            if world.isManaged {
                Button("Settings…", action: onEdit).buttonStyle(.themed)
                if !world.isCore {
                    Button("Load") { server.attempt { try await server.loadWorld(world.name) } }.buttonStyle(.themed)
                    Button("Unload") { server.attempt { try await server.unloadWorld(world) } }.buttonStyle(.themed)
                }
                if !world.folderMissing { Button("Copy…", action: onClone).buttonStyle(.themed) }
                if !world.isCore {
                    Button("Remove from Multiverse…", action: onRemove).buttonStyle(.themed)
                    if !world.folderMissing { Button("Delete…", action: onDelete).buttonStyle(.themedDanger) }
                }
            } else if !world.folderMissing {
                Button("Import…", action: onImport).buttonStyle(.themed)
            }
        }
        .disabled(!canAct)
    }
}

// MARK: - Sheets

private struct SheetFrame<Content: View, Actions: View>: View {
    let title: String
    var error: String?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetTitle(title)
            content
            if let error { Callout(tone: .danger, title: error) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
                Spacer()
                actions
            }
        }
        .padding(20)
        .frame(width: Theme.sheet(480))
    }
}

private struct CreateWorldSheet: View {
    let server: ServerController
    @Environment(\.dismiss) private var dismiss
    @State private var world = NewWorld()

    private var nameValid: Bool { Multiverse.isValidName(world.name) }
    private var seedValid: Bool { Multiverse.isValidSeed(world.seed) }

    var body: some View {
        SheetFrame(title: "New World") {
            Form {
                TextField("Name", text: $world.name, prompt: Text("mining")).focusOnOpen()
                Picker("Type", selection: $world.environment) {
                    ForEach(WorldEnvironment.allCases) { Text($0.title).tag($0) }
                }
                Picker("Terrain", selection: $world.type) {
                    ForEach(WorldType.allCases) { Text($0.title).tag($0) }
                }
                TextField("Seed", text: $world.seed, prompt: Text("Random"))
                Toggle("Generate structures", isOn: $world.structures)
            }
            .formStyle(.columns)
            if !world.name.isEmpty, !nameValid { Callout(tone: .warning, title: "Names can use letters, numbers, - and _.") }
            if !seedValid { Callout(tone: .warning, title: "Seeds can use letters, numbers, - and _.") }
            Hint("Generating a new world can briefly slow the server for everyone online.")
        } actions: {
            Button("Create") {
                let spec = world
                dismiss()
                server.attempt { try await server.createWorld(spec) }
            }
            .buttonStyle(.themedPrimary).keyboardShortcut(.defaultAction).disabled(!nameValid || !seedValid)
        }
    }
}

private struct ImportWorldSheet: View {
    let server: ServerController
    let world: WorldEntry
    @Environment(\.dismiss) private var dismiss
    @State private var environment: WorldEnvironment = .normal

    var body: some View {
        SheetFrame(title: "Import \(world.name)") {
            Picker("Type", selection: $environment) {
                ForEach(WorldEnvironment.allCases) { Text($0.title).tag($0) }
            }
            Hint("Multiverse starts managing this world and loads it. Pick the type it was created as: choosing the wrong one can make it behave strangely.")
        } actions: {
            Button("Import") {
                let env = environment
                dismiss()
                server.attempt { try await server.importWorld(world.name, environment: env) }
            }
            .buttonStyle(.themedPrimary).keyboardShortcut(.defaultAction)
        }
        .onAppear { environment = .guess(from: world.name) }
    }
}

private struct EditWorldSheet: View {
    let server: ServerController
    let world: WorldEntry
    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""
    @State private var gamemode = ""
    @State private var difficulty = ""

    private static let gamemodes = ["SURVIVAL", "CREATIVE", "ADVENTURE", "SPECTATOR"]
    private static let difficulties = ["PEACEFUL", "EASY", "NORMAL", "HARD"]

    var body: some View {
        SheetFrame(title: "\(world.title) Settings") {
            Form {
                TextField("Display name", text: $alias).focusOnOpen()
                Picker("Game mode", selection: $gamemode) {
                    ForEach(options(Self.gamemodes, gamemode), id: \.self) { Text($0.capitalized).tag($0) }
                }
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(options(Self.difficulties, difficulty), id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            .formStyle(.columns)
            Hint("These apply straight away, without a restart. Multiverse has many more options: use /mv modify in the Console for those.")
        } actions: {
            Button("Save") { save() }.buttonStyle(.themedPrimary).keyboardShortcut(.defaultAction)
        }
        .onAppear {
            alias = world.multiverse?.alias ?? ""
            gamemode = world.multiverse?.gamemode?.uppercased() ?? "SURVIVAL"
            difficulty = world.multiverse?.difficulty?.uppercased() ?? "NORMAL"
        }
    }

    private func options(_ base: [String], _ current: String) -> [String] {
        base.contains(current) || current.isEmpty ? base : base + [current]
    }

    private func save() {
        let changes = [
            ("alias", alias, world.multiverse?.alias ?? ""),
            ("gamemode", gamemode, world.multiverse?.gamemode?.uppercased() ?? ""),
            ("difficulty", difficulty, world.multiverse?.difficulty?.uppercased() ?? ""),
        ].filter { $0.1 != $0.2 }
        dismiss()
        server.attempt {
            for (property, value, _) in changes {
                try await server.modifyWorld(world, property: property, value: value)
            }
        }
    }
}

private struct CloneWorldSheet: View {
    let server: ServerController
    let world: WorldEntry
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""

    var body: some View {
        SheetFrame(title: "Copy \(world.title)") {
            TextField("New world's name", text: $target).textFieldStyle(.growing).focusOnOpen()
            if !target.isEmpty, !Multiverse.isValidName(target) { Callout(tone: .warning, title: "Names can use letters, numbers, - and _.") }
            Hint("This world is \(Format.bytes(world.size)). The copy needs about that much free disk space.")
        } actions: {
            Button("Copy") {
                let name = target
                dismiss()
                server.attempt { try await server.cloneWorld(world, to: name) }
            }
            .buttonStyle(.themedPrimary).keyboardShortcut(.defaultAction).disabled(!Multiverse.isValidName(target))
        }
    }
}

/// Deleting a world is the one action here that can't be undone by Multiverse, so it asks for the name.
private struct DeleteWorldSheet: View {
    let server: ServerController
    let world: WorldEntry
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    var body: some View {
        SheetFrame(title: "Delete \(world.title)?") {
            Callout(tone: .danger, title: "This permanently deletes the world's folder", detail: "\(Format.bytes(world.size)) of data. Anyone in it is moved out first. GilaMonster takes a backup of your worlds before deleting, and stops if that backup fails.")
            TextField("Type \(world.title) to confirm", text: $typed).textFieldStyle(.growing)
        } actions: {
            Button("Back Up and Delete") {
                dismiss()
                server.attempt { try await server.deleteWorld(world) }
            }
            .buttonStyle(.themedDanger).disabled(typed != world.title)
        }
    }
}
