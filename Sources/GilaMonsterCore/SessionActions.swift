import Foundation

// Session actions (D217, D220; 2026-11-16): what gilamonster-session can do beyond status, log and listed commands.
//
// Three kinds. Reads and builds go ahead without asking: they change nothing players see. Everything else (start,
// stop, restart, publishing a pack, changing hosting, telling Packmule, and asking about a named player) waits for
// the owner to press Allow, on a Mac notification or in Settings. No answer in time means no. Nothing that waits
// for Allow runs while a backup is being written.
//
// The owner can give a server standing permission, so its asks go ahead without a prompt. A server marked
// "Children may play here" can never have it. The mark is on unless the owner cleared it in the app, and a mark
// file that can't be read counts as on. gilamonster-session has no call that changes either.

public enum SessionAction: String, CaseIterable, Sendable {
    case backupStatus = "backup-status"
    case hostingStatus = "hosting-status"
    case gateCheck = "gate-check"
    case packAdd = "pack-add"
    case recipeSet = "recipe-set"
    case recipeBuild = "recipe-build"
    case start, stop, restart, publish, handoff
    case hostingStart = "hosting-start"
    case hostingStop = "hosting-stop"
    case hostingAdd = "hosting-add"
    case hostingRemove = "hosting-remove"

    public enum Kind: Sendable { case read, build, ask }

    public var kind: Kind {
        switch self {
        case .backupStatus, .hostingStatus, .gateCheck: .read
        case .packAdd, .recipeSet, .recipeBuild: .build
        case .start, .stop, .restart, .publish, .handoff, .hostingStart, .hostingStop, .hostingAdd, .hostingRemove: .ask
        }
    }

    /// The library and recipes belong to GilaMonster, not one server.
    public var needsServer: Bool { ![.packAdd, .recipeSet, .recipeBuild].contains(self) }

    /// For the Allow prompt: "wants to <verb> <server>".
    public func verb(recipe: String?) -> String {
        let r = recipe.map { " \($0)" } ?? ""
        switch self {
        case .start: return "start"
        case .stop: return "stop"
        case .restart: return "restart"
        case .publish: return "publish the newest\(r) build for"
        case .handoff: return "mark Packmule updated with\(r) on"
        case .hostingStart: return "start serving packs for"
        case .hostingStop: return "stop serving packs for"
        case .hostingAdd: return "give\(r) a pack address on"
        case .hostingRemove: return "remove\(r)'s pack address from"
        case .gateCheck: return "check whether a named player would get a pack from"
        default: return rawValue
        }
    }
}

/// One server's session permission, kept in its GilaMonster folder.
public struct SessionPermission: Codable, Equatable, Sendable {
    /// On unless the owner cleared it in the app.
    public var childrenMayPlay = true
    /// Asks go ahead without a prompt. Ignored while children may play.
    public var standing = false
    public init(childrenMayPlay: Bool = true, standing: Bool = false) { self.childrenMayPlay = childrenMayPlay; self.standing = standing }

    enum CodingKeys: String, CodingKey { case childrenMayPlay, standing }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        childrenMayPlay = try c.decodeIfPresent(Bool.self, forKey: .childrenMayPlay) ?? true
        standing = try c.decodeIfPresent(Bool.self, forKey: .standing) ?? false
    }

    /// Whether an ask may skip the prompt. Both have to be plainly set.
    public var skipsPrompt: Bool { !childrenMayPlay && standing }

    public static func file(meta: URL) -> URL { meta.appendingPathComponent("session-permission.json") }

    /// Missing or unreadable is the safe default: children may play, no standing permission.
    public static func load(meta: URL) -> SessionPermission {
        guard let data = try? Data(contentsOf: file(meta: meta)) else { return SessionPermission() }
        return (try? JSONDecoder().decode(SessionPermission.self, from: data)) ?? SessionPermission()
    }

    public static func save(_ p: SessionPermission, meta: URL) throws {
        guard p.standing == false || p.childrenMayPlay == false else {
            throw AppError("A server where children may play can't have standing permission.")
        }
        try JSONStore.save(p, to: file(meta: meta))
    }
}

