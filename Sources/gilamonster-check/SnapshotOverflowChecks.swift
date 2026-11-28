import Foundation
@testable import GilaMonsterCore

/// Runs scripts/snapshot-fixtures.sh with heavy made-up data in both themes and both looks, then reads each folder's
/// overflow-report.txt. A page wider than the window is a failure, and so is a run that drew nothing.
@MainActor func snapshotOverflowChecks() async {
    section("Snapshot: no page is wider than its window (heavy data)")
    let kept = ProcessInfo.processInfo.environment["GILAMONSTER_SNAPSHOT_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    let out = kept ?? folder("snapshot-out")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    // This file's own place in the package: Sources/gilamonster-check/<this file>, so the script is two folders up.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let script = root.appendingPathComponent("scripts/snapshot-fixtures.sh")
    guard FileManager.default.isExecutableFile(atPath: script.path) else { check(false, "scripts/snapshot-fixtures.sh is missing"); return }
    // A report left by an earlier run, in a reused folder, must never count: remove each before drawing.
    for theme in ["bold", "quiet"] { for look in ["light", "dark"] {
        try? FileManager.default.removeItem(at: out.appendingPathComponent("heavy/\(theme)-\(look)/overflow-report.txt"))
    } }
    let status = runScript(script, [out.path, "heavy"], root: root, environment: [:])
    equal(status, 0, "the snapshot script finished")
    for theme in ["bold", "quiet"] {
        for look in ["light", "dark"] {
            let report = out.appendingPathComponent("heavy/\(theme)-\(look)/overflow-report.txt")
            let text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
            let read = Overflow.readReport(text)
            check(read.expected > 0 && read.pages == read.expected, "heavy \(theme) \(look): every page was drawn (\(read.pages) of \(read.expected))")
            check(read.overflowing.isEmpty, "heavy \(theme) \(look): no page is wider than the window. \(read.overflowing.joined(separator: "; "))")
            check(read.pushed.isEmpty && read.placed.count == read.expected, "heavy \(theme) \(look): every page sits inside the window. \(read.pushed.joined(separator: "; "))")
            dialogChecks("heavy \(theme) \(look)", out.appendingPathComponent("heavy/\(theme)-\(look)/dialog-report.txt"))
        }
    }

    // Pixel type (K820) is on in every run above, at the default text size. The same heavy data again at the two larger
    // label sizes, 16.5 pt (body 16) and 22 pt (body 23), where buttons, columns and the sidebar have grown with the text.
    section("Snapshot: no page is wider than its window with larger pixel type (heavy data)")
    for (body, label) in [("16", "16.5 pt labels"), ("23", "22 pt labels")] {
        let larger = out.appendingPathComponent("body-\(body)")
        try? FileManager.default.removeItem(at: larger.appendingPathComponent("heavy/bold-light/overflow-report.txt"))
        let status = runScript(script, [larger.path, "heavy"], root: root,
                               environment: ["THEMES": "bold", "LOOKS": "light", "GILAMONSTER_SNAPSHOT_PIXEL": "on", "GILAMONSTER_SNAPSHOT_BODY": body])
        equal(status, 0, "\(label): the snapshot script finished")
        let read = Overflow.readReport((try? String(contentsOf: larger.appendingPathComponent("heavy/bold-light/overflow-report.txt"), encoding: .utf8)) ?? "")
        check(read.expected > 0 && read.pages == read.expected, "\(label): every page was drawn (\(read.pages) of \(read.expected))")
        check(read.overflowing.isEmpty, "\(label): no page is wider than the window. \(read.overflowing.joined(separator: "; "))")
        dialogChecks(label, larger.appendingPathComponent("heavy/bold-light/dialog-report.txt"))
    }

    // Dialogs (K820 review): each sheet and the Allow window is drawn and its left and right edges are read for content
    // running off the side. Bold Text is the case that cut the Allow prompt's player name, so it is run too.
    section("Snapshot: no dialog is clipped, with Bold Text and the largest text")
    for (body, bold, label) in [("23", "", "22 pt labels"), ("13", "1", "Bold Text")] {
        let dir = out.appendingPathComponent("dialogs-\(body)-\(bold.isEmpty ? "plain" : "bold")")
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("normal/bold-dark/dialog-report.txt"))
        var env = ["THEMES": "bold", "LOOKS": "dark", "PAGES": "overview", "GILAMONSTER_SNAPSHOT_BODY": body]
        if !bold.isEmpty { env["GILAMONSTER_SNAPSHOT_BOLD"] = bold }
        equal(runScript(script, [dir.path, "normal"], root: root, environment: env), 0, "\(label): the dialog run finished")
        dialogChecks(label, dir.appendingPathComponent("normal/bold-dark/dialog-report.txt"))
    }

    // The measure has to be able to say no here too: with every sheet drawn narrower than it asks, each must be CLIPPED.
    section("Snapshot: a deliberately clipped dialog is caught")
    let clipOut = folder("snapshot-clipped")
    equal(runScript(script, [clipOut.path, "normal"], root: root, environment: ["THEMES": "bold", "LOOKS": "light", "PAGES": "overview", "GILAMONSTER_SNAPSHOT_FORCE_NARROW": "1"]), 0, "the clipped run finished")
    let clipped = Overflow.readDialogReport((try? String(contentsOf: clipOut.appendingPathComponent("normal/bold-light/dialog-report.txt"), encoding: .utf8)) ?? "")
    check(clipped.expected > 0 && clipped.checked == clipped.expected, "the clipped run checked every dialog (\(clipped.checked) of \(clipped.expected))")
    check(clipped.clipped.count >= clipped.expected - 2, "and caught the clipping (\(clipped.clipped.count) of \(clipped.expected) reported)")
    check(Overflow.readDialogReport("").expected == 0 && Overflow.readDialogReport("").checked == 0, "a missing report counts as not having run")
    check(!Overflow.edgeHasContent([(255, 255, 255), (255, 255, 255)]) && Overflow.edgeHasContent([(255, 255, 255), (30, 30, 30)]), "an edge is clipped only where a pixel differs from its neighbours")

    // The measure has to be able to say no: with every page made too wide on purpose, each must be reported.
    section("Snapshot: a deliberately too-wide page is caught")
    let wideOut = folder("snapshot-wide")
    let wideStatus = runScript(script, [wideOut.path, "normal"], root: root,
                               environment: ["THEMES": "bold", "LOOKS": "light", "GILAMONSTER_SNAPSHOT_FORCE_WIDE": "1"])
    equal(wideStatus, 0, "the too-wide run finished")
    let wide = Overflow.readReport((try? String(contentsOf: wideOut.appendingPathComponent("normal/bold-light/overflow-report.txt"), encoding: .utf8)) ?? "")
    check(wide.expected > 0 && wide.pages == wide.expected, "the too-wide run drew every page")
    equal(wide.overflowing.count, wide.expected, "and every page was reported as too wide")

    // Every banner at once, each with a second line, over two pages (K815). When banners make the column taller than
    // the window, the report says so.
    section("Snapshot: banners with a second line leave the page in view")
    let banners = ["KEYCHAIN": "denied", "BANNERS": "all", "PAGES": "overview,console", "THEMES": "bold"]
    let bannerOut = folder("snapshot-banners")
    equal(runScript(script, [bannerOut.path, "normal"], root: root, environment: banners), 0, "the run with every banner finished")
    for look in ["light", "dark"] {
        let read = Overflow.readReport((try? String(contentsOf: bannerOut.appendingPathComponent("normal/bold-\(look)/overflow-report.txt"), encoding: .utf8)) ?? "")
        equal(read.placed.count, 2, "bold \(look): both pages were measured")
        check(read.placed.allSatisfy { line in bannerHeight(line).map { $0 > 300 } == true }, "bold \(look): the banners were really drawn (over 300 points of them). \(read.placed.joined(separator: "; "))")
        check(read.pushed.isEmpty, "bold \(look): no page is pushed out of view. \(read.pushed.joined(separator: "; "))")
    }
    // The measure has to be able to say no: with the column's hold on its height taken away on purpose, the same
    // banners push both pages out.
    section("Snapshot: a page pushed out of view by banners is caught")
    let oldOut = folder("snapshot-banners-old")
    equal(runScript(script, [oldOut.path, "normal"], root: root, environment: banners.merging(["LOOKS": "light", "GILAMONSTER_SNAPSHOT_FORCE_TALL_COLUMN": "1"]) { $1 }), 0, "the run without the hold finished")
    let old = Overflow.readReport((try? String(contentsOf: oldOut.appendingPathComponent("normal/bold-light/overflow-report.txt"), encoding: .utf8)) ?? "")
    equal(old.pushed.count, 2, "and both pages were reported as pushed out of view. \(old.placed.joined(separator: "; "))")
}

