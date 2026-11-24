import Foundation
@testable import GilaMonsterCore

/// Long content stays readable (0.5.0): a callout keeps one sentence as its title, lists are cut at the limits in
/// Overflow.Limit, names are matched the way the search field does, and the groups for Worlds and Changes are right.
@MainActor func overflowChecks() {
    section("Overflow: callout split")
    var split = Overflow.callout(title: "Short title", detail: "More")
    equal(split.title, "Short title", "a short title is kept")
    equal(split.detail, "More", "and so is its detail")
    split = Overflow.callout(title: "Couldn't read the file. The disk said no. Try again later.", detail: nil)
    equal(split.title, "Couldn't read the file.", "a title with several sentences keeps the first")
    equal(split.detail, "The disk said no. Try again later.", "and the rest becomes the detail")
    split = Overflow.callout(title: "Couldn't read the file. More here.", detail: "Existing detail")
    equal(split.detail, "More here.\n\nExisting detail", "the rest goes ahead of the detail it already had")
    split = Overflow.callout(title: "First line\njava.lang.Exception: boom\n\tat Foo.bar(Foo.java:1)", detail: nil)
    equal(split.title, "First line", "a multi-line error keeps its first line as the title")
    check(split.detail?.contains("java.lang.Exception: boom") == true && split.detail?.contains("Foo.bar") == true, "and every other line is in the detail, none lost")
    let long = String(repeating: "word ", count: 60)
    split = Overflow.callout(title: long, detail: nil)
    check(split.title.count <= 120 && split.title.hasSuffix("…"), "a title with no full stop is cut at 120 characters with an ellipsis")
    check(split.detail?.contains("word word") == true && (split.detail?.count ?? 0) >= long.trimmingCharacters(in: .whitespaces).count, "and the whole text is in the detail")
    split = Overflow.callout(title: "  Spaced out  ", detail: nil)
    equal(split.title, "Spaced out", "surrounding whitespace is trimmed")
    check(!Overflow.isLong(nil) && !Overflow.isLong("one line"), "no detail, or one line, needs no Show Details")
    check(Overflow.isLong("a\nb\nc\nd"), "four lines needs Show Details")
    check(!Overflow.isLong("a\nb\nc"), "three lines does not")
    check(Overflow.isLong(String(repeating: "x", count: 241)), "one very long line needs Show Details")

    section("Overflow: slice")
    let items = Array(1...30)
    var cut = Overflow.slice(items, limit: 25, expanded: false)
    equal(cut.shown.count, 25, "30 items with a limit of 25 show 25")
    equal(cut.hidden, 5, "and 5 are left for Show More")
    cut = Overflow.slice(items, limit: 25, expanded: true)
    equal(cut.shown.count, 30, "expanded shows all 30")
    equal(cut.hidden, 0, "and nothing is hidden")
    cut = Overflow.slice(Array(1...25), limit: 25, expanded: false)
    check(cut.shown.count == 25 && cut.hidden == 0, "exactly at the limit shows all, with no button")
    cut = Overflow.slice([Int](), limit: 5, expanded: false)
    check(cut.shown.isEmpty && cut.hidden == 0, "an empty list is empty")
    equal(Overflow.slice(items, limit: 8, expanded: false).shown, Array(1...8), "the first ones are the ones shown, in order")

    section("Overflow: limits")
    equal(Overflow.Limit.allowlistSearchFrom, 12, "the allowlist gets a search from 12 entries")
    equal(Overflow.Limit.allowlistShown, 25, "and shows 25 matches")
    equal(Overflow.Limit.turnedAway, 5, "turned away shows 5")
    equal(Overflow.Limit.warnings, 3, "warnings show 3")
    equal(Overflow.Limit.profiles, 6, "profiles show 6")
    equal(Overflow.Limit.changesPerGroup, 8, "changes show 8 per group")
    equal(Overflow.Limit.recentSignIns, 10, "recent sign-ins show 10")
    equal(Overflow.Limit.worldsFilterFrom, 10, "worlds get a filter from 10")

    section("Overflow: matching")
    let names = ["Alpha_One", "alpha_two", "Beta", "Émile", "Zed"]
    equal(Overflow.matching(names, "") { $0 }, names, "an empty search matches everything")
    equal(Overflow.matching(names, "   ") { $0 }, names, "so does one of spaces")
    equal(Overflow.matching(names, "ALPHA") { $0 }, ["Alpha_One", "alpha_two"], "capitals don't matter")
    equal(Overflow.matching(names, "emile") { $0 }, ["Émile"], "accents don't matter")
    equal(Overflow.matching(names, " beta ") { $0 }, ["Beta"], "spaces around the search are ignored")
    equal(Overflow.matching(names, "nobody") { $0 }, [], "no match is an empty list")
    equal(Overflow.matching(names, "_t") { $0 }, ["alpha_two"], "a part of a name matches")

    section("Overflow: worlds and changes")
    var core = WorldEntry(name: "world"); core.isCore = true; core.isMain = true; core.relativePath = "world"
    var auto = WorldEntry(name: "mining"); auto.relativePath = "mining"; auto.multiverse = MultiverseWorld(name: "mining")
    var manual = WorldEntry(name: "event"); manual.relativePath = "event"; manual.multiverse = MultiverseWorld(name: "event", autoLoad: false)
    var unknown = WorldEntry(name: "stray"); unknown.relativePath = "stray"
    let missing = WorldEntry(name: "gone")
    check(Overflow.loadsAtStartup(core), "the server's own world loads at startup")
    check(Overflow.loadsAtStartup(auto), "a Multiverse world that autoloads does")
    check(!Overflow.loadsAtStartup(manual), "one set not to autoload is Not loaded")
    check(!Overflow.loadsAtStartup(unknown), "a folder Multiverse doesn't know is Not loaded")
    check(!Overflow.loadsAtStartup(missing), "a world whose folder is missing is Not loaded")
    let kinds: [PendingChange] = [
        PendingChange(kind: .config(path: "a.yml"), summary: "a"),
        PendingChange(kind: .pluginRemove(fileName: "x.jar"), summary: "b"),
        PendingChange(kind: .pluginToggle(fileName: "y.jar", enable: true), summary: "c"),
        PendingChange(kind: .playerRestore(folder: "f", uuid: "u", name: "n", inventoryOnly: true, containers: []), summary: "d"),
    ]
    let grouped = Overflow.grouped(kinds)
    equal(grouped.map(\.group), [.plugins, .configs, .players], "changes group by kind, in a fixed order, with empty groups left out")
    equal(grouped.first?.changes.map(\.summary), ["b", "c"], "a removal and a toggle are both plugin changes, in their order")
    check(Overflow.grouped([]).isEmpty, "no changes, no groups")
    equal(grouped.reduce(0) { $0 + $1.changes.count }, kinds.count, "grouping loses none")

    section("Overflow: console and text size")
    equal(ConsoleLine(id: 1, text: ">\u{00A0}list", level: .info, origin: .command).displayText, "Command: list", "a typed command starts with the word Command")
    equal(ConsoleLine(id: 2, text: "[GilaMonster] Stopping", level: .info, origin: .wrapper).displayText, "[GilaMonster] Stopping", "the app's own lines keep their prefix, once")
    equal(ConsoleLine(id: 3, text: "Stopping", level: .info, origin: .wrapper).displayText, "[GilaMonster] Stopping", "and get one if they lack it")
    equal(ConsoleLine(id: 4, text: "[12:00:00 INFO]: Done", level: .info, origin: .server).displayText, "[12:00:00 INFO]: Done", "the server's lines are untouched")
    equal(TextZoom.larger(32), 32, "text can't grow past 32 points")
    equal(TextZoom.smaller(9), 9, "or shrink past 9")
    equal(TextZoom.larger(12), 13, "larger steps by one point")
    equal(TextZoom.smaller(12), 11, "smaller steps by one point")
    equal(TextZoom.clamped(500), 32, "a stored value out of range is brought back to 32")
    equal(TextZoom.clamped(-5), 9, "and one below it to 9")
    equal(TextZoom.larger(31.5), 32, "a step that would pass the top stops at it")
    equal(TextZoom.standard, 12, "the standard size is 12")

    section("Overflow: the snapshot report")
    let clean = Overflow.readReport("checked 17 of 17 pages\n")
    check(clean.pages == 17 && clean.expected == 17 && clean.overflowing.isEmpty, "a clean report: 17 of 17 pages, none overflowing")
    let bad = Overflow.readReport("checked 17 of 17 pages\nOVERFLOW worlds: fitting width 1400 is over the window's 1280\n")
    check(bad.pages == 17 && bad.overflowing.count == 1, "an overflowing page is reported")
    let short = Overflow.readReport("checked 9 of 17 pages\n")
    check(short.pages != short.expected, "a run that drew 9 of 17 pages is visibly short")
    check(Overflow.readReport("").expected == 0 && Overflow.readReport("garbage").expected == 0 && Overflow.readReport("checked 31 pages\n").expected == 0,
          "an empty report, garbage and the old form all count as not having run")

    section("Overflow: when the search and filter appear")
    check(!Overflow.showsAllowlistSearch(entries: 12) && Overflow.showsAllowlistSearch(entries: 13), "the allowlist search appears past 12 entries, not at 12")
    check(!Overflow.showsAllowlistSearch(entries: 0), "and not on an empty list")
    check(!Overflow.showsWorldsFilter(worlds: 10) && Overflow.showsWorldsFilter(worlds: 11), "the worlds filter appears past 10 worlds, not at 10")

    section("Overflow: words and shortcuts the views use")
    equal(Overflow.updateBadge("1.2.3"), "Update 1.2.3", "an update badge reads Update and the version")
    equal(Overflow.onlineMark(true), "online", "an online player's row says online")
    check(Overflow.onlineMark(false) == nil, "an offline player's row doesn't")
    equal(Overflow.quietAfterPageChange, 1, "announcements stay quiet for 1 second after a page change")
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = (try? String(contentsOf: root.appendingPathComponent("Sources/GilaMonster/AppModel.swift"), encoding: .utf8)) ?? ""
    let appLines = app.split(separator: "\n").map(String.init)
    let stopAt = appLines.firstIndex { $0.contains("Button(\"Stop\")") }
    let stopLine = stopAt.map { appLines[$0...min($0 + 1, appLines.count - 1)].joined(separator: " ") } ?? ""
    check(stopLine.contains(#".keyboardShortcut(".", modifiers: [.command, .control])"#), "Stop's shortcut is Control-Command-period (read from the menu source)")
}
