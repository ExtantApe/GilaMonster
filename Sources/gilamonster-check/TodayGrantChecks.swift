import Foundation
import Security
@testable import GilaMonsterCore

/// Allow for today (K721; owner, 2026-11-23: "Same action, same server (Recommended)", then "It should work for all
/// servers"): which actions it covers, local midnight, every server but only that kind of action, revoke, nobody
/// online and refusing when that can't be told, and that only the owner's click on a waiting ask makes a grant.
@MainActor func todayGrantChecks() async {
    section("Allow for today: what it covers")
    for a in [SessionAction.start, .stop, .restart] { check(a.todayFamily == .power, "\(a.rawValue) is covered with starts, stops and restarts") }
    check(SessionAction.hostingStart.todayFamily == .serving && SessionAction.hostingStop.todayFamily == .serving, "pack serving on and off go together")
    for a in [SessionAction.hostingRemove, .gateCheck, .backupStatus, .hostingStatus, .packAdd, .recipeSet, .recipeBuild] {
        check(a.todayFamily == nil, "\(a.rawValue) is never covered")
    }
    check(!SessionAction.allCases.contains { ["delete", "restore", "reset", "remove-world", "wipe"].contains(where: $0.rawValue.contains) && $0.todayFamily != nil },
          "nothing that deletes, restores or resets a world can be covered")

    section("Allow for today: local midnight")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Phoenix")!
    let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 59, second: 30))!
    let midnight = cal.date(from: DateComponents(year: 2026, month: 11, day: 24))!
    equal(TodayGrants.midnight(after: late, calendar: cal), midnight, "a click at 23:59:30 lasts until 00:00 that night")
    var g = TodayGrants()
    let first = g.add(.power, now: cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!, calendar: cal)
    let again = g.add(.power, now: late, calendar: cal)
    check(first.until == midnight && again.until == midnight && again.granted == first.granted, "a second click the same day ends at the same midnight, never later")
    check(g.covers(.power, now: midnight.addingTimeInterval(-1)) && !g.covers(.power, now: midnight), "covered up to midnight, not at it")
    check(!g.covers(.serving, now: late), "and only the kind of action it was given for")
    check(!g.covers(.power, now: first.granted.addingTimeInterval(-60)), "a clock set back before the click isn't covered, so the clock can't stretch a grant")
    var la = Calendar(identifier: .gregorian)
    la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let fallBack = la.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
    let laMidnight = TodayGrants.midnight(after: fallBack, calendar: la)
    equal(la.dateComponents([.year, .month, .day, .hour, .minute], from: laMidnight), DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 0), "on the day the clocks go back it still ends at local midnight")
    g.revokeAll()
    check(!g.covers(.power, now: late) && g.active(now: late).isEmpty, "revoking ends everything")
    check(!(TodayGrants() as Any is Encodable) && !(TodayGrants() as Any is Decodable), "grants can't be written to or read from a file")

    section("Allow for today: who's online")
    let watch = folder("today-watch")
    write("server-port=25596\nserver-ip=127.0.0.1\nmotd=made up\n", watch.appendingPathComponent("server.properties"))
    if let w = try? await ServerController.adopt(root: watch, name: "Made-up Today Watch") {
        w.noteConnection("MadeUpHidden[/127.0.0.1:50000] logged in with entity id 7 at ([world]0.5, 64.0, 0.5)")
        check(w.connected == ["MadeUpHidden"] && w.players.isEmpty, "a login with no join message (a vanish plugin) is still counted")
        check(Online.decide(state: .running, management: false, managementPlayers: nil, consolePlayers: max(w.players.count, w.connected.count)) == .someone(1), "so a hidden player means someone is on")
        w.noteConnection("<MadeUpChatter> MadeUpFake[/1.2.3.4:1] logged in with entity id 1")
        check(w.connected == ["MadeUpHidden"], "a chat line shaped like a login doesn't count")
        w.noteConnection("MadeUpHidden lost connection: Disconnected")
        check(w.connected.isEmpty, "and the disconnect line takes them off")
    } else { check(false, "couldn't adopt the watch server") }
    check(Online.decide(state: .stopped, management: false, managementPlayers: nil, consolePlayers: 0) == .nobody, "a stopped server has nobody on it")
    check(Online.decide(state: .running, management: true, managementPlayers: 0, consolePlayers: 3) == .nobody, "the management server's answer wins over the console")
    check(Online.decide(state: .running, management: true, managementPlayers: 2, consolePlayers: 0) == .someone(2), "two online, from the management server")
    check(Online.decide(state: .running, management: false, managementPlayers: nil, consolePlayers: 1) == .someone(1), "one online, from the console")
    if case .unsure = Online.decide(state: .running, management: true, managementPlayers: nil, consolePlayers: 0) {} else { check(false, "a management server that doesn't answer is unsure") }
    for s in [ServerState.starting, .stopping, .external(pid: 1)] {
        if case .unsure = Online.decide(state: s, management: false, managementPlayers: nil, consolePlayers: 0) {} else { check(false, "\(s.title) is unsure") }
    }

    // Two made-up servers that are never started, and a session asking about pack addresses (covered as one kind).
    let rootA = folder("today-a"), rootB = folder("today-b")
    write("server-port=25594\nserver-ip=127.0.0.1\nmotd=made up\n", rootA.appendingPathComponent("server.properties"))
    write("server-port=25595\nserver-ip=127.0.0.1\nmotd=made up\n", rootB.appendingPathComponent("server.properties"))
    guard let a = try? await ServerController.adopt(root: rootA, name: "Made-up Today A"),
          let b = try? await ServerController.adopt(root: rootB, name: "Made-up Today B") else { check(false, "couldn't adopt the made-up servers"); return }
    let nobodyOnA = await a.whoIsOnline()
    check(nobodyOnA == .nobody, "a real made-up server that never started has nobody on it")
    let (path, _) = throwawayKeychain("today-grants")
    var kc: SecKeychain?
    guard SecKeychainOpen(path, &kc) == errSecSuccess, let kc else { check(false, "couldn't open the throwaway keychain"); return }
    let service = SessionAccessService()
    service.keychain = kc
    let logDir = folder("today-log")
    service.logFile = logDir.appendingPathComponent("calls.jsonl")
    service.servers = { [a, b] }
    service.calendar = cal
    var clock = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 14))!
    service.now = { clock }
    var on = SessionAccessSettings(); on.enabled = true
    try? SessionAccess.saveSettings(on)
    defer { try? SessionAccess.saveSettings(SessionAccessSettings()) }
    let token = SessionAccess.token(create: true, keychain: kc) ?? ""
    let zip = await makePack("Today Pack", ["pack.mcmeta": #"{"pack":{"pack_format":75,"description":"today"}}"#, "assets/madeup/t.json": "{}"])
    func call(_ name: String, _ server: String, _ extra: [String: Any] = [:]) async -> [String: Any] {
        var body: [String: Any] = ["token": token, "caller": "Made-up Session", "call": name, "server": server]
        body.merge(extra) { $1 }
        let reply = await service.answer(try! JSONSerialization.data(withJSONObject: body))
        return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] ?? [:]
    }
    func error(_ r: [String: Any]) -> String { r["error"] as? String ?? "" }
    var r = await call("pack-add", "Made-up Today A", ["path": zip.path])
    _ = await call("recipe-set", "Made-up Today A", ["recipe": "today-one", "packs": [r["pack"] as? String ?? ""]])
    _ = await call("recipe-set", "Made-up Today A", ["recipe": "today-two", "packs": [r["pack"] as? String ?? ""]])
    var asked: [SessionApproval] = []
    var notices: [String] = []
    var answer: ((SessionApproval) -> Void)? = nil
    service.onAsk = { q in asked.append(q); answer?(q) }
    service.onAutoAllowed = { notices.append($0) }
    service.approvalWait = 0.3

    section("Allow for today: only the owner's click on a waiting ask")
    for name in ["allow-today", "today", "grant", "allow"] {
        r = await call(name, "Made-up Today A")
        check(r["ok"] as? Bool == false && error(r).contains("isn't a call"), "\"\(name)\" isn't a session call")
    }
    check(!SessionAction.allCases.contains { ["today", "grant", "allow"].contains(where: $0.rawValue.contains) }, "no session call can make or extend a grant")
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-one", "allowForToday": true, "today": true, "grant": "address"])
    check(r["ok"] as? Bool == false && asked.count == 1 && service.today.active(now: clock).isEmpty, "fields in a request asking for it are ignored: it still asks, and lapses unanswered")
    service.resolveForToday(UUID())
    service.resolveForToday(asked.last!.id)
    check(service.today.active(now: clock).isEmpty, "a click for a request that isn't waiting makes nothing")
    answer = { q in if q.action == .hostingRemove { service.resolveForToday(q.id) } }
    r = await call("hosting-remove", "Made-up Today A", ["recipe": "today-one"])
    check(error(r).contains("no pack address"), "removing an address that isn't there is refused first")

    section("Allow for today: one click covers every server, and only that kind of action")
    answer = { q in service.resolveForToday(q.id) }
    asked.removeAll()
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-one"])
    check(r["ok"] as? Bool == true && asked.count == 1 && asked[0].canAllowForToday, "the first one asks, with Allow for today offered, and goes ahead on the click")
    check(service.today.covers(.address, now: clock), "the click covers pack addresses until midnight")
    answer = nil
    r = await call("hosting-add", "Made-up Today B", ["recipe": "today-one"])
    check(r["ok"] as? Bool == true && asked.count == 1 && b.packHostSettings.recipes["today-one"] != nil, "a second server goes ahead without asking")
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    check(r["ok"] as? Bool == true && asked.count == 1, "and another on the first server")
    equal(notices.count, 2, "each one that went ahead without asking showed a notice")
    check(service.wentAhead.count == 2 && service.wentAhead[0].text.contains("Made-up Today A"), "and is listed for the menu bar, newest first")
    check(notices.first?.contains("Made-up Today B") == true && notices.first?.contains("for today") == true, "naming the server: \(notices.first ?? "")")
    check(b.console.contains { $0.text.contains("Allowed for today") }, "and wrote it to that server's log")
    r = await call("hosting-start", "Made-up Today B")
    check(r["ok"] as? Bool == false && asked.count == 2 && asked.last?.action == .hostingStart, "another kind of action still asks (and lapses unanswered)")
    r = await call("hosting-remove", "Made-up Today B", ["recipe": "today-one"])
    check(r["ok"] as? Bool == false && asked.count == 3 && asked.last?.canAllowForToday == false, "a removal asks, with no Allow for today offered")
    service.resolveForToday(asked.last!.id)
    check(b.packHostSettings.recipes["today-one"] != nil, "and a click for it can't allow it (it lapsed)")

    section("Allow for today: nobody online, and refusing when that can't be told")
    try? a.removeHostedRecipe("today-two")
    service.online = { _ in .someone(2) }
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    check(r["ok"] as? Bool == false && asked.count == 4, "with players online it asks as usual (and lapses unanswered)")
    service.online = { _ in .unsure("made-up reason") }
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    check(r["ok"] as? Bool == false && error(r).contains("couldn't tell") && asked.count == 4, "when nobody can be sure, it's refused without asking: \(error(r))")
    check(a.packHostSettings.recipes["today-two"] == nil, "and nothing changed")
    service.online = nil

    service.online = { _ in service.revokeToday(); return .nobody }
    try? a.removeHostedRecipe("today-two")
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    check(r["ok"] as? Bool == false && asked.count == 5 && a.packHostSettings.recipes["today-two"] == nil, "a revoke while the online check runs means it asks as usual")
    service.online = nil
    answer = { q in service.resolveForToday(q.id) }
    _ = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    answer = nil
    try? a.removeHostedRecipe("today-two")

    section("Allow for today: midnight and revoke")
    clock = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 0, minute: 0, second: 1))!
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    check(r["ok"] as? Bool == false && asked.count == 7, "after midnight it asks again")
    answer = { q in service.resolveForToday(q.id) }
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    check(r["ok"] as? Bool == true && service.today.covers(.address, now: clock), "a new click the next day covers that day")
    answer = nil
    service.revokeToday()
    try? a.removeHostedRecipe("today-two")
    r = await call("hosting-add", "Made-up Today A", ["recipe": "today-two"])
    check(r["ok"] as? Bool == false && asked.count == 9, "after the menu bar's revoke it asks again")

    service.onAsk = { q in asked.append(q) }
    var body: [String: Any] = ["token": token, "caller": "Made\u{202E}up\u{0007} Session", "call": "hosting-start", "server": "Made-up Today A"]
    _ = await service.answer(try! JSONSerialization.data(withJSONObject: body))
    check(asked.last?.caller == "Madeup Session", "control and bidi characters are taken out of the caller's name: \(asked.last?.caller ?? "")")
    body = [:]
    service.onAsk = { q in asked.append(q); answer?(q) }

    section("Allow for today: nothing kept")
    check(SessionAccessService().today.active(now: clock).isEmpty, "a new GilaMonster starts with no grants, so quitting clears them")
    let calls = SessionAccess.recentLog(200, from: service.logFile!)
    check(calls.contains { $0.note == "Allowed for today by the owner, until midnight" } && calls.contains { $0.note == "Allowed for today by the owner; nobody online" },
          "the record says which went ahead on the click and which without asking")
    check(calls.contains { !$0.allowed && $0.note.contains("couldn't tell") }, "and the refusal")
    let written = (try? FileManager.default.subpathsOfDirectory(atPath: logDir.path)) ?? []
    equal(written, ["calls.jsonl"], "nothing but the record is written beside it")
    let metaFiles = [rootA, rootB].flatMap { (try? FileManager.default.subpathsOfDirectory(atPath: $0.path)) ?? [] }
    check(!metaFiles.contains { $0.lowercased().contains("today") || $0.lowercased().contains("grant") }, "and no grant file in either server's folder")
}