extension ServerController {
    public var sessionPermission: SessionPermission { SessionPermission.load(meta: paths.meta) }

    /// For the app only, after the owner confirms. Marking a server also takes away its standing permission.
    public func setChildrenMayPlay(_ on: Bool) throws {
        var p = sessionPermission
        guard p.childrenMayPlay != on else { return }
        p.childrenMayPlay = on
        if on { p.standing = false }
        try SessionPermission.save(p, meta: paths.meta)
        let line = on ? "Marked: children may play here. Sessions must ask for every change." : "Cleared the mark saying children may play here."
        appendWrapper(line, level: .info)
        recordEvent(.config, on ? "Children may play here" : "Children mark cleared")
    }

    /// For the app only. Refused while children may play.
    public func setStandingPermission(_ on: Bool) throws {
        var p = sessionPermission
        if on && p.childrenMayPlay { throw AppError("A server where children may play can't have standing permission.") }
        guard p.standing != on else { return }
        p.standing = on
        try SessionPermission.save(p, meta: paths.meta)
        appendWrapper(on ? "Sessions may now start, stop and change packs here without asking." : "Sessions must ask again for every change here.", level: .info)
        recordEvent(.config, on ? "Standing permission given" : "Standing permission taken away")
    }

    /// Removes a recipe's address from this server. The old address stops working straight away.
    public func removeHostedRecipe(_ name: String) throws {
        var settings = packHostSettings
        guard settings.recipes.removeValue(forKey: ResourcePacks.slug(name)) != nil else { throw AppError("\(name) has no pack address here.") }
        packHostSettings = settings
    }
}

/// One request waiting for the owner.
public struct SessionApproval: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let caller: String
    public let action: SessionAction
    public let server: String
    public let recipe: String?
    public let asked: Date
    public var deadline: Date
    /// How many times the owner asked for more time (SessionAccessService.extend).
    public var extensions = 0

    /// "Head of Games wants to stop Made-up Server". The caller's name is their own claim.
    public var sentence: String { "\(caller) wants to \(action.verb(recipe: recipe)) \(server)" }

    /// Whether the prompt offers Allow for today.
    public var canAllowForToday: Bool { action.todayFamily != nil }
}

extension PackGate {
    /// For a session's gate check: the decision for one named player, without downloading anything. The player is
    /// found in the whitelist by name; a name that isn't there is a no.
    public static func wouldAdmit(name: String, root: URL, now: Date = Date()) -> Bool {
        guard let whitelist = tail(root.appendingPathComponent("whitelist.json"), bytes: 4 << 20),
              let rows = try? JSONSerialization.jsonObject(with: whitelist) as? [[String: Any]],
              let row = rows.first(where: { ($0["name"] as? String)?.lowercased() == name.lowercased() }),
              let uuid = (row["uuid"] as? String)?.lowercased(), let exact = row["name"] as? String else { return false }
        return admits(Player(name: exact, uuid: uuid), whitelist: whitelist,
                      log: tail(root.appendingPathComponent("logs/latest.log"), bytes: logTail).map { String(decoding: $0, as: UTF8.self) },
                      now: now)
    }
}

// MARK: - Asking the owner, and doing it

extension SessionAccessService {
    public enum Answer: Sendable { case allowed, denied, noAnswer }

    /// The owner's Allow or Deny, from the notification or Settings. An id that's already answered is ignored.
    public func resolve(_ id: UUID, allow: Bool) { finish(id, allow ? .allowed : .denied) }

