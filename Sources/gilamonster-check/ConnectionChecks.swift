import Foundation
import GilaMonsterCore
import Network
import Security

/// Made-up answers for every outside thing a connection check touches, with a record of what was asked.
final class FakeConnectionProbe: ConnectionProbe, @unchecked Sendable {
    private let lock = NSLock()
    var tools: [String: (Int32, String)] = [:]
    var executables: Set<String> = []
    var files: [String: (size: Int, mode: Int)] = [:]
    var tails: [String: String] = [:]
    var secrets: [String: SecretPresence] = [:]
    var answering: Set<String> = []     // host:port that answer a TCP connect
    var gameAnswering: Set<String> = [] // host:port that answer a status ping
    var web: [String: Int] = [:]
    var names: [String: [String]] = [:]
    private var _asked: [String] = []
    var asked: [String] { lock.lock(); defer { lock.unlock() }; return _asked }
    let now = Date()
    let home = "/made-up-home"

    private func ask(_ s: String) { lock.lock(); _asked.append(s); lock.unlock() }
    func run(_ path: String, _ args: [String], timeout: TimeInterval) async -> (status: Int32, out: String)? { ask("run \(path)"); return tools[path] }
    func isExecutable(_ path: String) -> Bool { executables.contains(path) }
    func fileInfo(_ path: String) -> (size: Int, mode: Int)? { files[path] }
    func tail(_ path: String, bytes: Int) -> String? { tails[path] }
    func keychain(_ account: String) -> SecretPresence { ask("keychain \(account)"); return secrets[account] ?? .missing }
    var undecided: [String: String] = [:] // host:port where a connection gives no verdict, and why
    func connect(host: String, port: Int, timeout: TimeInterval) async -> ConnectAnswer {
        let at = "\(host):\(port)"
        ask("tcp \(at)")
        if let why = undecided[at] { return .undecided(why) }
        return answering.contains(at) || gameAnswering.contains(at) ? .connected : .refused
    }
    func minecraftStatus(host: String, port: Int, timeout: TimeInterval) async -> Bool { ask("ping \(host):\(port)"); return gameAnswering.contains("\(host):\(port)") }
    func httpStatus(_ url: URL, timeout: TimeInterval) async -> Int? { ask("http \(url.absoluteString)"); return web[url.absoluteString] }
    func resolve(_ host: String) async -> [String]? { ask("dns \(host)"); return names[host] }
}

