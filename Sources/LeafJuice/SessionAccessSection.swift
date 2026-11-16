import AppKit
import LeafJuiceCore
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

    var body: some View {
        Section {
            Toggle("Let sessions on this Mac check status and run listed commands", isOn: Binding(get: { settings.enabled }, set: { on in
                settings.enabled = on
                save()
            }))
            if let error = service.error { Text(error).foregroundStyle(Juice.danger).font(.callout) }
            if settings.enabled {
                Text(service.isListening ? "Listening on this Mac only." : "Not listening yet.").font(.callout).foregroundStyle(Juice.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Commands sessions may run, exactly as written").font(.callout.weight(.semibold)).foregroundStyle(Juice.ink)
                if settings.commands.isEmpty { Text("None. Sessions can still read status and the log.").font(.callout).foregroundStyle(Juice.muted) }
                ForEach(settings.commands, id: \.self) { command in
                    HStack {
                        Text(command).font(.body.monospaced()).foregroundStyle(Juice.ink).textSelection(.enabled)
                        Spacer()
                        Button("Remove") { settings.commands.removeAll { $0 == command }; save() }
                            .accessibilityLabel("Remove \(command) from the list")
                    }
                }
                HStack {
                    TextField("Add a command, such as save-all", text: $adding).textFieldStyle(.roundedBorder)
                        .onSubmit(add).accessibilityLabel("Command to add")
                    Button("Add", action: add).disabled(adding.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem { Text(problem).foregroundStyle(Juice.danger).font(.callout) }
            }
            if !service.waiting.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting for you").font(.callout.weight(.semibold)).foregroundStyle(Juice.ink)
                    ForEach(service.waiting) { ask in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ask.sentence).foregroundStyle(Juice.ink)
                                Text("No answer by \(ask.deadline.formatted(date: .omitted, time: .shortened)) means no.").font(.caption).foregroundStyle(Juice.muted)
                            }
                            Spacer()
                            Button("Deny") { service.resolve(ask.id, allow: false) }.accessibilityLabel("Deny: \(ask.sentence)")
                            Button("Allow") { service.resolve(ask.id, allow: true) }.buttonStyle(.juicePrimary).accessibilityLabel("Allow: \(ask.sentence)")
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Starting, stopping and pack changes").font(.callout.weight(.semibold)).foregroundStyle(Juice.ink)
                Text("Sessions can ask to start, stop or restart a server, publish a pack, change pack serving, or check a named player against the pack gate. Each ask shows a notification with Allow and Deny. No answer in 2 minutes means no, and nothing is done while a backup is being written.")
                    .font(.caption).foregroundStyle(Juice.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(service.servers().filter { !$0.isLab }, id: \.profile.id) { server in
                    let mark = marks[server.profile.id] ?? server.sessionPermission
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.profile.name).font(.body.weight(.semibold)).foregroundStyle(Juice.ink)
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
                if let markError { Text(markError).foregroundStyle(Juice.danger).font(.callout) }
            }
            Button("Make a New Token…") { confirmNewToken = true }
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent calls").font(.callout.weight(.semibold)).foregroundStyle(Juice.ink)
                if log.isEmpty { Text("None yet.").font(.callout).foregroundStyle(Juice.muted) }
                ForEach(log.prefix(30)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: entry.allowed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(entry.allowed ? Juice.pulp : Juice.danger).accessibilityHidden(true)
                        Text(describe(entry)).font(.callout).foregroundStyle(Juice.ink).textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel((entry.allowed ? "Allowed: " : "Refused: ") + describe(entry))
                }
            }
        } header: {
            Text("Session access")
        } footer: {
            Text("For assistant sessions on this Mac, through leafjuice-session. They can read each server's status and its recent log, with chat, addresses and player names taken out, run only the commands listed here, add packs and build recipes, and ask for the changes above. Anything running as your macOS account could use it, so keep the list short. Every call is recorded here, allowed or not.")
                .font(.caption).foregroundStyle(Juice.muted)
        }
        .onAppear { reload(); reloadMarks() }
        .onChange(of: service.calls) { reload() }
        .confirmationDialog("Clear \"Children may play here\" for \(clearing?.profile.name ?? "this server")?", isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } })) {
            Button("Clear the Mark", role: .destructive) { if let s = clearing { setMark(s, false) }; clearing = nil }
        } message: {
            Text("Only clear it if no child ever plays here. Cleared, the server can be given standing permission, so sessions could start, stop or change its packs without asking. The change is written to the server's log.")
        }
        .confirmationDialog("Make a new token?", isPresented: $confirmNewToken) {
            Button("Make New Token") { _ = try? SessionAccess.newToken() }
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
        service.apply(settings)
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