    /// The owner's Allow for today, from the ask window, Settings or the notification. It allows this request and adds
    /// a grant for its kind of action on every server until local midnight. Only a request that's waiting, and whose
    /// action can be covered, adds one; anything else does nothing.
    public func resolveForToday(_ id: UUID) {
        guard let ask = waiting.first(where: { $0.id == id }), let family = ask.action.todayFamily else { return }
        _ = today.add(family, now: now(), calendar: calendar)
        lastToday.insert(id)
        finish(id, .allowed)
    }

    /// Most times one ask can be given more time, so an ask can't be kept open for ever.
    public static let maxExtensions = 3

    /// The owner pressed "Need More Time": the ask waits `approvalExtension` seconds longer, up to `maxExtensions`
    /// times. Nothing is allowed by this, and the default is still no when time runs out. Returns whether it extended.
    @discardableResult
    public func extend(_ id: UUID) -> Bool {
        guard answers[id] != nil, let i = waiting.firstIndex(where: { $0.id == id }), waiting[i].extensions < Self.maxExtensions else { return false }
        waiting[i].extensions += 1
        waiting[i].deadline = waiting[i].deadline.addingTimeInterval(approvalExtension)
        extraWait[id, default: 0] += approvalExtension
        return true
    }

    /// The menu bar's revoke: every grant ends now.
    public func revokeToday() { today.revokeAll() }

    func finish(_ id: UUID, _ answer: Answer) {
        guard let c = answers.removeValue(forKey: id) else { return }
        extraWait[id] = nil
        if let ask = waiting.first(where: { $0.id == id }) { onOutcome?(ask, answer) }
        waiting.removeAll { $0.id == id }
        onAnswered?(id)
        c.resume(returning: answer == .allowed)
        lastAnswer[id] = answer
    }

