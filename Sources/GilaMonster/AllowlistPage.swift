import GilaMonsterCore
import SwiftUI

/// Add someone before they've joined, with their groups. Each server is its own list.
struct AllowlistPage: View {
    @Bindable var server: ServerController
    @State private var typed = ""
    @State private var looking = false
    @State private var outcome: AccountLookup.Outcome?
    @State private var chosen = Set<String>()
    @State private var settings = PlayerAccessSettings()
    @State private var waiting: [AccessChange] = []
    @State private var entries: [AllowlistEntry] = []
    @State private var message: String?
    @State private var working = false
    @State private var pendingWarnings: [String] = []
    @State private var showAllAttempts = false
    @State private var search = ""
    @State private var showAllEntries = false
    @State private var removing: AllowlistEntry?
    @State private var editing: AllowlistEntry?
    @State private var conflictA = ""
    @State private var conflictB = ""
    @State private var sheriff: SheriffStatus?
    @State private var attempts: [SheriffAttempt] = []
    @State private var sheriffEditing: AllowlistEntry?
    @State private var modules = Modules.shared

    private var running: Bool { server.state == .running }

    var body: some View {
        Page(title: "Allowlist", subtitle: "Who can join \(server.displayName). This only changes this server.") {
            if let blocked = server.playerAccessBlocked { Callout(tone: .warning, title: "Adding players is off here", detail: blocked) }
            if let message { Callout(tone: .danger, title: message) }
            if server.hasSheriff { sheriffNote }
            addCard
            if server.hasWelcomeWagon { InvitesCard(server: server, profiles: server.hasSheriff ? sheriffProfiles : nil) }
            if !waiting.isEmpty { waitingCard }
            if sheriffProfiles != nil, !attempts.isEmpty { attemptsCard }
            listCard
            if server.hasLuckPerms, !server.hasSheriff { groupsCard }
        }
        .task(id: "\(server.state)-\(modules.isOn(.pluginCommands))") { await readSheriff() }
        .task {
            await server.refreshPlugins()
            reload()
            await server.refreshGroups()
            reload()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                entries = server.allowlist
                waiting = server.waitingAccess
            }
        }
        .sheet(item: $sheriffEditing) { entry in
            SheriffProfileSheet(server: server, entry: entry, profiles: sheriffProfiles ?? []) { reload() }
        }
        .sheet(item: $editing) { entry in
            GroupEditor(server: server, entry: entry, settings: settings) { reload() }
        }
        .confirmationDialog("Take \(removing?.name ?? "") off the allowlist?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { remove() }
        } message: {
            Text("They can't join after this, and any page sign-in ends. Their groups stay, so adding them back restores what they had.")
        }
    }

    private var addCard: some View {
        Card(title: "Add a player", systemImage: "person.badge.plus") {
            Hint("Java accounts only. Capitals don't matter, but the name has to belong to a real account. Looking it up sends the name to Mojang.")
            HStack {
                Text("Username").foregroundStyle(Theme.ink).accessibilityHidden(true)
                TextField("Minecraft username", text: $typed, prompt: ThemedPrompt("Minecraft username")).labelsHidden().textFieldStyle(.themed).frame(maxWidth: 260)
                    .onChange(of: typed) { outcome = nil; pendingWarnings = [] }
                    .onSubmit(lookUp)
                Button(looking ? "Looking…" : "Look Up", action: lookUp).buttonStyle(.themed)
                    .disabled(looking || !AccountLookup.isValidName(typed.trimmingCharacters(in: .whitespaces)) || server.playerAccessBlocked != nil)
            }
            switch outcome {
            case let .found(account): found(account)
            case .noAccount: Callout(tone: .danger, title: "No Minecraft account has that name", detail: "Check the spelling. Nothing was added.")
            case .invalid: Callout(tone: .danger, title: "That can't be a Minecraft name", detail: "Names are 1 to 16 letters, numbers or underscores.")
            case let .unreachable(why): Callout(tone: .warning, title: "Couldn't check that name", detail: "Nothing was added. \(why)")
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder private func found(_ account: MojangAccount) -> some View {
        Fact(label: "Account", value: account.name)
        Fact(label: "ID", value: account.uuid)
        if server.hasSheriff {
            if let profiles = sheriffProfiles {
                SheriffApproval(server: server, uuid: account.uuid, name: account.name, profiles: profiles) { _ in
                    reload()
                    Task { await readAttempts() }
                }
            } else {
                Hint("Sheriff looks after who can join this server, so they can be approved once GilaMonster can reach it.")
            }
        } else {
            rawFound(account)
        }
    }

    @ViewBuilder private func rawFound(_ account: MojangAccount) -> some View {
        if server.hasLuckPerms {
            let offered = settings.knownGroups.filter(settings.grantable.contains)
            if offered.isEmpty {
                Hint("No groups can be chosen yet. Mark some below. Without one they get what the default group gives.")
            } else {
                Text("Groups").type(.label(.semibold)).foregroundStyle(Theme.ink)
                ForEach(offered, id: \.self) { group in
                    Toggle(group, isOn: Binding(get: { chosen.contains(group) }, set: { on in
                        if on { chosen.insert(group) } else { chosen.remove(group) }
                        pendingWarnings = []
                    }))
                    .toggleStyle(.checkbox)
                }
            }
        }
        ForEach(pendingWarnings, id: \.self) { Callout(tone: .warning, title: $0) }
        HStack {
            Button(working ? "Working…" : pendingWarnings.isEmpty ? "Add \(account.name)" : "Add Anyway") { add(account) }
                .buttonStyle(.themedPrimary).disabled(working)
            Hint(running ? "Happens now, with the groups first." : "The server isn't running, so this waits until it is. They can't join until then.")
        }
    }

    private var waitingCard: some View {
        Card(title: "Not finished", systemImage: "clock") {
            ForEach(waiting) { change in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(change.name).type(.label(.semibold)).foregroundStyle(Theme.ink).rowName(change.name)
                        Hint(change.summary)
                        Spacer()
                        if change.problem != nil {
                            Button("Try Again") { Task { await server.retryAccess(change.id); reload() } }.buttonStyle(.themed).disabled(!running)
                        }
                        Button("Cancel") { server.cancelAccess(change.id); reload() }.buttonStyle(.themed)
                    }
                    if let problem = change.problem {
                        Callout(tone: .danger, title: problem)
                    } else {
                        Hint("Waiting for the server to be running.")
                    }
                }
            }
            Hint("Anything already done stays done, and doing it again is safe.")
        }
    }

    private var listCard: some View {
        let searching = Overflow.showsAllowlistSearch(entries: entries.count)
        let matches = searching ? Overflow.matching(entries, search) { $0.name } : entries
        let cut = Overflow.slice(matches, limit: Overflow.Limit.allowlistShown, expanded: showAllEntries)
        return Card(title: "On the allowlist (\(entries.count))", systemImage: "list.bullet") {
            if entries.isEmpty { Hint("Nobody yet.") }
            if searching {
                TextField("Search names", text: $search, prompt: ThemedPrompt("Search names")).textFieldStyle(.themed).frame(maxWidth: 260)
                    .accessibilityLabel("Search names on the allowlist")
                if matches.isEmpty { Hint("No name matches \u{201C}\(search)\u{201D}.") }
                else if !search.isEmpty { Hint("\(matches.count) of \(entries.count) match.") }
            }
            ForEach(cut.shown) { entry in
                HStack {
                    Text(entry.name).foregroundStyle(Theme.ink).textSelection(.enabled).rowName(entry.name)
                    Spacer()
                    if server.hasSheriff {
                        Button("Profiles…") { sheriffEditing = entry }.buttonStyle(.themed).disabled(sheriffProfiles == nil)
                            .accessibilityLabel("Profiles for \(entry.name)")
                    } else if server.hasLuckPerms {
                        Button("Groups…") { editing = entry }.buttonStyle(.themed).disabled(!running || server.playerAccessBlocked != nil)
                            .accessibilityLabel("Groups for \(entry.name)")
                    }
                    Button("Remove…") { removing = entry }.buttonStyle(.themed).disabled(server.state.isLive && !running)
                        .accessibilityLabel("Remove \(entry.name)")
                }
            }
            if cut.hidden > 0 || showAllEntries {
                Button(showAllEntries ? "Show Fewer" : "Show All (\(matches.count))") { showAllEntries.toggle() }
                    .buttonStyle(.disclosureLink(showAllEntries ? "chevron.up" : "chevron.down")).type(.body)
            }
            if server.hasSheriff, sheriffProfiles == nil { Hint("Profiles can be changed once GilaMonster can reach Sheriff.") }
            else if server.hasLuckPerms, !server.hasSheriff, !running { Hint("Groups can only be changed while the server runs.") }
        }
    }

    private var groupsCard: some View {
        Card(title: "Groups", systemImage: "person.3") {
            Hint("Tick the groups this screen may hand out. A new group stays off until you tick it, so leave staff and admin groups off.")
            if settings.knownGroups.isEmpty {
                Hint(running ? "Reading groups from the server…" : "Start the server once to read its groups.")
            }
            ForEach(settings.knownGroups, id: \.self) { group in
                Toggle(group, isOn: Binding(get: { settings.grantable.contains(group) }, set: { on in
                    if on { settings.grantable.insert(group) } else { settings.grantable.remove(group) }
                    save()
                }))
                .toggleStyle(.checkbox)
            }
            if settings.knownGroups.count >= 2 {
                Text("Don't combine").type(.label(.semibold)).foregroundStyle(Theme.ink)
                Hint("Choosing both groups in a pair warns you before saving. It doesn't stop you.")
                ForEach(settings.conflicts, id: \.self) { pair in
                    HStack {
                        Text(pair.joined(separator: " and ")).foregroundStyle(Theme.ink)
                        Spacer()
                        Button("Remove") {
                            settings.conflicts.removeAll { $0 == pair }
                            save()
                        }
                        .buttonStyle(.themed)
                        .accessibilityLabel("Remove the pair \(pair.joined(separator: " and "))")
                        .accessibilityLabel("Remove the pair \(pair.joined(separator: " and "))")
                    }
                }
                HStack {
                    Picker("First group", selection: $conflictA) {
                        Text("Choose…").tag("")
                        ForEach(settings.knownGroups, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Second group", selection: $conflictB) {
                        Text("Choose…").tag("")
                        ForEach(settings.knownGroups, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Add Pair") {
                        let pair = [conflictA, conflictB].sorted()
                        if !settings.conflicts.contains(pair) { settings.conflicts.append(pair) }
                        conflictA = ""; conflictB = ""
                        save()
                    }
                    .buttonStyle(.themed).disabled(conflictA.isEmpty || conflictB.isEmpty || conflictA == conflictB)
                }
            }
        }
    }

    private var sheriffProfiles: [SheriffProfile]? {
        if case .ready(_, let profiles, _, _) = sheriff { profiles } else { nil }
    }

    @ViewBuilder private var sheriffNote: some View {
        switch sheriff {
        case .unavailable(let why)?:
            Callout(tone: .warning, title: "Sheriff can't be reached", detail: why + " GilaMonster won't add anyone or change groups around it.") {
                if !modules.isOn(.pluginCommands) {
                    Button("Turn On Plugin Commands") { modules.set(.pluginCommands, on: true) }.buttonStyle(.themed)
                }
            }
        case .ready(let version, _, let luckPerms, let problems)?:
            Callout(tone: .info, title: "Approvals go through Sheriff \(version)", detail: "Profiles, questions and the change log are Sheriff's. This works only while GilaMonster runs this server, because it types Sheriff's commands into the console.") {
                EmptyView()
            }
            if !luckPerms { Callout(tone: .warning, title: "LuckPerms isn't running", detail: "Sheriff refuses every change without it, saying why.") }
            ProblemList(tone: .warning, what: "Sheriff's settings", problems: problems)
        default:
            Hint("Checking Sheriff…")
        }
    }

    private var attemptsCard: some View {
        let cut = Overflow.slice(attempts, limit: Overflow.Limit.turnedAway, expanded: showAllAttempts)
        return Card(title: "Turned away recently (\(attempts.count))", systemImage: "hand.raised",
                    subtitle: "People the allowlist stopped, newest first. Approving still looks the name up first.") {
            ForEach(cut.shown) { attempt in
                HStack {
                    Text(attempt.name).foregroundStyle(Theme.ink).textSelection(.enabled).lineLimit(1).truncationMode(.middle).help(attempt.name)
                    Hint(attempt.count == 1 ? "once" : "\(attempt.count) times")
                    Spacer()
                    Button("Approve…") { typed = attempt.name; lookUp() }.buttonStyle(.themed)
                        .accessibilityLabel("Approve \(attempt.name)")
                }
            }
            ShowMoreButton(hidden: cut.hidden, expanded: $showAllAttempts)
        }
    }

    private func readSheriff() async {
        await server.refreshPlugins()
        guard server.hasSheriff else { sheriff = .notInstalled; return }
        sheriff = nil
        sheriff = await server.sheriffStatus()
        await readAttempts()
    }

    private func readAttempts() async {
        guard sheriffProfiles != nil, case .success(let list) = await server.sheriffAttempts() else { attempts = []; return }
        attempts = list
    }

    private func reload() {
        settings = server.playerAccessSettings
        waiting = server.waitingAccess
        entries = server.allowlist
    }

    private func save() { server.playerAccessSettings = settings }

    private func lookUp() {
        guard server.playerAccessBlocked == nil, !looking else { return }
        looking = true
        message = nil
        chosen = []
        Task {
            outcome = await AccountLookup.lookUp(typed)
            looking = false
        }
    }

    private func add(_ account: MojangAccount) {
        working = true
        message = nil
        Task {
            defer { working = false }
            // Warned once. Pressing again means they've read it.
            if pendingWarnings.isEmpty {
                let existing = await server.currentGroups(uuid: account.uuid) ?? []
                let warnings = settings.warnings(adding: chosen, alreadyHas: existing)
                if !warnings.isEmpty {
                    pendingWarnings = warnings
                    return
                }
            }
            message = await server.requestAccess(AccessChange(uuid: account.uuid, name: account.name, addGroups: chosen.sorted()))
            if message == nil {
                typed = ""
                outcome = nil
                chosen = []
                pendingWarnings = []
            }
            reload()
        }
    }

    private func remove() {
        guard let entry = removing else { return }
        removing = nil
        Task {
            message = await server.removeFromAllowlist(entry)
            reload()
        }
    }
}

private struct GroupEditor: View {
    let server: ServerController
    let entry: AllowlistEntry
    let settings: PlayerAccessSettings
    let changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var current: Set<String>?
    @State private var chosen = Set<String>()
    @State private var signIn = SignInAccess.unknown
    @State private var warnings: [String] = []
    @State private var problem: String?
    @State private var working = false

    private var offered: [String] { settings.knownGroups.filter(settings.grantable.contains) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetTitle("Groups for \(entry.name)")
            if let current {
                ForEach(offered, id: \.self) { group in
                    Toggle(group, isOn: Binding(get: { chosen.contains(group) }, set: { on in
                        if on { chosen.insert(group) } else { chosen.remove(group) }
                        warnings = []
                    }))
                    .toggleStyle(.checkbox)
                }
                let others = current.subtracting(offered).sorted()
                if !others.isEmpty { Hint("Also has \(others.joined(separator: ", ")), which this screen doesn't change.") }
                if offered.isEmpty { Hint("No groups are marked as ones this screen can change.") }
            } else {
                Hint("Reading from the server…")
            }
            Fact(label: "Can sign in to the plugin page", value: signInText)
            ForEach(warnings, id: \.self) { Callout(tone: .warning, title: $0) }
            if let problem { Callout(tone: .danger, title: problem) }
            if server.hasWelcomeWagon { Divider(); WebSignInSection(server: server, name: entry.name) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.themed).keyboardShortcut(.cancelAction)
                Button(warnings.isEmpty ? "Save" : "Save Anyway", action: save).buttonStyle(.themedPrimary).disabled(current == nil || working)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            current = await server.currentGroups(uuid: entry.uuid)
            if let current { chosen = current.intersection(offered) } else { problem = "LuckPerms didn't answer." }
            signIn = await server.signInAccess(uuid: entry.uuid)
        }
    }

    private var signInText: String {
        switch signIn {
        case .yes: "Yes"
        case .no: "No"
        case .noGroupGivesIt: "No group gives it. Operators still can."
        case .unknown: "Unknown"
        }
    }

    private func save() {
        guard let current else { return }
        let before = current.intersection(offered)
        let adding = chosen.subtracting(before), removing = before.subtracting(chosen)
        if warnings.isEmpty {
            warnings = settings.warnings(adding: adding, alreadyHas: current.subtracting(removing))
            if !warnings.isEmpty { return }
        }
        working = true
        Task {
            defer { working = false }
            problem = await server.requestAccess(AccessChange(uuid: entry.uuid, name: entry.name, addGroups: adding.sorted(), removeGroups: removing.sorted(), addToAllowlist: false))
            changed()
            if problem == nil { dismiss() }
        }
    }
}
