import Foundation
import Security
@testable import LeafJuiceCore

/// Session actions (D217, D220): the children mark and standing permission, the Allow flow (allowed, denied, no
/// answer, nobody to ask), the backup refusal, and each action against a made-up server that never starts.
@MainActor func sessionActionChecks() async {
    section("Session actions: the children mark")
    let meta = folder("session-mark")
    var p = SessionPermission.load(meta: meta)
    check(p.childrenMayPlay && !p.standing && !p.skipsPrompt, "no mark file: children may play, no standing permission")
    write("{not json", SessionPermission.file(meta: meta))
    p = SessionPermission.load(meta: meta)
    check(p.childrenMayPlay && !p.skipsPrompt, "an unreadable mark file counts as children may play")
    write(#"{"standing":true}"#, SessionPermission.file(meta: meta))
    check(!SessionPermission.load(meta: meta).skipsPrompt, "standing permission without the mark cleared still asks")
    write(#"{"childrenMayPlay":true,"standing":true}"#, SessionPermission.file(meta: meta))
    check(!SessionPermission.load(meta: meta).skipsPrompt, "a file saying both still asks: the mark wins")
    var refused = false
    do { try SessionPermission.save(SessionPermission(childrenMayPlay: true, standing: true), meta: meta) } catch { refused = true }
    check(refused, "saving standing permission for a marked server is refused")
    write(#"{"childrenMayPlay":false,"standing":true}"#, SessionPermission.file(meta: meta))
    check(SessionPermission.load(meta: meta).skipsPrompt, "only a cleared mark plus standing permission skips the prompt")
    for (call, kind) in [("start", SessionAction.Kind.ask), ("stop", .ask), ("restart", .ask), ("publish", .ask), ("handoff", .ask),
                         ("hosting-start", .ask), ("hosting-stop", .ask), ("hosting-add", .ask), ("hosting-remove", .ask),
                         ("hosting-status", .read), ("backup-status", .read), ("gate-check", .read),
                         ("pack-add", .build), ("recipe-set", .build), ("recipe-build", .build)] {
        check(SessionAction(rawValue: call)?.kind == kind, "\(call) is a \(kind) call")
    }
    check(!SessionAction.allCases.contains { ["mark", "children", "standing", "permission"].contains(where: $0.rawValue.contains) },
          "no session call can change the mark or standing permission")

    // A made-up server that is never started.
    let root = folder("session-actions")
    write("server-port=25593\nserver-ip=127.0.0.1\nmotd=made up\n", root.appendingPathComponent("server.properties"))
    guard let server = try? await ServerController.adopt(root: root, name: "Made-up Actions") else { check(false, "couldn't adopt a made-up server"); return }
    check(server.sessionPermission.childrenMayPlay, "a new server starts marked")
    var standingRefused = false
    do { try server.setStandingPermission(true) } catch { standingRefused = true }
    check(standingRefused && !server.sessionPermission.standing, "standing permission is refused while marked")

    let (path, _) = throwawayKeychain("session-actions")
    var kc: SecKeychain?
    guard SecKeychainOpen(path, &kc) == errSecSuccess, let kc else { check(false, "couldn't open the throwaway keychain"); return }
    let service = SessionAccessService()
    service.keychain = kc
    service.logFile = folder("session-actions-log").appendingPathComponent("calls.jsonl")
    service.servers = { [server] }
    var on = SessionAccessSettings(); on.enabled = true
    try? SessionAccess.saveSettings(on)
    defer { try? SessionAccess.saveSettings(SessionAccessSettings()) }
    let token = SessionAccess.token(create: true, keychain: kc) ?? ""
    func call(_ name: String, _ extra: [String: Any] = [:]) async -> [String: Any] {
        var body: [String: Any] = ["token": token, "caller": "Made-up Session", "call": name, "server": "Made-up Actions"]
        body.merge(extra) { $1 }
        let reply = await service.answer(try! JSONSerialization.data(withJSONObject: body))
        return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] ?? [:]
    }
    func error(_ r: [String: Any]) -> String { r["error"] as? String ?? "" }
    var asked: [SessionApproval] = []
    var reply: Bool? = nil

    section("Session actions: asking the owner")
    service.onAsk = nil
    var r = await call("hosting-add", ["recipe": "made-up-recipe"])
    // The recipe has to exist; that's checked before anyone is asked.
    check(r["ok"] as? Bool == false && error(r).contains("no recipe"), "an unknown recipe is refused before anyone is asked: \(error(r))")

    // A pack, a recipe and a build: no prompt.
    section("Session actions: packs and recipes, no prompt")
    let zip = await makePack("Session Pack", ["pack.mcmeta": #"{"pack":{"pack_format":75,"description":"session"}}"#, "assets/madeup/x.json": "{}"])
    r = await call("pack-add", ["path": "relative/pack.zip"])
    check(r["ok"] as? Bool == false, "a relative path is refused")
    let link = folder("session-link").appendingPathComponent("linked.zip")
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: zip)
    r = await call("pack-add", ["path": link.path])
    check(r["ok"] as? Bool == false && error(r).contains("plain file"), "a link to a zip is refused")
    service.onAsk = { asked.append($0) }
    r = await call("pack-add", ["path": zip.path])
    let packID = r["pack"] as? String ?? ""
    check(r["ok"] as? Bool == true && !packID.isEmpty, "a zip is added to the library: \(r)")
    r = await call("recipe-set", ["recipe": "made-up-recipe", "packs": [packID, "no-such-pack"]])
    check(r["ok"] as? Bool == false && error(r).contains("no pack"), "a recipe naming a pack that isn't there is refused")
    r = await call("recipe-set", ["recipe": "made-up-recipe", "packs": [packID]])
    check(r["ok"] as? Bool == true, "a recipe is set: \(r)")
    r = await call("recipe-build", ["recipe": "made-up-recipe"])
    let sha1 = r["sha1"] as? String ?? ""
    check(r["ok"] as? Bool == true && sha1.count == 40, "and built: \(r)")
    check(asked.isEmpty, "none of that asked the owner")

    section("Session actions: Allow, Deny, no answer, nobody to ask")
    service.onAsk = nil
    r = await call("hosting-add", ["recipe": "made-up-recipe"])
    check(r["ok"] as? Bool == false && error(r).contains("couldn't ask"), "with nobody to ask, it's a no")
    check(server.packHostSettings.recipes["made-up-recipe"] == nil, "and nothing changed")
    service.onAsk = { a in asked.append(a); if let reply { service.resolve(a.id, allow: reply) } }
    reply = false
    r = await call("hosting-add", ["recipe": "made-up-recipe"])
    check(r["ok"] as? Bool == false && error(r).contains("said no"), "denied, it's a no")
    check(server.packHostSettings.recipes["made-up-recipe"] == nil, "and nothing changed")
    check(asked.last?.sentence == "Made-up Session wants to give made-up-recipe a pack address on Made-up Actions", "the prompt says who wants what: \(asked.last?.sentence ?? "")")
    reply = nil
    service.approvalWait = 0.3
    r = await call("hosting-add", ["recipe": "made-up-recipe"])
    check(r["ok"] as? Bool == false && error(r).contains("didn't answer"), "no answer in time is a no")
    check(service.waiting.isEmpty && server.packHostSettings.recipes["made-up-recipe"] == nil, "nothing changed, and nothing is left waiting")
    reply = true
    r = await call("hosting-add", ["recipe": "made-up-recipe"])
    check(r["ok"] as? Bool == true && server.packHostSettings.recipes["made-up-recipe"] != nil, "allowed, it's done")

    // A late answer for a request that's already over does nothing.
    let before = asked.count
    service.resolve(asked.last!.id, allow: true)
    equal(asked.count, before, "a second answer to the same request is ignored")

    section("Session actions: refused before asking")
    asked.removeAll()
    r = await call("stop")
    check(r["ok"] as? Bool == false && error(r).contains("isn't running"), "stop on a stopped server: refused")
    r = await call("restart")
    check(r["ok"] as? Bool == false, "restart too")
    r = await call("publish", ["recipe": "no-such-recipe"])
    check(r["ok"] as? Bool == false, "publishing a recipe that isn't there")
    r = await call("hosting-remove", ["recipe": "never-added"])
    check(r["ok"] as? Bool == false && error(r).contains("no pack address"), "removing an address that isn't there")
    r = await call("gate-check", ["url": "https://packs.example.test/x/pack.zip", "player": "bad name!"])
    check(r["ok"] as? Bool == false && error(r).contains("player name"), "a player name that can't be one")
    try? server.beginBusy("A made-up backup")
    r = await call("start")
    check(r["ok"] as? Bool == false && error(r).contains("A made-up backup is in progress"), "start while the server is busy is refused with the reason, not a quiet ok: \(error(r))")
    server.endBusy()
    r = await call("not-a-call")
    check(r["ok"] as? Bool == false && error(r).contains("isn't a call"), "an unknown call")
    check(asked.isEmpty, "none of those bothered the owner")

    section("Session actions: reads")
    r = await call("hosting-status")
    check(r["ok"] as? Bool == true && r["listening"] as? Bool == false && r["joiningOnly"] as? Bool == true, "hosting status: stopped, joining only on: \(r)")
    check((r["recipes"] as? [[String: Any]])?.first?["recipe"] as? String == "made-up-recipe", "with its recipes")
    r = await call("backup-status")
    check(r["ok"] as? Bool == true && r["writing"] as? Bool == false, "backup status: nothing being written")
    try? server.setPackHost(address: "https://packs.example.test", port: 28790)
    let address = server.packAddress(recipe: "made-up-recipe") ?? ""
    r = await call("gate-check", ["url": address])
    check(r["ok"] as? Bool == true && r["matches"] as? Bool == true && (r["decision"] as? String)?.contains("stopped") == true, "gate check: the address is known, serving is stopped: \(r)")
    r = await call("gate-check", ["url": "https://packs.example.test/wrong/pack.zip"])
    check(r["matches"] as? Bool == false, "a wrong path matches nothing")
    check(asked.isEmpty, "reads don't ask")
    r = await call("gate-check", ["url": address, "player": "MadeUpJoiner"])
    check(asked.isEmpty && r["player"] == nil, "naming a player while serving is stopped doesn't ask, and says nothing about them")
    try? server.startPackHost()
    await checkUntil(5, "listening") { server.packHostIsListening }
    r = await call("gate-check", ["url": address, "player": "MadeUpJoiner"])
    check(asked.count == 1 && asked.last?.action == .gateCheck, "while the gate decides, naming a player asks first, since it says whether they're joining")
    check(r["ok"] as? Bool == true && r["player"] as? String == "MadeUpJoiner" && r["wouldGet"] as? Bool == false, "and answers once allowed (not whitelisted, so no): \(r)")
    server.stopPackHost()

    section("Session actions: backups and standing permission")
    let job = UUID()
    Backups.inFlight.with { $0[job] = Backups.Job(process: nil, partial: folder("session-partial").appendingPathComponent("x.part"), server: "Made-up Actions", started: Date(), expected: 1) }
    asked.removeAll()
    r = await call("hosting-remove", ["recipe": "made-up-recipe"])
    check(r["ok"] as? Bool == false && error(r).contains("backup"), "nothing that asks runs while a backup is being written")
    check(asked.isEmpty && server.packHostSettings.recipes["made-up-recipe"] != nil, "not even asked, and nothing changed")
    r = await call("backup-status")
    check(r["writing"] as? Bool == true, "backup status shows it")
    Backups.inFlight.with { $0[job] = nil }

    try? server.setChildrenMayPlay(false)
    check(!server.sessionPermission.childrenMayPlay, "the owner clears the mark")
    check(server.console.contains { $0.text.contains("Cleared the mark") }, "which is written to the server's log")
    try? server.setStandingPermission(true)
    reply = nil
    service.onAsk = { asked.append($0) }
    r = await call("hosting-remove", ["recipe": "made-up-recipe"])
    check(r["ok"] as? Bool == true && asked.isEmpty, "with standing permission on an unmarked server, it goes ahead without asking")
    try? server.setChildrenMayPlay(true)
    check(server.sessionPermission.childrenMayPlay && !server.sessionPermission.standing, "marking it again takes standing permission away")
    service.approvalWait = 0.2
    r = await call("hosting-add", ["recipe": "made-up-recipe"])
    check(r["ok"] as? Bool == false && asked.count == 1, "so it asks again")

    let calls = SessionAccess.recentLog(100, from: service.logFile!)
    check(calls.contains { $0.note == "Standing permission" } && calls.contains { $0.note == "Allowed by the owner" }, "the record says how each change was allowed")
    check(calls.contains { !$0.allowed && $0.note.contains("said no") }, "and each refusal")
    check(!((try? String(contentsOf: service.logFile!, encoding: .utf8)) ?? "").contains(token), "the token is never in the record")
}
