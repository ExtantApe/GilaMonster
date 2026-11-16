import Foundation
@testable import LeafJuiceCore

/// Typed slots and the self-sorting list in session access (K679, 2026-11-16).
@MainActor func commandPatternChecks() {
    section("Session access: commands with typed slots")
    let list = ["rewild why {world} {int} {int}", "rewild scan {world}", "mayor check {player} {player}", "list"]
    let worlds = ["world", "made_up_nether", "Creative-2"]
    func allowed(_ c: String, worlds w: [String]? = worlds) -> Bool { SessionAccess.allows(SessionAccess.normalize(c), entries: list, worlds: w) }

    check(allowed("rewild why world 120 -64"), "a pattern filled with the right types is allowed")
    check(allowed("/rewild   scan made_up_nether"), "with a slash and extra spaces too")
    check(allowed("mayor check MadeUp_Fox Sample42"), "two player names")
    check(allowed("list"), "exact entries still work alongside patterns")
    for (bad, label) in [
        ("rewild why world 120 -64;op MadeUp", "a semicolon"), ("rewild why world 120 -64 | op MadeUp", "a pipe and extra words"),
        ("rewild scan world extra", "an extra word"), ("rewild scan", "a missing slot"), ("rewild why world 1.5 2", "a number that isn't whole"),
        ("rewild why world 12x 2", "letters in a number"), ("rewild why world 1234567890 2", "a number too long"),
        ("rewild scan /world", "a slash in a world"), ("rewild scan ../world", "a path in a world"), ("rewild scan .hidden", "a dot-file for a world"),
        ("rewild scan nowhere", "a world the server doesn't have"), ("mayor check MadeUp;x Sample42", "a semicolon in a player"),
        ("mayor check ab Sample42", "a player name too short"), ("mayor check MadeUpNameMuchTooLong Sample42", "a player name too long"),
        ("mayor check Made-Up Sample42", "a dash in a player name"), ("mayor check @a Sample42", "a selector for a player"),
        ("Rewild scan world", "the command in other letters"), ("rewild  scan world\u{00A0}x", "a non-breaking space"),
        ("rewild scan {world}", "the pattern itself"), ("rewild scan wörld", "a non-ASCII world"),
    ] {
        check(!allowed(bad), "refused: \(label)")
    }
    check(allowed("rewild scan anything_shaped", worlds: nil), "before a server is chosen, a world only has to look like one")
    check(!allowed("rewild scan anything_shaped"), "and the server's real worlds decide after")

    var on = SessionAccessSettings(); on.enabled = true; on.commands = list
    let token = "made-up-token-0123456789abcdef"
    func decide(_ command: String) -> Result<SessionAccess.Call, SessionAccess.Refusal> {
        let body = try! JSONSerialization.data(withJSONObject: ["token": token, "caller": "Made-up Session", "call": "run", "command": command])
        return SessionAccess.authorize(body, settings: on, token: token).1
    }
    equal(decide("rewild why world 1 -2"), .success(.run(command: "rewild why world 1 -2")), "authorize lets a filled pattern through")
    equal(decide("rewild why world 1 -2\nop MadeUp"), .failure(.lineBreak), "a second command after a line break: refused")
    if case .failure(.notOnList) = decide("rewild why world 1 -2 && op MadeUp") { check(true, "refused at authorize: chained commands") } else { check(false, "refused at authorize: chained commands") }

    for pattern in ["lp user {player} permission set x", "op {player}", "deop {player}", "whitelist add {player}", "ban {player}",
                    "pardon {player}", "kick {player}", "stop {int}", "rewild approve {world}", "minecraft:op {player}", "luckperms user {player} info",
                    "tp {player} {player}", "give {player} diamond {int}"] {
        check(SessionAccess.problem(adding: pattern) != nil, "a pattern for a write command is refused: \(pattern)")
    }
    for bad in ["{player} kick", "rewild scan {worlds}", "rewild scan x{world}", "rewild scan {world", "rewild scan"] where bad != "rewild scan" {
        check(SessionAccess.problem(adding: bad) != nil, "a malformed pattern is refused: \(bad)")
    }
    check(SessionAccess.problem(adding: "rewild scan") == nil, "a plain command still goes on as written")
    for good in list { check(SessionAccess.problem(adding: good) == nil, "allowed on the list: \(good)") }
    check(!SessionAccess.allows("rewild scan world", entries: ["rewild scan {worlds}"], worlds: nil), "a malformed pattern saved by hand allows nothing")
    equal(CommandPattern.example("rewild why {world} {int} {int}"), "rewild why world 120 -64", "Settings shows an example")
    equal(CommandPattern.example("mayor check {player} {player}"), "mayor check MadeUp_Fox Sample42", "with two different players")

    section("Session access: the list sorts itself")
    let big = [
        "welcomewagon reload", "save-all", "list", "tps", "mspt", "rewild scan {world}", "rewild why {world} {int} {int}", "rewild status",
        "rewild reload", "mayor check {player} {player}", "mayor list", "mayor reload", "sheriff status", "sheriff reload", "packmule status",
        "packmule check", "packmule reload", "bluemap reload", "bluemap", "waycave list", "waycave reload", "sundial status", "lanterngraves list",
        "lanterngraves reload", "fieldnotes status", "paper version", "minecraft:seed", "spark tps", "OneVoid status",
    ]
    equal(big.count, 29, "a list the size of the owner's")
    let groups = CommandPattern.grouped(big.shuffled(), plugins: ["WelcomeWagon", "Rewild", "Mayor", "Sheriff", "Packmule", "BlueMap", "Waycave", "Sundial", "LanternGraves", "FieldNotes", "OneVoid"])
    equal(groups.first?.name, "Server", "Server comes first")
    equal(groups.first?.entries, ["list", "minecraft:seed", "mspt", "paper version", "save-all", "spark tps", "tps"], "vanilla and Paper commands sit in Server, alphabetically")
    equal(groups.dropFirst().map(\.name), ["BlueMap", "FieldNotes", "LanternGraves", "Mayor", "OneVoid", "Packmule", "Rewild", "Sheriff", "Sundial", "Waycave", "WelcomeWagon"], "then plugins alphabetically, by their proper names")
    equal(groups.first { $0.name == "Rewild" }?.entries, ["rewild scan {world}", "rewild status", "rewild why {world} {int} {int}", "rewild reload"], "read-only first, then reloads, patterns included")
    equal(groups.first { $0.name == "Packmule" }?.entries, ["packmule check", "packmule status", "packmule reload"], "alphabetical inside each")
    equal(groups.flatMap(\.entries).sorted(), big.sorted(), "nothing lost or doubled")
    equal(CommandPattern.grouped(big, plugins: []).map(\.name).contains("rewild"), true, "an unknown plugin is grouped under its command")
    equal(CommandPattern.grouped([]), [], "an empty list has no groups")
}
