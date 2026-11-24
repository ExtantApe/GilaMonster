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
    let run = Process()
    run.executableURL = script
    run.arguments = [out.path, "heavy"]
    run.currentDirectoryURL = root
    run.standardOutput = FileHandle.nullDevice
    run.standardError = FileHandle.nullDevice
    do { try run.run() } catch { check(false, "couldn't run the snapshot script: \(error)"); return }
    run.waitUntilExit()
    equal(run.terminationStatus, 0, "the snapshot script finished")
    for theme in ["bold", "quiet"] {
        for look in ["light", "dark"] {
            let report = out.appendingPathComponent("heavy/\(theme)-\(look)/overflow-report.txt")
            let text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
            let read = Overflow.readReport(text)
            check(read.pages > 0, "heavy \(theme) \(look): the snapshot drew pages")
            check(read.overflowing.isEmpty, "heavy \(theme) \(look): no page is wider than the window. \(read.overflowing.joined(separator: "; "))")
        }
    }
}
