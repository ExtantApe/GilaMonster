import Foundation
import GilaMonsterCore

/// The desert redesign (K786, owner's pick 2026-11-25: "B: desert base, calmed down"): sections and the trail, the
/// shortcuts, pixel glyphs, made-up faces, the Overview's words, the roster, fonts, motion, and proof that the Allow
/// prompt kept its behavior byte for byte.
@MainActor func desertChecks() {
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    let repo = app.deletingLastPathComponent().deletingLastPathComponent()
    func source(_ name: String) -> String { (try? String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)) ?? "" }

    section("Sections: five beads, every page in exactly one")
    equal(Sections.all.map(\.title), ["Home", "Server", "Content", "People", "Upkeep"], "the five sections in spine order")
    equal(Sections.all.first?.pages.map(\.key), ["overview"], "Home holds Overview alone")
    let keys = Sections.all.flatMap { $0.pages.map(\.key) }
    equal(keys.count, Set(keys).count, "no page is in two sections")
    equal(keys, SidebarGroups.allKeys, "the sections hold the same pages as the groups, in the same order")
    if let line = source("AppModel.swift").split(separator: "\n").first(where: { $0.contains("case overview,") }) {
        let pages = Set(line.replacingOccurrences(of: "case", with: "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        equal(Set(keys), pages, "every page the app has can be reached from a bead")
    } else { check(false, "couldn't read the app's page list") }
    equal(Sections.section(of: "players")?.id, "people", "Players is under People")
    equal(Sections.section(of: "configs")?.id, "server", "Configs is under Server")
    check(Sections.section(of: "made-up") == nil, "a page that doesn't exist has no section")
    equal(Sections.section(forDigit: 1)?.id, "home", "the first digit is Home")
    equal(Sections.section(forDigit: 5)?.id, "upkeep", "the fifth is Upkeep")
    check(Sections.section(forDigit: 0) == nil && Sections.section(forDigit: 6) == nil, "there's no section 0 or 6")
    equal(Sections.spoken("People", pages: 2, waiting: 0), "People, 2 pages", "VoiceOver reads a bead's word and page count")
    equal(Sections.spoken("Home", pages: 1, waiting: 0), "Home, 1 page", "one page is singular")
    equal(Sections.spoken("Content", pages: 4, waiting: 1), "Content, 4 pages, 1 waiting", "and what's waiting there")
    let trail = ["configs", "console", "lab", "launch", "software"]
    equal(Sections.step(from: "console", in: trail, by: 1), "lab", "⌃Tab moves to the next page")
    equal(Sections.step(from: "software", in: trail, by: 1), "configs", "and wraps round at the end")
    equal(Sections.step(from: "configs", in: trail, by: -1), "software", "⌃⇧Tab wraps round at the start")
    equal(Sections.step(from: "players", in: trail, by: 1), "configs", "a page off the trail goes to the first")
    check(Sections.step(from: "x", in: [], by: 1) == nil, "an empty trail goes nowhere")
    let server = Sections.all[1]
    equal(Sections.landing(server, visible: trail, last: "launch"), "launch", "a bead goes back to the page last used there")
    equal(Sections.landing(server, visible: ["console", "launch"], last: "lab"), "console", "unless that page is hidden, then the first shown")
    equal(Sections.landing(server, visible: [], last: nil), nil, "a section with nothing shown opens nothing")
    equal(Sections.badge(Sections.all[4], badges: ["changes": 2, "advisor": 1, "plugins": 5]), 3, "a bead's badge adds up its own pages only")

    section("Shortcuts: sections on ⌥⌘1 to ⌥⌘5, pages keep ⌘1 to ⌘9, nothing else lost")
    let model = source("AppModel.swift")
    func after(_ marker: String, _ length: Int = 260) -> String {
        guard let r = model.range(of: marker) else { return "" }
        return String(model[r.upperBound...].prefix(length))
    }
    check(after("ForEach(Array(Sections.all.enumerated()), id: \\.element.id)").contains(".keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])"), "⌥⌘1 to ⌥⌘5 pick a section")
    check(after("ForEach(Array(PageID.visible.enumerated()), id: \\.element)", 320).contains(".keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)"), "⌘1 to ⌘9 still open each page by number, as before the redesign")
    check(model.contains(".keyboardShortcut(.tab, modifiers: .control)") && model.contains(".keyboardShortcut(.tab, modifiers: [.control, .shift])"), "⌃Tab and ⌃⇧Tab move along the trail")
    check(model.components(separatedBy: "String(index + 1))), modifiers: [.command, .option])").count == 2 && model.components(separatedBy: "String(index + 1))), modifiers: .command)").count == 2, "each digit set is used once")
    // The shortcuts people already had, unchanged.
    for (shortcut, words) in [(".keyboardShortcut(\"n\")", "⌘N adds a server"), (".keyboardShortcut(\"r\").disabled", "⌘R starts"),
                              (".keyboardShortcut(\".\", modifiers: [.command, .control])", "⌃⌘. stops"), (".keyboardShortcut(\"r\", modifiers: [.command, .shift])", "⇧⌘R restarts"),
                              (".keyboardShortcut(\"b\", modifiers: [.command, .shift])", "⇧⌘B backs up"), (".keyboardShortcut(\"r\", modifiers: [.command, .option])", "⌥⌘R opens requests"),
                              (".keyboardShortcut(\"i\", modifiers: [.command, .option])", "⌥⌘I shows Issues")] {
        check(model.contains(shortcut), "\(words), as before")
    }
    // No other view claims a digit or ⌃Tab.
    var clashes: [String] = []
    let digit = try! NSRegularExpression(pattern: #"keyboardShortcut\("[0-9]"|keyboardShortcut\(\.tab"#)
    for file in (try? FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "swift" {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let hits = digit.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        if hits > 0, file.lastPathComponent != "AppModel.swift" { clashes.append(file.lastPathComponent) }
    }
    check(clashes.isEmpty, "no view claims a digit or ⌃Tab of its own: \(clashes.joined(separator: ", "))")

    section("Pixel status glyphs: a shape for each state, always with its word")
    for glyph in PixelGlyph.allCases {
        check(glyph.rows.count == 8 && glyph.rows.allSatisfy { $0.count == 8 }, "\(glyph.rawValue) is 8 by 8")
    }
    equal(Set(PixelGlyph.allCases.map(\.rows)).count, 4, "the four shapes all differ")
    let up = PixelGlyph.up.rows, ring = PixelGlyph.starting.rows, tri = PixelGlyph.down.rows, square = PixelGlyph.stopped.rows
    check(up[3] == "########" && up[0] == "..####..", "Up is a filled circle")
    check(ring[3] == "##....##" && ring[0] == up[0], "Starting is the same circle, hollow")
    check(tri[0].filter { $0 == "#" }.count < tri[7].filter { $0 == "#" }.count && tri[7] == "########", "Down is a triangle, widening to the bottom")
    check(square[0] == "........" && square[1...6].allSatisfy { $0 == ".######." }, "Stopped is a square")
    equal(ServerState.running.glyph, .up, "a running server shows Up")
    equal(ServerState.starting.glyph, .starting, "starting shows the ring")
    equal(ServerState.stopping.glyph, .starting, "and so does stopping")
    equal(ServerState.crashed(code: 1).glyph, .down, "a crash shows the triangle")
    equal(ServerState.stopped.glyph, .stopped, "stopped shows the square")
    let desert = source("DesertViews.swift")
    check(desert.contains("GlyphView(glyph: state.glyph)") && desert.contains("Text(state.title)"), "StateLabel draws the glyph and the state's word together")
    check(desert.contains("struct PixelGrid") && desert.contains(".accessibilityHidden(true)"), "pixel art is hidden from VoiceOver; the word is read")

    section("Made-up faces: from the name, on the Mac")
    let face = PixelFace.pixels("MadeUpKid")
    equal(face.count, 64, "a face is 8 by 8")
    equal(face, PixelFace.pixels("MadeUpKid"), "the same name gives the same face")
    let names = ["MadeUpKid", "PixelPal", "CactusJo", "SandyB", "LizardLou", "Pebble42", "NightOwlNora"]
    check(Set(names.map { PixelFace.pixels($0) }).count >= 6, "different names mostly give different faces")
    let allowed = Set(PixelFace.skins + PixelFace.hairs + PixelFace.eyes + [PixelFace.white])
    check(names.allSatisfy { PixelFace.pixels($0).filter { !allowed.contains($0) }.count == 2 }, "every pixel is from the art colors, apart from the two mouth pixels")
    equal(PixelFace.initials("MadeUpKid"), "MU", "initials take the first letter and the next capital")
    equal(PixelFace.initials("pebble42"), "P4", "or the next digit")
    equal(PixelFace.initials(""), "?", "an empty name doesn't crash")
    let core = (try? String(contentsOf: repo.appendingPathComponent("Sources/GilaMonsterCore/Sections.swift"), encoding: .utf8)) ?? ""
    check(!core.isEmpty && !core.contains("URLSession") && !core.contains("http"), "faces and art make no network calls")
    check(!source("DesertViews.swift").contains("URLSession") && !source("DesertViews.swift").contains("http"), "and neither do the views that draw them")

    section("Overview: the status sentence and the fact line")
    equal(NeedsYou.sentence(name: "Riverside", state: .running, players: 3), "Riverside is up. 3 players online.", "running with players")
    equal(NeedsYou.sentence(name: "Riverside", state: .running, players: 1), "Riverside is up. 1 player online.", "one player")
    equal(NeedsYou.sentence(name: "Riverside", state: .running, players: 0), "Riverside is up. Nobody is online.", "nobody on")
    equal(NeedsYou.sentence(name: "Riverside", state: .stopped, players: 0), "Riverside is stopped.", "stopped")
    equal(NeedsYou.sentence(name: "Riverside", state: .crashed(code: 1), players: 0), "Riverside is down. It stopped unexpectedly.", "crashed")
    let now = Date()
    equal(NeedsYou.factLine(software: "Paper 26.2", running: true, since: now.addingTimeInterval(-7200), lastBackup: nil, isLab: false, needs: 0, openIssues: 0, now: now),
          "Paper 26.2 · up for 2 hours · no GilaMonster backup yet · nothing needs you", "the fact line in plain words")
    let line = NeedsYou.factLine(software: "Paper 26.2", running: false, since: nil, lastBackup: now.addingTimeInterval(-1500), isLab: false, needs: 2, openIssues: 1, now: now)
    check(line.contains("GilaMonster backup") && line.contains("2 things need you") && line.hasSuffix("1 open issue") && !line.contains("up for"), "backups, what needs you and open issues, and no uptime when stopped (\(line))")
    check(!NeedsYou.factLine(software: "Paper", running: false, since: nil, lastBackup: nil, isLab: true, needs: 1, openIssues: 0, now: now).contains("backup"), "the Lab has no backup words")
    let overview = source("OverviewPage.swift")
    check(overview.contains("Theme.display(28)") && overview.contains("GlyphView(glyph: server.state.glyph, size: 22)"), "the sentence is in the display face beside the glyph")
    check(overview.contains("server.start()") && overview.contains("server.stop(by: .button(\"Overview\"))") && overview.contains("server.restart(by: .button(\"Overview\"))"), "Start, Stop and Restart are still on Overview")
    check(overview.contains("ConnectCheckRow") && overview.contains("Copy Network Address") && overview.contains("Back Up Now") && overview.contains("ConnectionsCard"), "every action the old cards had is still there")

    section("Players: the roster")
    func p(_ name: String, _ seen: TimeInterval?) -> PlayerInfo { PlayerInfo(uuid: UUID().uuidString, name: name, lastSeen: seen.map { now.addingTimeInterval($0) }, playTicks: nil) }
    let roster = PlayerRoster.split([p("SandyB", -100), p("PixelPal", -5), p("MadeUpKid", -1), p("LizardLou", -10), p("CactusJo", nil)], online: ["PixelPal", "MadeUpKid"])
    equal(roster.onNow.map(\.title), ["MadeUpKid", "PixelPal"], "On now comes first, by name")
    equal(roster.seenBefore.map(\.title), ["LizardLou", "SandyB", "CactusJo"], "Seen before is most recent first, never-seen last")
    let players = source("DeepViews.swift")
    check(players.contains("Theme.popText).frame(width: 4)") && players.contains("on ? Theme.raised : Color.clear"), "the selected row has an edge marker as well as its tint")
    check(players.contains("Text(\"× \\(item.count)\")"), "inventory slots show their count in text")
    check(players.contains("Filled circle: on now. Square: offline."), "the key says what each shape means")

    section("Allow prompt: restyled only, behavior byte for byte")
    let prompts = source("SessionPrompts.swift")
    // SessionAskList with its font choices taken out must be exactly the text it was before K786 (fingerprint taken
    // from main at 69f6036). Any change to wording, buttons, order, default, focus, countdown or guard changes it.
    if let start = prompts.range(of: "/// Each waiting ask with Deny and Allow.") {
        let list = String(prompts[start.lowerBound...])
        let fonts = try! NSRegularExpression(pattern: #"\.font\([^()]*(?:\([^()]*\)[^()]*)*\)"#)
        // K800 added layout only, and each piece is taken out by its exact text before hashing: `.fixedSize()` on the
        // four buttons, and the width the words' column asks for.
        let layout = [".fixedSize()", ".frame(idealWidth: 262, alignment: .leading)"]
        let bare = layout.reduce(fonts.stringByReplacingMatches(in: list, range: NSRange(list.startIndex..., in: list), withTemplate: "")) { $0.replacingOccurrences(of: $1, with: "") }
        var h: UInt64 = 0xcbf29ce484222325
        for b in bare.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        equal(String(h, radix: 16), "e23c502b945538b5", "SessionAskList is unchanged apart from its fonts and the K800 layout modifiers")
        equal(list.components(separatedBy: ".fixedSize()").count - 1, 4, "Deny, Allow, Allow for Today and Need More Time are each as wide as their label")
        for label in ["Button(\"Deny\")", "Button(\"Allow\")", "Button(\"Allow for Today\")", "Button(\"Need More Time (\\(left) left)\")"] {
            // From the button to the end of its style line. Need More Time's style comes after its action, just
            // before .disabled.
            let stop = label.contains("Need") ? ".disabled(left <= 0)" : "\n"
            var tail = ""
            if let from = list.range(of: label) {
                let rest: Substring = list[from.lowerBound...]
                if let end = rest.range(of: stop) { tail = String(rest[..<end.lowerBound]) }
            }
            check(tail.contains(".fixedSize()"), "\(label) never shrinks below its label")
        }
        check(!list.contains("truncationMode") && !list.contains("lineLimit"), "no label in the list is cut short")
        check(list.contains("}.frame(idealWidth: 262, alignment: .leading)\n                    Spacer(minLength: 12)"), "the words keep a 262 pt column beside the buttons")
    } else { check(false, "SessionAskList is in SessionPrompts.swift") }
    func at(_ s: String) -> Int { prompts.range(of: s).map { prompts.distance(from: prompts.startIndex, to: $0.lowerBound) } ?? -1 }
    let deny = at("Button(\"Deny\") { if settled() { service.resolve(ask.id, allow: false) } }")
    let allow = at("Button(\"Allow\") { if settled() { service.resolve(ask.id, allow: true) } }")
    let today = at("Button(\"Allow for Today\") { if settled() { service.resolveForToday(ask.id) } }")
    let more = at("Button(\"Need More Time (\\(left) left)\")")
    check(deny > 0 && deny < allow && allow < today && today < more, "Deny, then Allow, then Allow for Today, then Need More Time")
    check(prompts.contains(".keyboardShortcut(index == 0 && focusFirst ? .defaultAction : nil)\n                                .focused($focused, equals: ask.id)"), "Deny is the default and holds focus")
    if allow > 0, today > allow {
        let between = prompts[prompts.index(prompts.startIndex, offsetBy: allow)..<prompts.index(prompts.startIndex, offsetBy: today)]
        check(!between.contains("keyboardShortcut") && !between.contains(".focused("), "Allow is never the default and never takes focus")
    }
    check(prompts.contains("No answer in \\(left / 60):\\(String(format: \"%02d\", left % 60)) means no."), "the countdown reads as before")
    check(prompts.contains("SessionAskPlacement.accepts(pointer: pointer, sinceChange: Date().timeIntervalSince(changed))"), "the click guard is still there")
    check(prompts.contains("override func cancelOperation(_ sender: Any?) {\n            if let first = SessionAccessService.shared.waiting.first { SessionAccessService.shared.resolve(first.id, allow: false) }"), "Escape still denies")
    check(prompts.contains("AskPanelLook { SessionAskList(service: .shared, focusFirst: true) }") && prompts.contains("BeadBandView(height: 6)"), "the ask window wears the bead band and sand surface")
    check(prompts.contains(".frame(minWidth: AskPanelLook.minWidth)") && prompts.contains("static var minWidth: CGFloat { 580 }") && !prompts.contains(".frame(width: 580)"), "the ask window is 580 pt at least and grows when the buttons need more")
    check(prompts.contains("panel.contentView?.fittingSize"), "and it is sized from what its content asks for, every time it opens")
    let style = source("Theme.swift")
    check(style.contains("configuration.label\n                .lineLimit(1)\n                .fixedSize(horizontal: true, vertical: false)"), "a themed button's label is one line at its full width")
    // Fails closed: the fingerprint catches a one-word change.
    var tampered: UInt64 = 0xcbf29ce484222325
    for b in "Button(\"Allow\")".utf8 { tampered ^= UInt64(b); tampered = tampered &* 0x100000001b3 }
    check(String(tampered, radix: 16) != "e23c502b945538b5", "a different text gives a different fingerprint")

    section("Fonts: open licence only, and text at 13 pt or more")
    let fonts = repo.appendingPathComponent("brand/fonts/lilitaone")
    check(FileManager.default.fileExists(atPath: fonts.appendingPathComponent("LilitaOne-Regular.ttf").path), "Lilita One is in brand/fonts")
    let ofl = (try? String(contentsOf: fonts.appendingPathComponent("OFL.txt"), encoding: .utf8)) ?? ""
    check(ofl.contains("SIL OPEN FONT LICENSE"), "with its SIL Open Font License beside it")
    let build = (try? String(contentsOf: repo.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)) ?? ""
    check(build.contains("brand/fonts/lilitaone/LilitaOne-Regular.ttf") && build.contains("brand/fonts/lilitaone/OFL.txt") && build.contains("Contents/Resources/Fonts"), "the app bundle carries the font and its licence")
    var small: [String] = []
    let tiny = try! NSRegularExpression(pattern: #"\.(caption2?|callout|footnote|subheadline)\b|size: (9|10|11|12)\)"#)
    for file in (try? FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "swift" {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        for (n, l) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where l.contains("font") {
            let s = String(l)
            if tiny.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { small.append("\(file.lastPathComponent):\(n + 1)") }
        }
    }
    check(small.isEmpty, "no view sets text under 13 pt: \(small.joined(separator: ", "))")
    check(!desert.contains("SF Pro") && !desert.contains("\"Helvetica") && desert.contains("static let lilita = \"LilitaOne\""), "the display face is Lilita One, never a macOS font by name")

    section("Motion: Reduce Motion stops the slide and the pulse")
    check(desert.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion") && desert.contains("reduceMotion ? nil : .easeOut(duration: 0.16)") && desert.contains("reduceMotion ? .identity"), "the trail slides in over 160 ms, at once with Reduce Motion")
    check(overview.contains("guard !reduceMotion else { return }"), "the status glyph's one pulse is skipped with Reduce Motion")

    section("Spine: a tab list named Sections, beads named for VoiceOver")
    check(desert.contains(".accessibilityLabel(\"Sections\")") && desert.contains(".accessibilityAddTraits(.isTabBar)"), "the spine is a tab list named Sections")
    check(desert.contains("Sections.spoken(section.title, pages: pages, waiting: waiting)"), "each bead reads its word and page count")
    check(desert.contains(".onKeyPress(.upArrow)") && desert.contains(".onKeyPress(.downArrow)") && desert.contains(".onKeyPress(keys: [.return, .space])"), "↑↓ move between beads and Return or Space picks one")
    check(desert.contains("Theme.spineFocus, lineWidth: 2") && desert.contains("Theme.accent, lineWidth: 2"), "focus rings stay visible on the spine and the trail")
    check(desert.contains("on ? Theme.beadRing : Theme.beadEdge") && desert.contains(".bold : .regular"), "the selected bead has its cream outline and bold word, not only a color")

    section("Colors: Increase Contrast holds text to 7:1")
    equal(Palette.Use.text.minimum(.contrastLight), 7, "text needs 7:1 with Increase Contrast")
    equal(Palette.Use.ui.minimum(.contrastDark), 4.5, "controls and icons need 4.5:1 with Increase Contrast")
    equal(Palette.Use.text.minimum(.light), 4.5, "and 4.5:1 without")
    check(Palette.contrast(0x6A6A6A, 0xFFFFFF) > 4.5 && Palette.contrast(0x6A6A6A, 0xFFFFFF) < 7, "a gray that passes 4.5:1 but not 7:1 exists, so the stricter rule is a real one")
    equal(Palette.background.hex(.light), 0xF6EFE3, "the paler sand page in light")
    equal(Palette.background.hex(.dark), 0x1E1C20, "basalt in dark")
    equal(Palette.surface.hex(.light), 0xFDFAF4, "cards in light")
    equal(Palette.side.hex(.light), 0x2A282C, "the spine is basalt in light")
    equal(Palette.side.hex(.dark), 0x151417, "and deeper basalt in dark")
    equal(Palette.pop.hex(.light, .bold), 0xB13917, "Bold's main action is red-orange")
    for name in ["sideInk", "sideMuted", "beadEdge", "beadOn", "pill", "sideFocus", "onPill"] {
        check(Palette.pairs.contains { $0.foreground == name }, "\(name) is held to its minimum")
    }
    check(Palette.failures().filter { $0.mode.isContrast }.isEmpty, "every pair passes its Increase Contrast minimum, in every color vision")
}
