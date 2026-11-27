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
        }
    }

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
