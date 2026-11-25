import Foundation
import GilaMonsterCore

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
    // Plugin source badges (owner, 2026-11-15): each source tinted, with its words and icon held to WCAG on the tint.
    check(Palette.sources.count == SourceKind.allCases.count - 1, "every source but None has badge colours")
    let tints = Palette.sources.map { $0.wash.light }
    check(Set(tints).count == tints.count, "each source has its own tint")
    equal(PluginSource.modrinth(project: "luckperms", allowBeta: false).spoken, "Source Modrinth, ID luckperms", "VoiceOver reads a source as one phrase")
    check(PluginSource.github(repo: "made-up/plugin", assetPattern: "", prereleases: false).badge! == ("GitHub", "made-up/plugin"), "GitHub releases show the repository")
    check(PluginSource.jenkins(jobURL: "https://ci.example.com/job/Folder/job/Plugin/", artifactPattern: "").badge! == ("Jenkins", "ci.example.com/Plugin"), "a Jenkins job shows its host and job name")
    check(PluginSource.spigot(resourceID: 1234).badge! == ("SpigotMC", "#1234") && PluginSource.none.badge == nil, "SpigotMC shows its number, and no source shows no badges")
    check(PluginSource.modrinth(project: "", allowBeta: false).badge == nil && PluginSource.modrinth(project: "", allowBeta: false).spoken == "No source", "a half-filled source shows as no source, with no empty ID badge")
    // Sizes read as numbers (UX audit finding 10): "0 KB", never "Zero KB".
    check(!Format.bytes(0).lowercased().contains("zero") && Format.bytes(0).contains("0"), "a size of nothing reads as a number (\(Format.bytes(0)))")
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
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster/AppModel.swift")
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

/// The Theme setting (owner, 2026-11-23: "Looks good, Bold default (Recommended)"): Bold by default, Quiet remembered,
/// and anything else saved reads as Bold. Both flavors are held to WCAG by paletteChecks.
@MainActor func themeChoiceChecks() {
    section("Theme setting: Bold by default, and remembered")
    guard let (defaults, suite) = scratchDefaults("theme") else { check(false, "a scratch settings domain"); return }
    defer { removeScratchSuite(suite) }
    equal(ThemeChoice.load(defaults), .bold, "nothing saved means Bold")
    ThemeChoice.save(.quiet, defaults)
    equal(ThemeChoice.load(defaults), .quiet, "Quiet is remembered")
    equal(defaults.string(forKey: ThemeChoice.key), "quiet", "it's saved under the documented key")
    defaults.set("loud", forKey: ThemeChoice.key)
    equal(ThemeChoice.load(defaults), .bold, "an unknown value reads as Bold")
    ThemeChoice.save(.bold, defaults)
    equal(ThemeChoice.load(defaults), .bold, "Bold is remembered")
    check(Palette.Flavor.allCases.count == 2, "two flavors, both checked for contrast")
    check(Palette.accent.hex(.light, .bold) != Palette.accent.hex(.light, .quiet) || Palette.pop.hex(.light, .bold) != Palette.pop.hex(.light, .quiet), "Bold and Quiet differ")
}

/// Every view takes its colors from Theme, so a theme change reaches everything and Increase Contrast is followed.
/// Reads the app's own source: a color written straight into a view fails, unless its line says theme-exempt and why.
@MainActor func noHardCodedColorChecks() {
    section("Views take every color from the theme")
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { check(false, "the app's source is readable"); return }
    let pattern = try! NSRegularExpression(pattern: #"Color\((red|white|hue|\.sRGB)|NSColor\((srgbRed|red|white|calibrated|deviceRed)|Color\.(red|green|blue|orange|yellow|pink|purple|gray|black|white|teal|mint|cyan|indigo|brown)\b|\((\.red|\.green|\.blue|\.orange|\.yellow|\.pink|\.purple|\.gray|\.black|\.white|\.teal|\.mint|\.cyan|\.indigo|\.brown)\)|NSColor\.system[A-Z]"#)
    var found: [String] = []
    var swiftFiles = 0
    for file in files where file.pathExtension == "swift" && file.lastPathComponent != "Theme.swift" {
        swiftFiles += 1
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where !line.contains("theme-exempt") {
            let s = String(line)
            if pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { found.append("\(file.lastPathComponent):\(n + 1)") }
        }
    }
    check(swiftFiles > 20, "read the app's views (\(swiftFiles) files)")
    check(found.isEmpty, "no view writes a color of its own: \(found.joined(separator: ", "))")
    let sample = "x.foregroundStyle(.orange)"
    check(pattern.firstMatch(in: sample, range: NSRange(sample.startIndex..., in: sample)) != nil, "the rule catches a named color")
}

/// K728: the Quit question names every server it stops and what else goes with the app.
@MainActor func quitWordingChecks() {
    section("Quit question: names what stops, Keep Running is the default")
    let one = QuitWording.make(running: ["made-up-server"], leftOver: [], packHost: true, sessionAccess: true)
    equal(one.title, "Quitting stops made-up-server.", "one server is named in the title")
    equal(one.stopButton, "Stop made-up-server and Quit", "the stop button names it too")
    check(one.detail.contains("The resource pack downloads and session access stop with the app too."), "says the pack host and session access stop")
    check(one.detail.contains("close the window instead"), "says how to keep everything running")
    let two = QuitWording.make(running: ["made-up-server", "second-server"], leftOver: [], packHost: false, sessionAccess: false)
    equal(two.title, "Quitting stops 2 servers.", "two servers are counted")
    check(two.detail.contains("Running: made-up-server and second-server."), "and listed by name")
    check(!two.detail.contains("stop with the app too"), "nothing else is mentioned when nothing else runs")
    let left = QuitWording.make(running: ["a"], leftOver: ["b"], packHost: false, sessionAccess: true)
    check(left.detail.contains("Running: a and b.") && left.detail.contains("b was left running"), "servers left running are named")
    check(left.detail.contains("Session access stop"), "session access alone is named")
    // The alert itself: Keep Running is the first button and takes Return; Stop is never the default.
    let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster/AppModel.swift")
    let text = (try? String(contentsOf: src, encoding: .utf8)) ?? ""
    check(text.contains("let keep = alert.addButton(withTitle: \"Keep Running\")\n        keep.keyEquivalent = \"\\r\""), "Keep Running is first and takes Return")
    check(text.contains("stop.keyEquivalent = \"\"") && text.contains("guard alert.runModal() == .alertSecondButtonReturn"), "only a click on Stop quits")
    check(!text.contains("Stop running servers and quit?"), "the old one-keypress question is gone")
}

/// Link buttons (Show Details, Show More, Show All, Need More Time) are ink with an underline and a symbol, so the color
/// pair is ink on each background they sit on: the page and cards, the profile cards, and the four callout washes.
@MainActor func linkButtonColorChecks() {
    section("Colors: link buttons (ink) on every background they sit on")
    for bg in ["background", "surface", "raised", "accentWash", "warningWash", "dangerWash", "infoWash"] {
        let pair = Palette.pairs.first { $0.foreground == "ink" && $0.background == bg && $0.use == .text }
        check(pair != nil, "ink on \(bg) is held to 4.5:1 in the palette checks")
        let weak = Palette.failures().filter { $0.pair.foreground == "ink" && $0.pair.background == bg }
        check(weak.isEmpty, "ink on \(bg) passes in every appearance and every color vision")
    }
}
