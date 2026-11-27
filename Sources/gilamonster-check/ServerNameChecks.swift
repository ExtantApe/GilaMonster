import Foundation
@testable import GilaMonsterCore

/// The name shown for a server (K824; owner, 2026-11-26: "MOTD, editable"): the owner's name, then the server
/// message without its codes, then the folder. Made-up names only, in the suite's own temp folder.
@MainActor func serverNameChecks() async {
    section("Server name: from the server message")
    equal(ServerName.fromMessage("§2§lMade-up Realms"), "Made-up Realms", "colour and bold codes are removed")
    equal(ServerName.fromMessage("§x§1§2§3§a§b§cMade-up §x§F§F§0§0§9§9Realms§r"), "Made-up Realms", "hex colours (§x and six §-digits) are removed whole")
    equal(ServerName.fromMessage("§6Made-up Realms\n§7Come and build"), "Made-up Realms", "only the first line")
    equal(ServerName.fromMessage("   §6§l  Made-up   Realms  §r  "), "Made-up Realms", "padding used to centre the message is trimmed")
    equal(ServerName.fromMessage("&aMade-up &lRealms"), "Made-up Realms", "the & codes the Configs page already treats as codes")
    equal(ServerName.fromMessage("Made-up Realms§"), "Made-up Realms", "a § left alone at the end goes too")
    equal(ServerName.fromMessage("Pebble & Moss"), "Pebble & Moss", "an ordinary & stays")
    equal(ServerName.fromMessage(""), nil, "empty: no name")
    equal(ServerName.fromMessage("   "), nil, "only spaces: no name")
    equal(ServerName.fromMessage("§a§l§r"), nil, "only codes: no name")
    equal(ServerName.fromMessage("\nMade-up Realms"), nil, "an empty first line: no name, the second line isn't used")
    equal(ServerName.fromMessage("A Minecraft Server"), nil, "the default message names nothing")
    equal(ServerName.fromMessage("§fa minecraft server"), nil, "the default, however it's coloured or cased")
    let forty = String(repeating: "Made-up ", count: 5).trimmingCharacters(in: .whitespaces) + "!"   // 40 characters
    equal(forty.count, 40, "the fixture is 40 characters")
    equal(ServerName.fromMessage(forty), forty, "40 characters is still a name")
    equal(ServerName.fromMessage(forty + "!"), nil, "41 is a sentence, so no name")
    equal(ServerName.fromMessage("§2" + forty), forty, "codes don't count towards the length")

    equal(ConfigForm.plainMOTD("§x§1§a§7§f§3§c§lMade-up Realms§r\n§7Come and build"), "Made-up Realms Come and build", "the Connect card's server message loses hex colours too")

    section("Server name: only the motd line of server.properties")
    let file = "#Minecraft server properties\nrcon.password=made-up-secret\nmotd=\\u00A72\\u00A7lMade-up Realms\\n\\u00A77Second line\nmanagement-server-secret=another-made-up-secret\n"
    equal(ServerName.message(inProperties: file), "§2§lMade-up Realms\n§7Second line", "\\u and \\n escapes become characters, as Minecraft reads them")
    equal(ServerName.message(inProperties: file).flatMap(ServerName.fromMessage), "Made-up Realms", "and the name comes out plain")
    check(ServerName.message(inProperties: file)?.contains("secret") == false, "nothing from any other line comes back")
    equal(ServerName.message(inProperties: "motd = Pebble\\: Moss \\= Fern\\\\\n"), "Pebble: Moss = Fern\\", "escaped separators and backslashes")
    equal(ServerName.message(inProperties: "motd:Made-up\\\n    Realms\nmax-players=20"), "Made-upRealms", "a line carried on with a backslash")
    equal(ServerName.message(inProperties: "motd=one\r\nmotd=two\r\n"), "two", "the last motd wins, as in Java")
    equal(ServerName.message(inProperties: "#motd=commented\nmotd-extra=other\nserver-port=25565\n"), nil, "no motd key: nothing")
    equal(ServerName.message(inProperties: "motd=\n"), "", "an empty motd reads as empty")

    section("Server name: the owner's name, then the message, then the folder")
    equal(ServerName.resolve(custom: "Pebble Garden", message: "Made-up Realms", folder: "survival"), "Pebble Garden", "the owner's name beats the server message")
    equal(ServerName.resolve(custom: nil, message: "Made-up Realms", folder: "survival"), "Made-up Realms", "no name of theirs: the server message")
    equal(ServerName.resolve(custom: "  ", message: nil, folder: "survival"), "survival", "neither: the folder")
    equal(ServerName.folderLine(display: "Made-up Realms", folder: "survival"), "Folder: survival", "the folder stays visible under another name")
    equal(ServerName.folderLine(display: "survival", folder: "survival"), nil, "and isn't repeated under itself")
    equal(ServerName.subtitle(software: "Paper 26.3", display: "Made-up Realms", folder: "survival"), "survival · Paper 26.3", "the window's subtitle carries the folder too")
    equal(ServerName.subtitle(software: "Paper 26.3", display: "survival", folder: "survival"), "Paper 26.3", "unless the title already says it")

    section("Server name: under the icon and in the switcher")
    equal(ServerName.sidebarLines("Pebble"), ["Pebble"], "a short name sits on one line")
    equal(ServerName.sidebarLines("Made-up Realms"), ["Made-up", "Realms"], "a two-word name wraps between its words")
    equal(ServerName.sidebarLines("Riverbend Mountain"), ["Riverbend", "Mountain"], "a long two-word name wraps, with no cut inside a word")
    equal(ServerName.sidebarLines("Fern Hollow Creative"), ["Fern", "Hollow…"], "three words that don't fit: the whole words that do, then an ellipsis")
    equal(ServerName.sidebarLines("The Pebble Garden Of Moss"), ["The Pebble", "Garden…"], "a long name is cut after a whole word on the second line")
    equal(ServerName.sidebarLines("Supercalifragilistic"), ["Superca…"], "one very long word is cut once, at its end")
    equal(ServerName.sidebarLines("Supercalifragilistic Realms"), ["Superca…"], "and so is a name that starts with one")
    equal(ServerName.sidebarLines("Moss Supercalifragilistic"), ["Moss…"], "a long second word is left off whole")
    equal(ServerName.sidebarLines(""), [], "no name, no lines")
    for name in ["Pebble", "Made-up Realms", "Riverbend Mountain", "Fern Hollow Creative", "The Pebble Garden Of Moss", "Supercalifragilistic", "Moss Supercalifragilistic", "A B C D E F G H I J K L"] {
        let lines = ServerName.sidebarLines(name)
        check(lines.count <= 2 && lines.dropLast().allSatisfy { $0.count <= ServerName.sidebarLine } && (lines.last?.count ?? 0) <= ServerName.sidebarLine - 2,
              "\(name): at most two lines, each within its room, the last leaving room for the arrow (\(lines))")
        let words = Set(name.split(separator: " ").map(String.init))
        check(lines.joined(separator: " ").split(separator: " ").allSatisfy { words.contains($0.replacingOccurrences(of: "…", with: "")) || lines.count == 1 && $0.hasSuffix("…") },
              "\(name): every word shown is a whole word of the name, or the one cut word (\(lines))")
    }
    equal(ServerName.switcherSpoken(display: "Made-up Realms", folder: "survival", state: "Running"), "Made-up Realms, folder survival, Running", "a switcher row is read with its folder")
    equal(ServerName.switcherSpoken(display: "lab", folder: "lab", state: "Stopped", lab: true), "lab, folder lab, the Lab's server for this run, Stopped", "the Lab's row says what it is")
    equal(ServerName.switcherButtonSpoken(display: "The Pebble Garden Of Moss", folder: "survival", state: "Running"), "Server: The Pebble Garden Of Moss, folder survival, Running. Switch server.",
          "the button's tooltip and VoiceOver label carry the whole name, however the label is cut")
    equal(ServerName.switcherButtonSpoken(display: "survival", folder: "survival", state: "Stopped"), "Server: survival, Stopped. Switch server.", "without repeating a folder that is the name")

    section("Server name: on a server")
    do {
        let root = folder("servers/pebble-survival")
        let properties = "rcon.password=made-up-secret\nmotd=\\u00A72\\u00A7lMade-up Realms\\n\\u00A77Second line\nserver-port=25571\n"
        write(properties, root.appendingPathComponent("server.properties"))
        let c = try await ServerController.adopt(root: root, name: nil)
        defer { c.stopTicker() }
        equal(c.profile.name, "pebble-survival", "what backups and sessions go by is still the folder's name")
        equal(c.displayName, "Made-up Realms", "the name shown comes from the server message")
        equal(c.headline, "Made-up Realms is stopped.", "the headline uses it")
        equal(c.headlineSpoken, "Made-up Realms is stopped. State: Stopped.", "and so does what VoiceOver reads")
        equal(c.folderLine, "Folder: pebble-survival", "the folder name still shows")
        equal(c.editableServerMessage, "§2§lMade-up Realms\n§7Second line", "the rename sheet gets the message as typed")
        c.raiseAlert("\(c.displayName) crashed", "made-up")
        check(c.recentAlerts.contains { $0.contains("Made-up Realms crashed") }, "a notification names it the same way")

        _ = try c.rename(to: "Pebble Garden", moveFolderTo: nil)
        equal(c.displayName, "Pebble Garden", "the owner's rename beats the server message")
        equal(c.headline, "Pebble Garden is stopped.", "in the headline too")
        equal(c.folderLine, "Folder: pebble-survival", "and the folder still shows")
        let again = ServerController.open(root: root)
        equal(again?.displayName, "Pebble Garden", "the rename is kept in GilaMonster's own settings")
        again?.stopTicker()
        equal(try String(contentsOf: root.appendingPathComponent("server.properties"), encoding: .utf8), properties, "server.properties is untouched by a rename")

        c.resetDisplayName()
        equal(c.profile.customName, nil, "Reset clears the owner's name")
        equal(c.displayName, "Made-up Realms", "so the server message names it again")
        let afterReset = ServerController.open(root: root)
        equal(afterReset?.displayName, "Made-up Realms", "and the earlier name doesn't come back at the next launch")
        afterReset?.stopTicker()

        try c.setServerMessage("§bFern Hollow")
        equal(c.displayName, "Fern Hollow", "a new server message is picked up when it's saved")
        try c.setServerMessage("A Minecraft Server")
        equal(c.displayName, "pebble-survival", "the default message falls back to the folder")
        equal(c.folderLine, nil, "where the folder isn't repeated")
        try c.setServerMessage("Welcome to a made-up server that takes a whole sentence to say hello")
        equal(c.displayName, "pebble-survival", "a long message falls back to the folder")
        try c.setServerMessage("")
        equal(c.displayName, "pebble-survival", "an empty message falls back to the folder")

        // Two servers with one server message: each row still says which folder it is.
        let twinA = folder("servers/twin-one"), twinB = folder("servers/twin-two")
        for root in [twinA, twinB] { write("motd=\\u00A7aShared Message\n", root.appendingPathComponent("server.properties")) }
        let one = try await ServerController.adopt(root: twinA, name: nil), two = try await ServerController.adopt(root: twinB, name: nil)
        defer { one.stopTicker(); two.stopTicker() }
        equal([one.displayName, two.displayName], ["Shared Message", "Shared Message"], "two servers can share a server message")
        let rows = [one, two].map { ServerName.switcherSpoken(display: $0.displayName, folder: $0.folderName, state: $0.state.title) }
        equal(rows, ["Shared Message, folder twin-one, Stopped", "Shared Message, folder twin-two, Stopped"], "and both show their folder in the switcher")

        // A server named before K824: its label was the owner's, so it stays.
        let old = folder("servers/moss-creative")
        write("motd=\\u00A7dMoss Message\n", old.appendingPathComponent("server.properties"))
        write("{\"id\": \"\(UUID().uuidString)\", \"name\": \"Moss Label\"}", folder("servers/moss-creative/.gilamonster").appendingPathComponent("server.json"))
        let earlier = ServerController.open(root: old)
        defer { earlier?.stopTicker() }
        equal(earlier?.displayName, "Moss Label", "a name given before this change still beats the server message")
        check((try? String(contentsOf: old.appendingPathComponent(".gilamonster/server.json"), encoding: .utf8))?.contains("customName") == false, "opening it writes nothing")
        earlier?.resetDisplayName()
        equal(earlier?.displayName, "Moss Message", "and Reset hands it to the server message")
        equal(earlier?.profile.name, "Moss Label", "leaving what backups and sessions go by alone")
        let later = ServerController.open(root: old)
        equal(later?.displayName, "Moss Message", "and the old label doesn't come back at the next launch")
        later?.stopTicker()

        // A folder renamed while the server message names the server: the old folder name is not a label.
        let plain = folder("servers/fern-first")
        write("motd=Fern Message\n", plain.appendingPathComponent("server.properties"))
        let fern = try await ServerController.adopt(root: plain, name: nil)
        let movedTo = try fern.moveFolder(to: "fern-second")
        fern.stopTicker()
        let fernAgain = movedTo.flatMap { ServerController.open(root: $0) }
        equal(fernAgain?.displayName, "Fern Message", "a folder rename alone doesn't turn the old folder name into the owner's name")
        equal(fernAgain?.folderLine, "Folder: fern-second", "and the new folder shows")
        fernAgain?.stopTicker()
    } catch { failures.append("server name checks threw: \(error)") }

    section("Server name: where the app shows it")
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    func source(_ name: String) -> String { (try? String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    let overview = source("OverviewPage.swift")
    check(overview.contains("Text(server.headline)") && overview.contains(".accessibilityLabel(server.headlineSpoken)"), "the Overview's headline and its VoiceOver label")
    check(overview.contains("if let folder = server.folderLine"), "the folder line under the headline")
    check(overview.contains("\"Copy Folder Path\"") && overview.contains("abbreviatingWithTildeInPath") && overview.contains("\"Show in Finder\""), "Copy Folder Path and Show in Finder still go by the folder")
    let rootView = source("RootView.swift")
    check(rootView.contains(".navigationTitle(server.displayName)") && rootView.contains("ServerName.subtitle("), "the window title, with the folder in its subtitle")
    check(rootView.contains("\"Reset to Server Message\"") && rootView.contains("server.resetDisplayName()") && rootView.contains("name = server.displayName"),
          "the rename sheet: prefilled, with Reset to Server Message")
    let spine = source("DesertViews.swift")
    check(spine.contains("SymbolText(ServerName.sidebarLines(server.displayName).joined(separator: \"\\n\") + \" ▾\", .label())") && spine.contains(".lineLimit(2).truncationMode(.tail)") && !spine.contains(".truncationMode(.middle).frame(maxWidth: 70)"),
          "the name under the icon: two lines, cut at the end only")
    check(spine.components(separatedBy: "ServerName.switcherButtonSpoken(display: server.displayName, folder: server.folderName, state: server.state.title)").count == 3, "the switcher's tooltip and VoiceOver label: the whole name")
    check(spine.contains("Text(SwitcherRow.title(other))\n                        Text(other.folderName)") && spine.contains(".accessibilityLabel(SwitcherRow.spoken(other))"), "every switcher row: the name, the folder beneath it, and both read aloud")
    check(source("AppModel.swift").contains("Button(\"Start \\(server.displayName)\")"), "the menu bar")
    // Only these still go by the stored name: the Advisor's code name for a server (a check and its preview), and picture file names.
    var stray: [String] = []
    for file in (try? FileManager.default.contentsOfDirectory(atPath: app.path)) ?? [] where file.hasSuffix(".swift") {
        for (n, line) in source(file).components(separatedBy: "\n").enumerated() where line.contains(".profile.name") {
            if line.contains("display: server.profile.name") || line.contains("display = server.profile.name") || line.contains("server.profile.name.replacingOccurrences") { continue }
            stray.append("\(file):\(n + 1)")
        }
    }
    equal(stray, [], "no screen shows the stored name where the display name belongs")
}
