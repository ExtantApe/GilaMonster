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
        }
    }

    // Pixel type (K820) is on in every run above, at the default text size. The same heavy data again at the two larger
    // label sizes, 16.5 pt (body 16) and 22 pt (body 23), where buttons, columns and the sidebar have grown with the text.
    section("Snapshot: no page is wider than its window with larger pixel type (heavy data)")
    for (body, label) in [("16", "16.5 pt labels"), ("23", "22 pt labels")] {
        let larger = out.appendingPathComponent("body-\(body)")
        try? FileManager.default.removeItem(at: larger.appendingPathComponent("heavy/bold-light/overflow-report.txt"))
        let status = runScript(script, [larger.path, "heavy"], root: root,
                               environment: ["THEMES": "bold", "LOOKS": "light", "GILAMONSTER_SNAPSHOT_PIXEL": "on", "GILAMONSTER_SNAPSHOT_BODY": body, "GILAMONSTER_SNAPSHOT_DIALOGS_ONLY": ""].filter { !$0.value.isEmpty })
        equal(status, 0, "\(label): the snapshot script finished")
        let read = Overflow.readReport((try? String(contentsOf: larger.appendingPathComponent("heavy/bold-light/overflow-report.txt"), encoding: .utf8)) ?? "")
        check(read.expected > 0 && read.pages == read.expected, "\(label): every page was drawn (\(read.pages) of \(read.expected))")
        check(read.overflowing.isEmpty, "\(label): no page is wider than the window. \(read.overflowing.joined(separator: "; "))")
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