@MainActor func connectionChecks() async {
    section("Connections: the file")
    let meta = folder("connections-meta")
    var loaded = ConnectionStore.load(meta)
    check(loaded.settings == ConnectionSettings() && loaded.problems.isEmpty && !loaded.unreadable, "no file means no connections and no complaint")

    write("{not json", ConnectionStore.file(meta))
    loaded = ConnectionStore.load(meta)
    check(loaded.unreadable && loaded.settings.services.isEmpty && loaded.problems.count == 1, "an unreadable file is reported, not a crash")
    var fresh = ConnectionSettings(); fresh.playerAddress = "play.example.test"
    try? ConnectionStore.save(fresh, meta: meta, replacingUnreadable: true)
    check(FileManager.default.fileExists(atPath: meta.appendingPathComponent("connections.json.unreadable").path), "saving over it moves the old file aside first")
    equal(ConnectionStore.load(meta).settings, fresh, "and the new file reads back")

    let pasted = "made-up-secret-value-0000"
    let text = """
    {"playerAddress":"play.example.test","token":"\(pasted)","services":[
      {"id":"play","name":"Game tunnel","provider":"playit","traffic":"game","enabled":true,"localAddress":"127.0.0.1:25565","publicAddress":"play.example.test","secret":{"agent":{}}},
      {"id":"pack","provider":"playit","traffic":"web","localAddress":"127.0.0.1:8766","secret_key":"x","authKey":"\(pasted)"},
      {"id":"later","provider":"wireguard-someday","traffic":"teleport","enabled":true},
      {"id":"Bad Name","provider":"other","enabled":true},
      {"id":"play","provider":"other","enabled":true},
      {"name":"no id"},
      "not an object"
    ]}
    """
    loaded = ConnectionStore.parse(Data(text.utf8))
    equal(loaded.settings.services.map(\.id), ["play", "pack", "later"], "good entries load; a bad id, a repeated id and broken entries are skipped")
    equal(loaded.settings.services.first?.secret, .agent, "where a secret lives is read")
    equal(loaded.settings.services[1].enabled, false, "an entry that doesn't say it's on is off")
    equal(loaded.settings.services[2].provider, .other, "a provider this version doesn't know reads as Other")
    equal(loaded.settings.services[2].traffic, .access, "and unknown traffic as admin access, which is never pinged")
    check(loaded.problems.contains { $0.contains("token") && $0.contains("Keychain") }, "a secret pasted at the top is named as ignored")
    check(loaded.problems.contains { $0.contains("authKey") }, "and one pasted into a service")
    check(!loaded.problems.joined().contains(pasted), "the pasted value itself is never repeated")
    check(loaded.problems.count >= 6, "each skipped entry says why (\(loaded.problems.count) problems)")
    let saved = folder("connections-meta-2")
    try? ConnectionStore.save(loaded.settings, meta: saved, replacingUnreadable: false)
    let savedText = (try? String(contentsOf: ConnectionStore.file(saved), encoding: .utf8)) ?? ""
    check(!savedText.contains(pasted) && !savedText.contains("authKey") && !savedText.contains("\"token\""), "saving drops the pasted secrets")
    equal(ConnectionStore.load(saved).settings, loaded.settings, "and everything else reads back the same")

    // Reported on 2026-11-14: the README's own shape must not be flagged.
    let readmeShaped = ConnectionStore.parse(Data(#"{"playerAddress":"play.example.test","services":[{"id":"play","provider":"playit","traffic":"game","enabled":true,"localAddress":"127.0.0.1:25565","secret":{"agent":{}}},{"id":"api","provider":"other","traffic":"web","enabled":true,"secret":{"keychain":{"account":"api"}}},{"id":"f","provider":"other","traffic":"web","secret":{"file":{"path":"~/x"}}}]}"#.utf8))
    check(readmeShaped.problems.isEmpty, "the documented secret field, holding where a secret lives, isn't flagged (\(readmeShaped.problems))")
    let pastedIntoSecret = ConnectionStore.parse(Data(#"{"services":[{"id":"play","provider":"playit","secret":"made-up-pasted-value"}]}"#.utf8))
    check(pastedIntoSecret.problems.contains { $0.contains("secret") } && !pastedIntoSecret.problems.joined().contains("made-up-pasted-value"), "but a secret pasted straight into that field is named, without repeating it")
    check(pastedIntoSecret.settings.services.first?.id == "play" && pastedIntoSecret.settings.services.first?.secret == nil, "and isn't kept, while the rest of the entry is")

    // Moving a pasted secret into the Keychain (2026-11-14), with a throwaway keychain.
    do {
        let moveMeta = folder("connections-move")
        let value = "made-up-pasted-\(UUID().uuidString)"
        write(#"{"apiKey":"top-\#(value)","services":[{"id":"play","provider":"playit","enabled":true,"localAddress":"127.0.0.1:25565","token":"\#(value)"},{"id":"other","provider":"other","secret":"\#(value)-2"}]}"#, ConnectionStore.file(moveMeta))
        var loaded = ConnectionStore.load(moveMeta)
        equal(loaded.pasted.map(\.id), ["-/apiKey", "play/token", "other/secret"], "each pasted secret is found, by where it is")
        let (kcPath, _) = throwawayKeychain("connections-move")
        var moveKC: SecKeychain?
        _ = SecKeychainOpen(kcPath, &moveKC)
        for p in loaded.pasted {
            try ConnectionStore.moveToKeychain(p, meta: moveMeta) { v, account in try ConnectionSecrets.save(v, account: account, in: moveKC) }
        }
        let after = (try? String(contentsOf: ConnectionStore.file(moveMeta), encoding: .utf8)) ?? ""
        check(!after.contains("made-up-pasted"), "after moving, no secret is left in the file")
        loaded = ConnectionStore.load(moveMeta)
        check(loaded.pasted.isEmpty && loaded.problems.isEmpty, "and nothing is flagged any more")
        equal(loaded.settings.services.first { $0.id == "play" }?.secret, .keychain(account: "play"), "the connection's secret now points at the Keychain")
        equal(loaded.settings.services.first { $0.id == "play" }?.localAddress, "127.0.0.1:25565", "and the rest of it is untouched")
        equal(ConnectionSecrets.presence(account: "play", in: moveKC), .present, "the value is in the Keychain")
        equal(ConnectionSecrets.presence(account: "connections-apikey", in: moveKC), .present, "the top-level one too")
        let failing = ConnectionStore.PastedSecret(service: "gone", key: "token")
        check((try? ConnectionStore.moveToKeychain(failing, meta: moveMeta) { _, _ in }) == nil, "moving something that isn't there is refused")
        write(#"{"services":[{"id":"x","provider":"other","token":"made-up-keep-me"}]}"#, ConnectionStore.file(moveMeta))
        struct Refused: Error {}
        let refused = (try? ConnectionStore.moveToKeychain(ConnectionStore.PastedSecret(service: "x", key: "token"), meta: moveMeta) { _, _ in throw Refused() }) == nil
        check(refused && ((try? String(contentsOf: ConnectionStore.file(moveMeta), encoding: .utf8)) ?? "").contains("made-up-keep-me"), "if the Keychain refuses, the file keeps the value, so nothing is lost")
    } catch { check(false, "moving pasted secrets threw: \(error)") }

    section("Connections: addresses")
    equal(HostPort.parse("127.0.0.1:25565"), HostPort(host: "127.0.0.1", port: 25565), "host and port")
    equal(HostPort.parse("[::1]:8766"), HostPort(host: "::1", port: 8766), "IPv6 in brackets")
    equal(HostPort.parse("play.example.test", defaultPort: 25565)?.port, 25565, "a bare name takes the game's port")
    for bad in ["", "play.example.test", "host:0", "host:70000", "a b:1", "https://x:1", "::1:25565", "[::1", "host:port"] {
        check(HostPort.parse(bad) == nil, "refused: '\(bad)'")
    }

    section("Connections: checks with made-up answers")
    let tool = "/made-up-home/Minecraft/_tools/playit/playit"
    let running = "playitd daemon status for socket /x:\n  Phase: running\n  PID: 4242\n  Version: 2.0.0\n  Secret configured: true\n"
    func playitProbe() -> FakeConnectionProbe {
        let p = FakeConnectionProbe()
        p.executables = [tool]
        p.tools[tool] = (0, running)
        p.gameAnswering = ["127.0.0.1:25565"]
        p.answering = ["127.0.0.1:8766"]
        return p
    }
    let ctx = ConnectionContext(serverRunning: true, serverIP: "127.0.0.1", serverPort: 25565, packHostPort: 8766)
    var play = ConnectionService(id: "play", name: "Game tunnel", provider: .playit, traffic: .game, localAddress: "127.0.0.1:25565", publicAddress: "play.example.test", secret: .agent)
    func run(_ s: ConnectionService, _ p: FakeConnectionProbe, _ c: ConnectionContext = ctx, outside: Bool = false) async -> ConnectionStatus {
        await ConnectionCheck.run(s, context: c, probe: p, outside: outside)
    }

    var p = playitProbe()
    var status = await run(play, p)
    equal(status.health, .ready, "a running agent with its secret, forwarding to a server that answers, is ready: \(status.summary)")
    check(!p.asked.contains { $0.hasPrefix("ping play.example.test") || $0.hasPrefix("http") }, "nothing goes over the internet unless asked")
    check(status.details.contains("Not tried from the internet yet."), "and it says so")

    var off = play; off.enabled = false
    p = playitProbe()
    let v1 = await run(off, p).health
    equal(v1, .off, "a connection that's off is shown off")
    check(p.asked.isEmpty, "and nothing about it is checked")

    p = playitProbe(); p.executables = []
    status = await run(play, p)
    equal(status.health, .notReady, "no playit agent installed: not ready")
    check(status.summary.contains("isn't installed"), "and says so: \(status.summary)")

    p = playitProbe(); p.tools[tool] = nil
    let v2 = await run(play, p).health
    equal(v2, .notReady, "an agent that won't answer: not ready")
    p = playitProbe(); p.tools[tool] = (0, "garbage")
    let v3 = await run(play, p).health
    equal(v3, .notReady, "an answer that can't be read: not ready")
    p = playitProbe(); p.tools[tool] = (0, running.replacingOccurrences(of: "Phase: running", with: "Phase: stopped"))
    let v4 = await run(play, p).health
    equal(v4, .notReady, "an agent that's stopped: not ready")
    p = playitProbe(); p.tools[tool] = (0, running.replacingOccurrences(of: "Secret configured: true", with: "Secret configured: false"))
    status = await run(play, p)
    equal(status.health, .notReady, "an agent with no secret: not ready, not a crash")
    check(status.summary.contains("no secret"), "and says what's missing: \(status.summary)")
    p = playitProbe(); p.tools[tool] = (0, running.replacingOccurrences(of: "  Secret configured: true\n", with: ""))
    let v5 = await run(play, p).health
    equal(v5, .unknown, "an agent that doesn't say: unknown, never ready")

    // The real case from 2026-11-10: the tunnel forwards to another address on this Mac, the server listens on 127.0.0.1 only.
    var viaOtherAddress = play; viaOtherAddress.localAddress = "100.64.10.20:25565"
    p = playitProbe()
    status = await run(viaOtherAddress, p)
    check(status.health == .notReady && status.summary.contains("127.0.0.1:25565"), "a tunnel pointing away from a server that only listens on 127.0.0.1 is flagged, with the fix: \(status.summary)")
    var wrongPort = play; wrongPort.localAddress = "127.0.0.1:25566"
    status = await run(wrongPort, playitProbe())
    check(status.health == .notReady && status.summary.contains("25566"), "a tunnel to the wrong port is flagged: \(status.summary)")
    status = await run(play, playitProbe(), ConnectionContext(serverRunning: true, serverIP: "", serverPort: 25565))
    equal(status.health, .ready, "a server listening everywhere is fine with 127.0.0.1")

    p = playitProbe(); p.gameAnswering = []
    status = await run(play, p)
    equal(status.health, .notReady, "a running server that doesn't answer where the tunnel points: not ready")
    p = playitProbe(); p.gameAnswering = []
    status = await run(play, p, ConnectionContext(serverRunning: false, serverIP: "127.0.0.1", serverPort: 25565))
    equal(status.health, .warning, "a stopped server is a warning, not a broken tunnel")

    let stamp = ISO8601DateFormatter(); stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func refusal(_ minutesAgo: Double, _ target: String = "127.0.0.1:25565") -> String {
        "\(stamp.string(from: Date().addingTimeInterval(-minutesAgo * 60))) ERROR playit_agent_core::network::lan_address: Failed to establish connection for flow (198.51.100.7:50030, \(target)) Os { code: 61, kind: ConnectionRefused, message: \"Connection refused\" }"
    }
    p = playitProbe(); p.tails["/made-up-home/Library/Logs/playit/playitd.log"] = [refusal(3), refusal(4), refusal(40), refusal(2, "127.0.0.1:8766")].joined(separator: "\n")
    status = await run(play, p)
    check(status.health == .warning && status.summary.contains("2 times"), "recent refusals in playit's log for this address are counted, older ones and other addresses aren't: \(status.summary)")

    // Secrets kept by GilaMonster: missing is not ready, never a crash; the value is never read.
    var keyed = ConnectionService(id: "status-api", name: "Status page", provider: .other, traffic: .web, publicAddress: "https://status.example.test", secret: .keychain(account: "status-api"))
    p = FakeConnectionProbe()
    status = await run(keyed, p)
    equal(status.health, .notReady, "a secret missing from the Keychain: not ready")
    check(status.summary.contains("Keychain"), "and it says where to put it: \(status.summary)")
    p = FakeConnectionProbe(); p.secrets["status-api"] = .unavailable("The Keychain is locked.")
    let v6 = await run(keyed, p).health
    equal(v6, .unknown, "a locked Keychain: unknown, not missing and not ready")
    p = FakeConnectionProbe(); p.secrets["status-api"] = .present
    let v7 = await run(keyed, p).health
    equal(v7, .ready, "with the secret there, ready")
    keyed.secret = .file(path: "~/Library/Application Support/madeup/agent.toml")
    let secretFile = "/made-up-home/Library/Application Support/madeup/agent.toml"
    p = FakeConnectionProbe()
    let v8 = await run(keyed, p).health
    equal(v8, .notReady, "a secret file that isn't there: not ready (~ is expanded)")
    p = FakeConnectionProbe(); p.files[secretFile] = (0, 0o600)
    let v9 = await run(keyed, p).health
    equal(v9, .notReady, "an empty secret file: not ready")
    p = FakeConnectionProbe(); p.files[secretFile] = (120, 0o644)
    let v10 = await run(keyed, p).health
    equal(v10, .warning, "a secret file others can read: flagged")
    p = FakeConnectionProbe(); p.files[secretFile] = (120, 0o600)
    let v11 = await run(keyed, p).health
    equal(v11, .ready, "a private one: fine")

    // Bad settings are reported, not run.
    var broken = play; broken.localAddress = "not an address"; broken.publicAddress = "https://wrong-kind.example.test"
    status = await run(broken, playitProbe())
    equal(status.health, .notReady, "addresses that can't be read: not ready")
    check(status.details.contains { $0.contains("local address") } && status.details.contains { $0.contains("public address") }, "each one is named")
    var noLocal = play; noLocal.localAddress = ""
    let v12 = await run(noLocal, playitProbe()).health
    equal(v12, .notReady, "a playit tunnel with nowhere to forward: not ready")

    // From outside, only when asked.
    p = playitProbe()
    status = await run(play, p, outside: true)
    check(p.asked.contains("ping play.example.test:25565"), "asked, it pings the public address as a player would")
    equal(status.health, .notReady, "and a public address that doesn't answer is not ready")
    p = playitProbe(); p.gameAnswering.insert("play.example.test:25565")
    let v13 = await run(play, p, outside: true).health
    equal(v13, .ready, "one that answers is ready")
    let packTunnel = ConnectionService(id: "pack", name: "Pack tunnel", provider: .playit, traffic: .web, localAddress: "127.0.0.1:8766", publicAddress: "https://pack.example.test:14248", secret: .agent)
    p = playitProbe(); p.web["https://pack.example.test:14248"] = 404
    status = await run(packTunnel, p, outside: true)
    equal(status.health, .ready, "any web answer proves the web tunnel reaches this Mac (pack serving answers strangers 404)")
    check(p.asked.contains("tcp 127.0.0.1:8766") && !p.asked.contains("ping 127.0.0.1:8766"), "web tunnels are checked with a plain connection, not a game ping")

    // A DNS name: looked up only when checking from outside.
    let name = ConnectionService(id: "dns", name: "Domain name", provider: .other, traffic: .dns, publicAddress: "example.test")
    p = FakeConnectionProbe()
    let dnsQuiet = await run(name, p)
    check(dnsQuiet.health == .ready && p.asked.isEmpty, "a name isn't looked up by the quiet check")
    p = FakeConnectionProbe()
    let dnsMissing = await run(name, p, outside: true)
    check(dnsMissing.health == .notReady && p.asked == ["dns example.test"], "from outside, a name that doesn't look up is not ready")
    p = FakeConnectionProbe(); p.names["example.test"] = ["192.0.2.10"]
    let dnsFound = await run(name, p, outside: true)
    equal(dnsFound.health, .ready, "and one that does is ready")
    let resolved = await SystemConnectionProbe().resolve("localhost")
    check(resolved?.contains("127.0.0.1") == true || resolved?.contains("::1") == true, "the real lookup finds localhost")


    section("Connections: the map and sign-in page")
    let withURLs = ConnectionStore.parse(Data(#"{"playerAddress":"play.example.test","mapURL":"https://map.example.test","signInURL":"https://example.test/signin","services":[]}"#.utf8))
    equal(withURLs.settings.mapURL, "https://map.example.test", "the map address is read")
    equal(withURLs.settings.signInURL, "https://example.test/signin", "and the sign-in page")
    let urlMeta = folder("connections-urls")
    try? ConnectionStore.save(withURLs.settings, meta: urlMeta, replacingUnreadable: false)
    equal(ConnectionStore.load(urlMeta).settings, withURLs.settings, "both survive a save")
    equal(ConnectionStore.parse(Data(#"{"services":[]}"#.utf8)).settings.signInURL, "", "a file from before them still opens, with them unset")
    for bad in ["example.test", "ftp://example.test", "https://", "https:// example.test", "javascript:alert(1)"] {
        check(ConnectionCheck.playerURL(bad) == nil, "not a player address: '\(bad)'")
    }
    p = FakeConnectionProbe()
    let unset = await ConnectionCheck.runURL("", probe: p, outside: true)
    check(unset.health == .off && unset.summary == "Not set." && p.asked.isEmpty, "unset: says so, and nothing is asked")
    p = FakeConnectionProbe()
    let quiet = await ConnectionCheck.runURL("https://map.example.test", probe: p, outside: false)
    check(quiet.health == .unknown && p.asked.isEmpty, "the quiet check never fetches it")
    let notURL = await ConnectionCheck.runURL("map.example.test", probe: p, outside: true)
    equal(notURL.health, .notReady, "an address without https:// is not ready")
    let plainHTTP = await ConnectionCheck.runURL("http://map.example.test", probe: p, outside: false)
    check(plainHTTP.health == .warning && plainHTTP.summary.contains("https"), "plain http is flagged even before checking")
    for (code, health, label) in [(200, ConnectionHealth.ready, "a page"), (401, .ready, "a sign-in prompt"), (403, .ready, "a refusal to strangers"),
                                  (404, .warning, "not found"), (502, .notReady, "a proxy error"), (nil, .notReady, "no answer")] as [(Int?, ConnectionHealth, String)] {
        p = FakeConnectionProbe()
        if let code { p.web["https://map.example.test"] = code }
        let s = await ConnectionCheck.runURL("https://map.example.test", probe: p, outside: true)
        equal(s.health, health, "from outside, \(label) (\(code.map(String.init) ?? "none")) is \(health.title)")
    }
    p = FakeConnectionProbe(); p.web["http://map.example.test"] = 200
    equal((await ConnectionCheck.runURL("http://map.example.test", probe: p, outside: true)).health, .warning, "an http page that answers is still flagged")

    // Beside the invite code.
    let both = InviteAddress.choose(configured: "https://example.test/signin", welcomewagon: "https://example.test/signin")
    check(both.url == "https://example.test/signin" && both.note == nil, "the configured address is shown, with nothing to add when WelcomeWagon agrees")
    let differ = InviteAddress.choose(configured: "https://example.test/signin", welcomewagon: "https://old.example.test")
    check(differ.url == "https://example.test/signin" && differ.note?.contains("old.example.test") == true, "when WelcomeWagon disagrees, the configured one is shown and the other named")
    let fallback = InviteAddress.choose(configured: "", welcomewagon: "https://example.test/join")
    check(fallback.url == "https://example.test/join" && fallback.note != nil, "with none configured, WelcomeWagon's is shown and said to be WelcomeWagon's")
    let none = InviteAddress.choose(configured: " ", welcomewagon: nil)
    check(none.url == nil && none.note?.contains("only the code") == true, "with neither, the screen says so and still shows the code")

    section("Connections: the game's status ping, on real sockets")
    let request = [UInt8](MinecraftPing.request(host: "127.0.0.1", port: 25565))
    equal(request.last, 0x00, "the request ends with the status request")
    equal(Array(request.suffix(2)), [0x01, 0x00], "which is one byte long, id 0")
    let answer: [UInt8] = { let json = Array(#"{"version":{"name":"26.3","protocol":775},"description":"made up"}"#.utf8); let body = [0x00] + [UInt8(json.count)] + json; return [UInt8(body.count)] + body }()
    check(MinecraftPing.looksLikeStatus(Data(answer)), "a status answer is recognised")
    check(!MinecraftPing.looksLikeStatus(Data("HTTP/1.1 404 Not Found\r\n".utf8)), "a web answer isn't")
    check(!MinecraftPing.looksLikeStatus(Data()), "and nothing isn't")

    let real = SystemConnectionProbe()
    if !portsAllowed {
        needsPorts("Connections: the game's status ping and a plain connection, against real listeners")
    } else if let game = try? fakeListener(reply: Data(answer)), let web = try? fakeListener(reply: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n".utf8)) {
        let gp = Int(game.port!.rawValue), wp = Int(web.port!.rawValue)
        // Generous waits for the answers that should arrive: a busy run once took longer than 3 seconds (2026-11-14).
        // They return as soon as the answer comes, so a passing run isn't slower.
        let v19 = await real.minecraftStatus(host: "127.0.0.1", port: gp, timeout: 15)
        check(v19, "a server that answers the ping is seen")
        let v20 = await real.minecraftStatus(host: "127.0.0.1", port: wp, timeout: 3)
        check(!v20, "something that accepts but isn't Minecraft isn't mistaken for it")
        let v21 = await real.tcp(host: "127.0.0.1", port: wp, timeout: 15)
        check(v21, "a plain connection is seen")
        game.cancel(); web.cancel()
        try? await Task.sleep(nanoseconds: 200_000_000)
        let v22 = await real.tcp(host: "127.0.0.1", port: gp, timeout: 2)
        check(!v22, "a closed port isn't")
    } else {
        check(false, "couldn't open a listener on 127.0.0.1")
    }

    await localAnswerChecks()
    await connectionDecisionChecks()

    section("Connections: a real Keychain, with a made-up secret")
    // A throwaway keychain file, never the login Keychain (see the top of main.swift).
    let (path, _) = throwawayKeychain("connections")
    var kc: SecKeychain?
    guard SecKeychainOpen(path, &kc) == errSecSuccess, let kc else { check(false, "couldn't open the throwaway keychain"); return }
    let account = "made-up-service"
    equal(ConnectionSecrets.presence(account: account, in: kc), .missing, "a secret never saved is missing")
    do {
        try ConnectionSecrets.save("made-up-\(UUID().uuidString)", account: account, in: kc)
        equal(ConnectionSecrets.presence(account: account, in: kc), .present, "once saved it's there, found without reading it")
        try ConnectionSecrets.save("made-up-replacement", account: account, in: kc)
        equal(ConnectionSecrets.presence(account: account, in: kc), .present, "saving again replaces it")
        ConnectionSecrets.remove(account: account, in: kc)
        equal(ConnectionSecrets.presence(account: account, in: kc), .missing, "and removed it's gone")
    } catch {
        check(false, "the throwaway keychain refused a made-up secret: \(error.localizedDescription)")
    }
    check((try? ConnectionSecrets.save("", account: account, in: kc)) == nil, "an empty secret is refused")
    try? ConnectionSecrets.save("made-up-again", account: account, in: kc)
    runSecurity(["lock-keychain", path])
    check(ConnectionSecrets.presence(account: account, in: kc) != .missing, "a locked keychain isn't mistaken for a missing secret")
}

/// A listener on 127.0.0.1 that answers every connection with fixed bytes once it has read something.
func fakeListener(reply: Data) throws -> NWListener {
    guard portsAllowed else { throw AppError("a listener was asked for in a run that mustn't open ports") }
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: params)
    let queue = DispatchQueue(label: "gilamonster.fake-listener")
    listener.newConnectionHandler = { c in
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
            c.send(content: reply, completion: .contentProcessed { _ in c.cancel() })
        }
    }
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
    listener.start(queue: queue)
    guard ready.wait(timeout: .now() + 3) == .success, listener.port != nil else { listener.cancel(); throw AppError("no listener") }
    return listener
}

// MARK: - Whether the local address answers (K822)

/// A stand-in server on 127.0.0.1 over IPv4 only, made with plain sockets so nothing else decides how it binds.
/// Closing it stops the thread and frees the port. It touches nothing but its own sockets.
final class StandInServer: @unchecked Sendable {
    enum Manner { case answers(Data), dropsWithoutAnswer, neverAccepts }
    let port: Int
    private let fd: Int32
    private var fillers: [Int32] = []
    private let lock = NSLock()
    private var closed = false

    /// `port` 0 picks a free one.
    init?(_ manner: Manner, port wanted: Int = 0) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        self.fd = fd
        guard fd >= 0 else { port = 0; return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = StandInServer.loopback(port: wanted)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var backlog: Int32 = 16
        if case .neverAccepts = manner { backlog = 1 }
        guard bound == 0, listen(fd, backlog) == 0 else { close(fd); port = 0; return nil }
        var got = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &got) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        let port = Int(UInt16(bigEndian: got.sin_port))
        self.port = port
        switch manner {
        case .neverAccepts:
            // Nothing is ever accepted, so a few connections fill the queue and the next one hangs.
            for _ in 0..<12 {
                let c = socket(AF_INET, SOCK_STREAM, 0)
                guard c >= 0 else { continue }
                _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) | O_NONBLOCK)
                var to = StandInServer.loopback(port: port)
                _ = withUnsafePointer(to: &to) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(c, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
                fillers.append(c)
            }
            usleep(200_000)
        case .answers, .dropsWithoutAnswer:
            let listening = fd
            Thread.detachNewThread {
                while true {
                    let c = accept(listening, nil, nil)
                    guard c >= 0 else { return }
                    var noSignal: Int32 = 1
                    setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                    var wait = timeval(tv_sec: 1, tv_usec: 0)
                    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    let n = read(c, &buffer, buffer.count)
                    if n > 0, case let .answers(reply) = manner { reply.withUnsafeBytes { _ = write(c, $0.baseAddress, $0.count) } }
                    close(c)
                }
            }
        }
    }

    static func loopback(port: Int) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = UInt16(port).bigEndian
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        return a
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        for c in fillers { close(c) }
        shutdown(fd, SHUT_RDWR)
        close(fd)
    }
    deinit { stop() }

    /// A port on 127.0.0.1 with nothing listening: bound once to find it, then let go.
    static func freePort() -> Int? {
        guard let s = StandInServer(.dropsWithoutAnswer) else { return nil }
        let port = s.port
        s.stop()
        usleep(100_000)
        return port
    }
}

@MainActor func localAnswerChecks() async {
    guard portsAllowed else { needsPorts("Connections: a listening, dropping, late and never-accepting server on real sockets (K822)"); return }
    section("Connections: a listening server is seen as answering (K822)")
    let real = SystemConnectionProbe()
    let statusAnswer: Data = { let json = Array(#"{"version":{"name":"26.3","protocol":775},"description":"made up"}"#.utf8); let body = [0x00] + [UInt8(json.count)] + json; return Data([UInt8(body.count)] + body) }()
    func game(_ port: Int, host: String = "127.0.0.1") -> ConnectionService {
        ConnectionService(id: "play", name: "Game tunnel", provider: .other, traffic: .game, localAddress: "\(host):\(port)")
    }
    func context(_ port: Int, running: Bool = true, starting: Bool = false, proxy: Bool = false, status: Bool = true) -> ConnectionContext {
        var c = ConnectionContext(serverRunning: running, serverIP: "127.0.0.1", serverPort: port)
        c.serverStarting = starting; c.proxyProtocol = proxy; c.statusEnabled = status
        return c
    }
    func needsYou(_ service: ConnectionService, _ status: ConnectionStatus) -> [String] { ConnectionCheck.problems([service], [service.id: status]) }

    // The real case from 2026-11-26: a server with Paper's proxy-protocol on. It listens on 127.0.0.1 over IPv4 only
    // and drops a status ping that arrives without the PROXY header, so the ping gets nothing while players get in.
    guard let proxied = StandInServer(.dropsWithoutAnswer) else { check(false, "couldn't open a stand-in server on 127.0.0.1"); return }
    var status = await ConnectionCheck.run(game(proxied.port), context: context(proxied.port, proxy: true), probe: real)
    equal(status.health, .ready, "a server that listens but drops the ping, with proxy-protocol on, is ready: \(status.summary)")
    check(status.details.contains { $0.contains("is listening at 127.0.0.1:\(proxied.port)") && $0.contains("PROXY header") }, "and the details say it's listening and why no ping is sent")
    check(needsYou(game(proxied.port), status).isEmpty, "and it's kept out of Needs you")
    status = await ConnectionCheck.run(game(proxied.port), context: context(proxied.port, status: false), probe: real)
    equal(status.health, .ready, "the same with the server's status turned off: \(status.summary)")
    status = await ConnectionCheck.run(game(proxied.port), context: context(proxied.port), probe: real)
    equal(status.health, .unknown, "listening but silent to the ping, with no setting to explain it, is unknown: \(status.summary)")
    check(status.summary.contains("Couldn't tell") && needsYou(game(proxied.port), status).isEmpty, "it says it couldn't tell, and stays out of Needs you")
    let ipv6 = await real.connect(host: "::1", port: proxied.port, timeout: 2)
    equal(ipv6, .refused, "the stand-in really is IPv4 only: ::1 is refused")
    status = await ConnectionCheck.run(game(proxied.port, host: "localhost"), context: context(proxied.port, proxy: true), probe: real)
    equal(status.health, .ready, "a tunnel written as localhost still finds the IPv4-only server: \(status.summary)")
    proxied.stop()

    let fake = FakeConnectionProbe(); fake.answering = ["127.0.0.1:25565"]
    var proxyContext = ConnectionContext(serverRunning: true, serverIP: "127.0.0.1", serverPort: 25565); proxyContext.proxyProtocol = true
    _ = await ConnectionCheck.run(game(25565), context: proxyContext, probe: fake)
    check(fake.asked.contains("tcp 127.0.0.1:25565") && !fake.asked.contains { $0.hasPrefix("ping") }, "with proxy-protocol on, no status ping is sent to the server at all")

    guard let answering = StandInServer(.answers(statusAnswer)) else { check(false, "couldn't open a stand-in server on 127.0.0.1"); return }
    status = await ConnectionCheck.run(game(answering.port), context: context(answering.port), probe: real)
    equal(status.health, .ready, "an IPv4-only server that answers the ping is ready: \(status.summary)")
    check(status.details.contains("The server answers at 127.0.0.1:\(answering.port)."), "and says it answers")
    answering.stop()

    section("Connections: refused, timed out and still starting (K822)")
    guard let closedPort = StandInServer.freePort() else { check(false, "couldn't find a free port"); return }
    let closedAnswer = await real.connect(host: "127.0.0.1", port: closedPort, timeout: 2)
    equal(closedAnswer, .refused, "a port with nothing on it is refused, not timed out")
    status = await ConnectionCheck.run(game(closedPort), context: context(closedPort), probe: real)
    equal(status.health, .notReady, "a running server with nothing listening where the tunnel points: not ready")
    check(status.summary.contains("Nothing is listening at 127.0.0.1:\(closedPort)") && needsYou(game(closedPort), status).count == 1, "it says so, and that one is in Needs you")
    status = await ConnectionCheck.run(game(closedPort), context: context(closedPort, running: false), probe: real)
    equal(status.health, .warning, "a stopped server is still a warning")

    // A delayed start: checked while the server loads, then again once it listens.
    status = await ConnectionCheck.run(game(closedPort), context: context(closedPort, running: false, starting: true), probe: real)
    equal(status.health, .unknown, "while the server is starting, a closed port is unknown: \(status.summary)")
    check(status.summary.contains("still starting") && needsYou(game(closedPort), status).isEmpty, "it says the server is starting, and stays out of Needs you")
    if let late = StandInServer(.answers(statusAnswer), port: closedPort) {
        status = await ConnectionCheck.run(game(closedPort), context: context(closedPort), probe: real)
        equal(status.health, .ready, "checked again once it listens, the same address is ready: \(status.summary)")
        late.stop()
    } else {
        check(false, "couldn't start the stand-in server late on its port")
    }

    // A timeout: the queue is full and nothing is accepted, so a new connection gets no answer either way.
    if let stuck = StandInServer(.neverAccepts) {
        let started = Date()
        let answer = await real.connect(host: "127.0.0.1", port: stuck.port, timeout: 1)
        equal(answer, .undecided("no answer within 1 second"), "a connection that gets no answer in time is undecided")
        check(Date().timeIntervalSince(started) < 4, "and the wait ends at its limit")
        status = await ConnectionCheck.run(game(stuck.port), context: context(stuck.port), probe: real)
        equal(status.health, .unknown, "a check that timed out is unknown, never not ready: \(status.summary)")
        check(status.summary.hasPrefix("Couldn't check 127.0.0.1:\(stuck.port)") && needsYou(game(stuck.port), status).isEmpty, "it says it couldn't check, and stays out of Needs you")
        let web = ConnectionService(id: "pack", name: "Pack server", provider: .other, traffic: .web, localAddress: "127.0.0.1:\(stuck.port)")
        status = await ConnectionCheck.run(web, context: context(25565), probe: real)
        equal(status.health, .unknown, "the same for a web service")
        stuck.stop()
    } else {
        check(false, "couldn't open the stand-in that never accepts")
    }
    let webClosed = ConnectionService(id: "pack", name: "Pack server", provider: .other, traffic: .web, localAddress: "127.0.0.1:\(closedPort)")
    status = await ConnectionCheck.run(webClosed, context: context(25565), probe: real)
    equal(status.health, .warning, "a web service with nothing listening is still a warning")


}

/// The K822 decisions that need no socket: an undecided probe, what Needs you lists, and Paper's proxy-protocol setting.
/// They stay in the default run; the parts on real sockets above run with --with-ports (K817).
@MainActor func connectionDecisionChecks() async {
    func game(_ port: Int, host: String = "127.0.0.1") -> ConnectionService {
        ConnectionService(id: "play", name: "Game tunnel", provider: .other, traffic: .game, localAddress: "\(host):\(port)")
    }
    func context(_ port: Int) -> ConnectionContext { ConnectionContext(serverRunning: true, serverIP: "127.0.0.1", serverPort: port) }
    let odd = FakeConnectionProbe(); odd.undecided = ["127.0.0.1:25565": "network is down"]
    let status = await ConnectionCheck.run(game(25565), context: context(25565), probe: odd)
    check(status.health == .unknown && status.summary == "Couldn't check 127.0.0.1:25565: network is down.", "any other error is unknown, with the reason: \(status.summary)")

    // Needs you takes only what was checked and found wanting.
    let services = [game(1), ConnectionService(id: "b", name: "B", provider: .other, traffic: .web), ConnectionService(id: "c", name: "C", provider: .other, traffic: .web),
                    ConnectionService(id: "d", name: "D", provider: .other, traffic: .web, enabled: false), ConnectionService(id: "e", name: "E", provider: .other, traffic: .web)]
    let listed = ConnectionCheck.problems(services, ["play": ConnectionStatus(.unknown, "Couldn't check."), "b": ConnectionStatus(.notReady, "Down."),
                                                     "c": ConnectionStatus(.warning, "Look."), "d": ConnectionStatus(.notReady, "Off anyway.")])
    equal(listed, ["B: Down.", "C: Look."], "Needs you lists not ready and needs a look, and leaves out unknown, turned off and not checked yet")

    section("Connections: Paper's proxy-protocol setting")
    check(PaperGlobalSettings.proxyProtocol("proxies:\n  bungee-cord:\n    online-mode: true\n  proxy-protocol: true\n  velocity:\n    enabled: false\n"), "proxy-protocol: true under proxies is read")
    check(!PaperGlobalSettings.proxyProtocol("proxies:\n  bungee-cord:\n    online-mode: true\n  proxy-protocol: false\n"), "false is read as off")
    check(!PaperGlobalSettings.proxyProtocol("proxies:\n  # proxy-protocol: true\n  velocity:\n    proxy-protocol: true\nother:\n  proxy-protocol: true\n"), "a comment, a deeper key and another section don't count")
    check(PaperGlobalSettings.proxyProtocol("_version: 31\nproxies:\n    proxy-protocol: \"true\" # on\n"), "other indents, quotes and a trailing comment are fine")
    check(!PaperGlobalSettings.proxyProtocol(""), "no file means off")
}