/// Every dialog was checked, none is clipped, and a report that isn't there fails.
@MainActor private func dialogChecks(_ label: String, _ report: URL) {
    let read = Overflow.readDialogReport((try? String(contentsOf: report, encoding: .utf8)) ?? "")
    check(read.expected > 0 && read.checked == read.expected, "\(label): every dialog was checked (\(read.checked) of \(read.expected))")
    check(read.clipped.isEmpty, "\(label): no dialog is clipped. \(read.clipped.joined(separator: "; "))")
    // The real ask window, driven off screen through all three "Need More Time" presses (K820 recheck): wide, narrow,
    // and on a screen too short to hold it, which is only held to staying on that screen.
    let ask = ((try? String(contentsOf: report.deletingLastPathComponent().appendingPathComponent("ask-window-report.txt"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    check(ask.first == "checked 3 ask windows", "\(label): the ask window was driven three times (\(ask.first ?? "no report"))")
    let faults = ask.dropFirst().filter { !$0.hasPrefix("NOTE ") }
    check(faults.isEmpty, "\(label): after the last extra minute the ask window fits, keeps its place and guards clicks. \(faults.joined(separator: "; "))")
}

@MainActor private func runScript(_ script: URL, _ arguments: [String], root: URL, environment: [String: String]) -> Int32 {
    let run = Process()
    run.executableURL = script
    run.arguments = arguments
    run.currentDirectoryURL = root
    run.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    run.standardOutput = FileHandle.nullDevice
    run.standardError = FileHandle.nullDevice
    do { try run.run() } catch { check(false, "couldn't run the snapshot script: \(error)"); return -1 }
    run.waitUntilExit()
    return run.terminationStatus
}

/// The banner row's height from a PLACED line: "... banners 412 tall".
private func bannerHeight(_ line: String) -> Int? {
    guard let tail = line.components(separatedBy: ", banners ").last, tail.hasSuffix(" tall") else { return nil }
    return Int(tail.dropLast(5))
}