    /// Waits for the owner. With nobody to ask, the answer is no.
    func askOwner(_ approval: SessionApproval) async -> Answer {
        guard let onAsk else { return .noAnswer }
        let wait = approvalWait
        let allowed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            answers[approval.id] = c
            waiting.append(approval)
            onAsk(approval)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                // "Need more time" adds to extraWait while this sleeps; each addition is waited out before the no.
                while let self, self.answers[approval.id] != nil, let more = self.extraWait.removeValue(forKey: approval.id), more > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(more * 1_000_000_000))
                }
                self?.finish(approval.id, .noAnswer)
            }
        }
        let answer = lastAnswer.removeValue(forKey: approval.id) ?? (allowed ? .allowed : .denied)
        return answer
    }

    func act(_ action: SessionAction, request: SessionAccess.Request, server: ServerController?, log: URL) async -> Data {
        // The caller's name is shown in prompts, notices, the menu and the server's log, so control and format
        // characters (line breaks, bidi overrides) are taken out.
        let caller = String(String(String.UnicodeScalarView((request.caller ?? "?").unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
        })).prefix(64))
        var note: String?
        func refuse(_ why: String) -> Data {
            SessionAccess.record(request, outcome: .failure(.server(why)), server: server?.profile.name, to: log)
            return Self.reply(["ok": false, "error": why])
        }
        func done(_ body: [String: Any]) -> Data {
            SessionAccess.record(request, outcome: .success(.act(action)), server: server?.profile.name, note: note, to: log)
            var out = body
            out["ok"] = true
            if let server { out["server"] = server.profile.name }
            return Self.reply(out)
        }

        // Everything a request names is checked before the owner is bothered.
        let recipe = request.recipe?.trimmingCharacters(in: .whitespaces) ?? ""
        if recipe.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) {
            return refuse("A recipe name can't contain line breaks or control characters.")
        }
        let recipeKey = ResourcePacks.slug(recipe)
        let needsRecipe: Set<SessionAction> = [.publish, .handoff, .hostingAdd, .hostingRemove, .recipeSet, .recipeBuild]
        if needsRecipe.contains(action) {
            guard !recipe.isEmpty, recipe.count <= 64, !recipeKey.isEmpty else { return refuse("Name a recipe.") }
            if action != .recipeSet, action != .hostingRemove, !ResourcePacks.recipeNames().contains(recipeKey) {
                return refuse("There's no recipe called \"\(recipe.prefix(64))\". Recipes: \(ResourcePacks.recipeNames().joined(separator: ", ")).")
            }
        }
        let player = request.player?.trimmingCharacters(in: .whitespaces) ?? ""
        if !player.isEmpty, player.range(of: "^[A-Za-z0-9_]{3,16}$", options: .regularExpression) == nil {
            return refuse("That isn't a Minecraft player name.")
        }
        if let server {
            // A long job on this server (a backup, applying changes, a start already under way) makes Start do
            // nothing and could be cut short by a stop, so these are refused with the reason, before anyone is asked.
            if [.start, .stop, .restart].contains(action), let busy = server.busyWith {
                return refuse("\(busy) is in progress on \(server.profile.name), so nothing was changed. Try again when it's done.")
            }
            switch action {
            case .start where !server.state.canStart: return refuse("\(server.profile.name) is \(server.state.title.lowercased()), so it can't be started.")
            case .stop where server.state != .running, .restart where server.state != .running:
                return refuse("\(server.profile.name) isn't running under GilaMonster (it's \(server.state.title.lowercased())).")
            case .publish where ResourcePacks.history(recipe).isEmpty: return refuse("\(recipe) has no build yet. Build it first.")
            case .hostingRemove where server.packHostSettings.recipes[recipeKey] == nil: return refuse("\(recipe) has no pack address here.")
            default: break
            }
        }

        // Anything players would notice, and naming a player, waits for the owner.
        // A named player is asked about only while the gate is deciding: stopped or open, the answer is the same for all.
        let gateDecides = server.map { $0.packHostIsListening && $0.packHostSettings.joiningOnly } ?? false
        let asks = action.kind == .ask || (action == .gateCheck && !player.isEmpty && gateDecides)
        if asks, let server {
            if Backups.writing { return refuse("A backup is being written, so nothing was changed. Try again when it's done.") }
            let family = action.todayFamily
            var coveredToday = false
            if server.sessionPermission.skipsPrompt {
                note = "Standing permission"
            } else if let family, today.covers(family, now: now()) {
                // Allowed for today: still only with nobody on this server, and never when that can't be told.
                let who: Online
                if let online { who = await online(server) } else { who = await server.whoIsOnline() }
                switch who {
                case .nobody where !today.covers(family, now: now()):
                    break   // revoked, or midnight passed, while checking: ask as usual
                case .nobody:
                    coveredToday = true
                    note = "Allowed for today by the owner; nobody online"
                case .someone:
                    break
                case let .unsure(why):
                    return refuse("This is allowed for today, but GilaMonster couldn't tell whether anyone is on \(server.profile.name) (\(why)), so nothing was done.")
                }
            }
            if note == nil {
                let now = Date()
                let approval = SessionApproval(id: UUID(), caller: caller, action: action, server: server.profile.name,
                                               recipe: recipe.isEmpty ? nil : recipe, asked: now, deadline: now.addingTimeInterval(approvalWait))
                switch await askOwner(approval) {
                case .allowed where lastToday.remove(approval.id) != nil:
                    note = "Allowed for today by the owner, until midnight"
                case .allowed: note = "Allowed by the owner"
                case .denied: return refuse("The owner said no.")
                case .noAnswer:
                    return refuse(onAsk == nil ? "GilaMonster couldn't ask the owner, so nothing was done."
                                               : "The owner didn't answer within \(Int(approvalWait)) seconds, so nothing was done.")
                }
            }
            if Backups.writing { return refuse("A backup started while waiting, so nothing was changed.") }
            if [.start, .stop, .restart].contains(action), let busy = server.busyWith {
                return refuse("\(busy) started on \(server.profile.name) while waiting, so nothing was changed.")
            }
            switch action {
            case .start where !server.canStartNow, .stop where server.state != .running, .restart where server.state != .running:
                return refuse("\(server.profile.name) became \(server.state.title.lowercased()) while waiting, so nothing was changed.")
            default: break
            }
            if coveredToday, let family {
                wentAhead.insert((now(), "\(caller): \(action.verb(recipe: recipe.isEmpty ? nil : recipe)) \(server.profile.name)"), at: 0)
                if wentAhead.count > 20 { wentAhead.removeLast(wentAhead.count - 20) }
                server.appendWrapper("Allowed for today: \(caller) asked to \(action.verb(recipe: recipe.isEmpty ? nil : recipe)) this server, and nobody was online.", level: .info)
                onAutoAllowed?("\(caller) \(action.verb(recipe: recipe.isEmpty ? nil : recipe)) \(server.profile.name) without asking. You allowed \(family.words) for today.")
            }
        }

        do {
            switch action {
            case .backupStatus:
                let server = server!
                let running = Backups.running().filter { $0.server == server.profile.name }
                var out: [String: Any] = ["writing": !running.isEmpty, "automatic": server.profile.backup.enabled]
                if let last = server.profile.backup.lastRun { out["lastBackup"] = ISO8601DateFormatter().string(from: last) }
                out["running"] = running.map { b -> [String: Any] in
                    var row: [String: Any] = ["started": ISO8601DateFormatter().string(from: b.started), "writtenBytes": b.written]
                    if let f = b.fraction { row["fraction"] = (f * 100).rounded() / 100 }
                    return row
                }
                return done(out)

            case .hostingStatus:
                let server = server!
                let s = server.packHostSettings
                let recipes = s.recipes.keys.sorted().map { key -> [String: Any] in
                    var row: [String: Any] = ["recipe": key]
                    if let elsewhere = s.recipes[key]?.elsewhere { row["elsewhere"] = elsewhere }
                    if let address = server.packAddress(recipe: key) { row["address"] = address }
                    if let served = server.servedPackSHA1(recipe: key) { row["served"] = served }
                    return row
                }
                var out: [String: Any] = ["listening": server.packHostIsListening, "address": s.address, "port": s.port,
                                          "joiningOnly": s.joiningOnly, "packCheckToken": server.packCheckTokenPath != nil, "recipes": recipes]
                if let e = server.packHostError { out["error"] = e }
                return done(out)

            case .gateCheck:
                let server = server!
                let s = server.packHostSettings
                let text = request.url?.trimmingCharacters(in: .whitespaces) ?? ""
                guard PackHosting.isFullAddress(text) else { return refuse("Give the pack's full address.") }
                guard !s.address.isEmpty, text.lowercased().hasPrefix(s.address + "/") else {
                    return done(["matches": false, "decision": "That address isn't served by \(server.profile.name), so this check can't say."])
                }
                let path = String(text.dropFirst(s.address.count))
                let routes = s.recipes.compactMap { key, hosted in
                    hosted.elsewhere == nil ? PackRoute(token: hosted.token, recipe: key, url: nil, published: hosted.published, followsProperties: false) : nil
                }
                guard let (route, _) = PackHosting.match(path: path, routes: routes) else {
                    return done(["matches": false, "decision": "Nothing is served at that address. Everyone gets 404."])
                }
                var out: [String: Any] = ["matches": true, "recipe": route.recipe, "listening": server.packHostIsListening, "joiningOnly": s.joiningOnly]
                if !server.packHostIsListening {
                    out["decision"] = "Pack serving is stopped, so nobody gets it."
                } else if !s.joiningOnly {
                    out["decision"] = "Anyone with the address gets it."
                } else if player.isEmpty || !asks {
                    out["decision"] = "Only a player on the allowlist, joining now or online, gets it. Packmule's link check gets it with the pack-check token. Everyone else gets 404."
                } else {
                    let yes = PackGate.wouldAdmit(name: player, root: server.paths.root)
                    out["player"] = player
                    out["wouldGet"] = yes
                    out["decision"] = yes ? "\(player) would get it now." : "\(player) would get 404 now."
                }
                return done(out)

            case .packAdd:
                let path = request.path ?? ""
                guard path.hasPrefix("/"), path.lowercased().hasSuffix(".zip") else { return refuse("Give the full path of a .zip file.") }
                var info = stat()
                guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return refuse("That isn't a plain file (a link or folder won't do).") }
                guard info.st_size <= 1 << 30 else { return refuse("That pack is over 1 GB.") }
                let pack = try await ResourcePacks.add(URL(fileURLWithPath: path))
                return done(["pack": pack.id, "title": pack.title, "version": pack.latest?.sha1 ?? ""])

            case .recipeSet:
                let ids = (request.packs ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !ids.isEmpty, ids.count <= 50, Set(ids).count == ids.count else { return refuse("List the packs, highest priority first, each once.") }
                let library = ResourcePacks.list()
                var entries: [PackRecipe.Entry] = []
                for id in ids {
                    guard let pack = library.first(where: { $0.id == id }), let latest = pack.latest else {
                        return refuse("There's no pack \"\(id.prefix(64))\" in the library.")
                    }
                    entries.append(PackRecipe.Entry(pack: pack.id, version: latest.sha1))
                }
                var r = ResourcePacks.loadRecipe(recipeKey)
                r.entries = entries
                ResourcePacks.saveRecipe(r)
                return done(["recipe": recipeKey, "packs": ids])

            case .recipeBuild:
                let build = try await ResourcePacks.combine(ResourcePacks.loadRecipe(recipeKey))
                return done(["recipe": recipeKey, "sha1": build.sha1, "bytes": build.size, "warnings": build.warnings])

            case .start:
                let server = server!
                server.appendWrapper("A session (\(caller)) started the server.", level: .info)
                await server.start()
                var out: [String: Any] = ["state": server.state.title]
                if !server.blockers.isEmpty { out["blockers"] = server.blockers.map(\.title) }
                return done(out)

            case .stop:
                let server = server!
                server.appendWrapper("A session (\(caller)) stopped the server.", level: .info)
                server.stop()
                return done(["state": server.state.title])

            case .restart:
                let server = server!
                server.restart(reason: "Restart asked for by a session (\(caller))")
                return done(["state": server.state.title])

            case .publish:
                let server = server!
                guard let newest = ResourcePacks.history(recipeKey).first else { return refuse("\(recipe) has no build yet.") }
                let made = try server.publishPack(recipe: recipeKey, sha1: newest.sha1)
                return done(["recipe": recipeKey, "sha1": made.sha1, "url": made.url])

            case .handoff:
                let server = server!
                if request.byHand == true {
                    server.markHandedOff(recipe: recipeKey)
                    return done(["recipe": recipeKey, "handedOff": true])
                }
                switch await server.tellPackmule(recipe: recipeKey) {
                case let .done(text): return done(["recipe": recipeKey, "handedOff": true, "note": text])
                case let .notTold(text): return refuse(text)
                }

            case .hostingStart:
                try server!.startPackHost()
                return done(["listening": server!.packHostIsListening, "joiningOnly": server!.packHostSettings.joiningOnly])

            case .hostingStop:
                server!.stopPackHost()
                return done(["listening": false])

            case .hostingAdd:
                let server = server!
                server.hostedRecipe(recipeKey)
                var out: [String: Any] = ["recipe": recipeKey]
                if let address = server.packAddress(recipe: recipeKey) { out["address"] = address }
                return done(out)

            case .hostingRemove:
                try server!.removeHostedRecipe(recipeKey)
                return done(["recipe": recipeKey, "removed": true])
            }
        } catch {
            return refuse(error.localizedDescription)
        }
    }
}
