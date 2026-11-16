import Foundation
import LeafJuiceCore

/// WCAG AA for every pair the app draws, in all four appearances and with each common kind of color blindness.
/// This is what keeps the palette honest: change a color in Palette and CI fails if any pair drops below its minimum.
@MainActor func paletteChecks() {
    section("Colors: WCAG contrast, every pair, every appearance, every color vision")
    // The formula itself, against WCAG's own fixed points.
    check(abs(Palette.contrast(0x000000, 0xFFFFFF) - 21) < 0.01, "black on white is 21:1")
    check(abs(Palette.contrast(0x777777, 0xFFFFFF) - 4.48) < 0.01, "#777 on white is 4.48:1, just under AA")
    equal(Palette.contrast(0x123456, 0x123456), 1, "a color on itself is 1:1")
    // The simulations: gray stays gray, and red and green collapse for protanopia and deuteranopia as they should.
    for vision in Palette.Vision.allCases {
        let gray = Palette.simulate(0x808080, vision)
        check(abs(Palette.luminance(gray) - Palette.luminance(0x808080)) < 0.01, "\(vision.rawValue) keeps gray's lightness")
    }
    for vision in [Palette.Vision.protanopia, .deuteranopia] {
        func distance(_ a: UInt32, _ b: UInt32) -> Double {
            var total = 0.0
            for shift: UInt32 in [16, 8, 0] {
                let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
                total += (x - y) * (x - y)
            }
            return total.squareRoot()
        }
        let before = distance(0xCC3333, 0x339933), after = distance(Palette.simulate(0xCC3333, vision), Palette.simulate(0x339933, vision))
        check(after < before / 2, "\(vision.rawValue) brings a red and a green much closer, as it should (\(Int(before)) to \(Int(after)))")
    }
    let blue = Palette.simulate(0x2255CC, .tritanopia)
    check(blue != 0x2255CC, "tritanopia changes blue")
    // A source counts only once it's filled in (UX audit finding 5): the Add Plugin dialog opens on an empty Modrinth.
    check(!PluginSource.modrinth(project: "", allowBeta: false).isSet && !PluginSource.modrinth(project: "  ", allowBeta: false).isSet, "an empty Modrinth project isn't a source, so Add stays off")
    check(PluginSource.modrinth(project: "luckperms", allowBeta: false).isSet && PluginSource.hangar(project: "MadeUp/Plugin", channel: "Release").isSet, "a filled-in project is a source")
    check(!PluginSource.spigot(resourceID: 0).isSet && PluginSource.spigot(resourceID: 1234).isSet, "SpigotMC needs a resource number")
    check(!PluginSource.github(repo: "made-up", assetPattern: "", prereleases: false).isSet && PluginSource.github(repo: "made-up/plugin", assetPattern: "", prereleases: false).isSet, "GitHub needs owner/name")
    check(!PluginSource.jenkins(jobURL: "ci.example.com", artifactPattern: "").isSet && PluginSource.jenkins(jobURL: "https://ci.example.com/job/Plugin/", artifactPattern: "").isSet, "Jenkins needs a web address")
    check(!PluginSource.web(url: "", linkPattern: "").isSet && !PluginSource.web(url: "file:///etc/x.jar", linkPattern: "").isSet && PluginSource.web(url: "https://example.com/x.jar", linkPattern: "").isSet, "a web source needs an http or https address")
    // The real test.
    check(Palette.pairs.count >= 45, "every pair the app uses is listed (\(Palette.pairs.count))")
    let failing = Palette.failures()
    for f in failing { check(false, f.line) }
    check(failing.isEmpty, "no pair falls under WCAG AA anywhere (\(Palette.pairs.count) pairs × \(Palette.Mode.allCases.count) appearances × \(Palette.Vision.allCases.count) kinds of color vision)")
    // Fails closed: a made-up palette with a weak pair is caught.
    check(Palette.contrast(0xCDD5B6, 0xFFFEF8) < 3, "the old card border would fail as a control outline, which is why controls have their own")
}

/// The sidebar's groups: every page once, Overview on top, alphabetical within groups, and collapsed state kept.
@MainActor func sidebarChecks() {
    section("Sidebar groups")
    let keys = SidebarGroups.allKeys
    equal(keys.count, Set(keys).count, "no page appears twice")
    equal(keys.first, "overview", "Overview is on top, on its own")
    equal(SidebarGroups.groups.map(\.title), ["Server", "Content", "People", "Upkeep"], "groups in the agreed order")
    for group in SidebarGroups.groups {
        let titles = group.pages.map(\.title)
        equal(titles, titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "\(group.title) is alphabetical")
    }
    // Every page the app has, read from its own source, so a new page can't be left out of the sidebar.
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LeafJuice/AppModel.swift")
    if let text = try? String(contentsOf: source, encoding: .utf8),
       let line = text.split(separator: "\n").first(where: { $0.contains("case overview,") }) {
        let pages = Set(line.replacingOccurrences(of: "case", with: "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        equal(Set(keys), pages, "every page is in exactly one place")
    } else { check(false, "couldn't read the app's page list") }
    let upkeep = SidebarGroups.groups.first { $0.id == "upkeep" }!
    equal(SidebarGroups.rollUp(upkeep, badges: ["changes": 2, "advisor": 1, "plugins": 5]), 3, "a collapsed group's badge adds up its own pages only")
    equal(SidebarGroups.decodeCollapsed(SidebarGroups.encodeCollapsed(["people", "server"])), ["people", "server"], "collapsed groups are remembered")
    equal(SidebarGroups.decodeCollapsed("people,made-up,,server"), ["people", "server"], "and a name that isn't a group is dropped")
}

/// Why the app is quitting (K650): macOS's reason codes, and which ones nobody is there to answer.
@MainActor func quitReasonChecks() {
    section("Quitting at a shutdown, restart or log out")
    equal(QuitReason(code: QuitReason.code("shut")), .shutdown, "'shut' is a shutdown")
    equal(QuitReason(code: QuitReason.code("rest")), .restart, "'rest' is a restart")
    equal(QuitReason(code: QuitReason.code("rlgo")), .logout, "'rlgo' is a log out")
    equal(QuitReason(code: QuitReason.code("logo")), .logout, "'logo' is a log out too")
    equal(QuitReason(code: nil), .user, "no reason is a person quitting")
    equal(QuitReason(code: QuitReason.code("abcd")), .user, "and so is any other")
    check([QuitReason.shutdown, .restart, .logout].allSatisfy(\.unattended), "shutdown, restart and log out don't wait for an answer")
    check(!QuitReason.user.unattended, "a person quitting is still asked")
    equal(QuitReason.code("shut"), 0x73687574, "the four letters make the code macOS uses")
}
