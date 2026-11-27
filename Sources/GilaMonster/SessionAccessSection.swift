import AppKit
import GilaMonsterCore
import SwiftUI

/// The owner's switch, list of commands, and record of every call for session access. See SessionAccess.swift.
struct SessionAccessSection: View {
    @State private var settings = SessionAccess.loadSettings()
    @State private var adding = ""
    @State private var problem: String?
    @State private var log: [SessionAccess.LogEntry] = []
    @State private var confirmNewToken = false
    @State private var clearing: ServerController?
    @State private var marks: [UUID: SessionPermission] = [:]
    @State private var markError: String?
    private let service = SessionAccessService.shared
    /// Proper names for the groups, such as WelcomeWagon, from the plugins installed on any server.
    private var pluginNames: [String] { service.servers().flatMap { $0.plugins.compactMap { $0.descriptor?.name } } }

    var body: some View {
        Section {
            Toggle("Let sessions on this Mac check status and run listed commands", isOn: Binding(get: { settings.enabled }, set: { on in
                settings.enabled = on
                save()
            }))
            if let error = service.error { Text(error).foregroundStyle(Theme.danger).type(.body) }
            if settings.enabled {
                Text(service.waitingForKeychain ? "Waiting for Keychain access. macOS may be asking you to allow GilaMonster. Until you answer, sessions are told to wait." : service.isListening ? "Listening on this Mac only." : "Not listening yet.").type(.body).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Commands sessions may run").type(.label(.semibold)).foregroundStyle(Theme.ink)
                Text("Exactly as written, or a pattern with typed slots: {world} is one of that server's worlds, {int} a whole number, {player} a player name. Nothing else can be added to a pattern. The list sorts itself.")
                    .type(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                if settings.commands.isEmpty { Text("None. Sessions can still read status and the log.").type(.body).foregroundStyle(Theme.muted) }
                ForEach(CommandPattern.grouped(settings.commands, plugins: pluginNames), id: \.name) { group in
                    Text(group.name).type(.label(.semibold)).foregroundStyle(Theme.muted).padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.entries, id: \.self) { command in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(command).type(.mono).foregroundStyle(Theme.ink).textSelection(.enabled)
                                if CommandPattern.isPattern(command) {
                                    Text("For example: \(CommandPattern.example(command))").type(.mono).foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                            Button("Remove") { settings.commands.removeAll { $0 == command }; save() }
                                .accessibilityLabel("Remove \(command) from the list")
                        }
                    }
                }
                HStack {
                    TextField("Add a command, such as save-all or rewild scan {world}", text: $adding).textFieldStyle(.roundedBorder)
                        .onSubmit(add).accessibilityLabel("Command to add")
                    Button("Add", action: add).disabled(adding.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem { Text(problem).foregroundStyle(Theme.danger).type(.body) }
            }
            if !service.waiting.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting for you").type(.label(.semibold)).foregroundStyle(Theme.ink)
                    SessionAskList(service: service)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Starting, stopping and pack changes").type(.label(.semibold)).foregroundStyle(Theme.ink)
                Text("Sessions can ask to start, stop or restart a server, publish a pack, change pack serving, or check a named player against the pack gate. Each ask opens a small GilaMonster window with Allow and Deny, shows a count on the menu bar leaf, and sends a notification when macOS allows one. No answer in 2 minutes means no, and nothing is done while a backup is being written.")
                    .type(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(service.servers().filter { !$0.isLab }, id: \.profile.id) { server in
                    let mark = marks[server.profile.id] ?? server.sessionPermission
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.displayName).type(.label(.semibold)).foregroundStyle(Theme.ink)
                        Toggle("Children may play here", isOn: Binding(get: { mark.childrenMayPlay }, set: { on in
                            if on { setMark(server, true) } else { clearing = server }
                        }))
                        Toggle("Let sessions do these without asking", isOn: Binding(get: { mark.standing && !mark.childrenMayPlay }, set: { on in
                            do { try server.setStandingPermission(on); markError = nil } catch { markError = error.localizedDescription }
                            reloadMarks()
                        }))
                        .disabled(because: mark.childrenMayPlay ? "Not while children may play here. Every change asks first." : nil)
                    }
                    .padding(.vertical, 2)
                }
                if let markError { Text(markError).foregroundStyle(Theme.danger).type(.body) }
            }
            Button("Make a New Token…") { confirmNewToken = true }
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent calls").type(.label(.semibold)).foregroundStyle(Theme.ink)
                if log.isEmpty { Text("None yet.").type(.body).foregroundStyle(Theme.muted) }
                ForEach(log.prefix(30)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: entry.allowed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(entry.allowed ? Theme.accent : Theme.danger).accessibilityHidden(true)
                        Text(describe(entry)).type(.body).foregroundStyle(Theme.ink).textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel((entry.allowed ? "Allowed: " : "Refused: ") + describe(entry))
                }
            }
        } header: {
            Text("Session access")
        } footer: {
            Text("For assistant sessions on this Mac, through gilamonster-session. They can read each server's status and its recent log, with chat, addresses and player names taken out, run only the commands listed here, add packs and build recipes, and ask for the changes above. Anything running as your macOS account could use it, so keep the list short. Every call is recorded here, allowed or not.")
                .type(.body).foregroundStyle(Theme.muted)
        }
        .onAppear { reload(); reloadMarks() }
        .onChange(of: service.calls) { reload() }
        .confirmationDialog("Clear \"Children may play here\" for \(clearing?.displayName ?? "this server")?", isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } })) {
            Button("Clear the Mark", role: .destructive) { if let s = clearing { setMark(s, false) }; clearing = nil }
        } message: {
            Text("Only clear it if no child ever plays here. Cleared, the server can be given standing permission, so sessions could start, stop or change its packs without asking. The change is written to the server's log.")
        }
        .confirmationDialog("Make a new token?", isPresented: $confirmNewToken) {
            Button("Make New Token") { Task { try? await service.newToken() } }
        } message: {
            Text("Anything holding the old token is refused from now on. Sessions read the new one from the Keychain, and macOS may ask you to allow that again.")
        }
    }

    private func describe(_ e: SessionAccess.LogEntry) -> String {
        var text = "\(e.at.formatted(date: .omitted, time: .shortened)) \(e.caller): \(e.call)"
        if let c = e.command { text += " \(c)" }
        if let s = e.server, !s.isEmpty { text += " on \(s)" }
        if !e.allowed || !e.note.isEmpty { text += ". \(e.note)" }
        return text
    }

    private func add() {
        if let why = SessionAccess.problem(adding: adding) { problem = why; return }
        let command = SessionAccess.normalize(adding)
        if !settings.commands.contains(command) { settings.commands.append(command) }
        adding = ""; problem = nil
        save()
    }

    private func save() {
        do { try SessionAccess.saveSettings(settings); problem = nil } catch { problem = error.localizedDescription }
        Task { await service.apply(settings) }
    }

    private func reload() { log = SessionAccess.recentLog(30) }

    private func reloadMarks() {
        marks = Dictionary(uniqueKeysWithValues: service.servers().filter { !$0.isLab }.map { ($0.profile.id, $0.sessionPermission) })
    }

    private func setMark(_ server: ServerController, _ on: Bool) {
        do { try server.setChildrenMayPlay(on); markError = nil } catch { markError = error.localizedDescription }
        reloadMarks()
    }
}
