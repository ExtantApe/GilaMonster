import Foundation
import GilaMonsterCore

/// How deep in braces each line that makes `card` sits, counted from the opening of `opener`'s closure. 1 means the
/// card is drawn straight in that closure, with no `if` around it.
func braceDepths(of card: String, after opener: String, in source: String) -> [Int] {
    var depth = 0
    var started = false
    var found: [Int] = []
    for line in source.components(separatedBy: "\n") {
        if !started {
            guard line.contains(opener) else { continue }
            started = true
        } else if line.contains(card) {
            found.append(depth)
        }
        depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
        if started, depth <= 0 { break }
    }
    return found
}

/// The Hosting card on Resource Packs (K812). It was drawn only when the library had a pack, so a server whose pack
/// is an exact file showed no Serving badge and no way to change "Only players joining this server".
@MainActor func packCardChecks() async {
    section("Resource Packs: the Hosting card shows with an empty library")
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    func source(_ name: String) -> String { (try? String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)) ?? "" }

    equal(braceDepths(of: "Card(", after: "Page(", in: "Page(x) {\n    if a {\n        if b {\n            Card(1)\n        }\n    }\n    Card(2)\n}\nCard(3)"), [3, 1],
          "the depth reader counts the ifs around a card, and stops at the end of the closure")

    let page = source("ResourcePacksPage.swift")
    let hosting = braceDepths(of: "PackHostingCard(", after: #"Page(title: "Resource Packs""#, in: page)
    equal(hosting, [1], "the page draws the Hosting card once, with no condition on the library around it")
    let publish = braceDepths(of: "PackPublishCard(", after: #"Page(title: "Resource Packs""#, in: page)
    check(!publish.isEmpty && publish.allSatisfy { $0 == 1 } && page.contains("if publishFirst, !packs.isEmpty { PackPublishCard(") && page.contains("if !publishFirst, !packs.isEmpty { PackPublishCard("),
          "publishing still needs a library pack, and still comes first once its folder is set")

    let card = source("PackHostingCard.swift")
    equal(braceDepths(of: "serving", after: #"Card(title: "Hosting""#, in: card).first, 1, "the card always draws its serving row")
    check(card.contains(#"Badge(text: "Serving", tone: .good)"#), "which has the Serving badge")
    check(card.contains(#"Text("Only players joining this server")"#) && card.contains("try server.setPackJoiningOnly(on)"), "and the switch for only players joining, which saves the choice")
    check(card.contains("+ ResourcePacks.exactNames()"), "and its rows include every exact pack, whatever the library holds")
    check(card.contains(#"Button("Add an Exact Pack…")"#), "Add an Exact Pack is on this card, so it has to be reachable before any pack exists")

    // What the switch does, on a server that has only ever had an exact pack.
    do {
        let root = folder("pack-card")
        write("server-port=25597\n", root.appendingPathComponent("server.properties"))
        let c = try await ServerController.adopt(root: root, name: "pack-card")
        check(c.packHostSettings.joiningOnly, "only players joining starts on")
        try c.setPackJoiningOnly(false)
        check(!c.packHostSettings.joiningOnly, "switching it off is saved")
        check(ServerController.open(root: root)?.packHostSettings.joiningOnly == false, "and is still off when the server is opened again")
        try c.setPackJoiningOnly(true)
        check(c.packHostSettings.joiningOnly, "switching it back on is saved")
    } catch { check(false, "the pack card's server: \(error)") }
}
