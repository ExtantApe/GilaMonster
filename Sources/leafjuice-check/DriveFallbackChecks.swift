import Foundation
@testable import LeafJuiceCore

/// The drive-only rule (owner, 2026-11-16): backups go to one drive; after it's been missing 24 hours they go to the
/// Mac's disk, only while 75 GB stays free; skipped and warned otherwise; back to the drive when it returns.
@MainActor func driveFallbackChecks() async {
    let GB: Int64 = 1 << 30
    section("Drive-only backups: the rule")
    let rule = BackupFallback(path: "/made/up")
    let now = Date()
    let hours: (Double) -> Date = { now.addingTimeInterval(-$0 * 3600) }
    equal(rule.decide(connected: true, missingSince: nil, now: now, free: 1 * GB, needed: 50 * GB, driveName: "Drive"), .drive, "drive connected: it's used, whatever the Mac's disk has")
    if case .skip(let why) = rule.decide(connected: false, missingSince: hours(23.5), now: now, free: 500 * GB, needed: 50 * GB, driveName: "Drive") {
        check(why.contains("isn't connected") && why.contains("Nothing was written") && why.contains("30 minutes"), "missing 23.5 hours: skipped and says when the fallback starts (\(why))")
    } else { check(false, "missing under 24 hours should skip") }
    if case .skip = rule.decide(connected: false, missingSince: nil, now: now, free: 500 * GB, needed: 50 * GB, driveName: "Drive") {
        check(true, "missing, first noticed just now: the 24 hours start now, so it's skipped")
    } else { check(false, "first noticed missing should skip") }
    equal(rule.decide(connected: false, missingSince: hours(24), now: now, free: 130 * GB, needed: 50 * GB, driveName: "Drive"), .fallback, "missing 24 hours, 80 GB would be left: the Mac's disk")
    if case .skip(let why) = rule.decide(connected: false, missingSince: hours(30), now: now, free: 120 * GB, needed: 50 * GB, driveName: "Drive") {
        check(why.contains("75 GB"), "missing 30 hours, only 70 GB would be left: skipped, and says so (\(why))")
    } else { check(false, "too little room should skip") }
    if case .skip = rule.decide(connected: false, missingSince: hours(48), now: now, free: nil, needed: 1 * GB, driveName: "Drive") {
        check(true, "free space unknown: skipped (fails closed)")
    } else { check(false, "unknown free space should skip") }

    section("Drive-only backups: which drive a path is on")
    equal(DriveCheck.volumeRoot(URL(fileURLWithPath: "/Volumes/Made Up/LeafJuice/x"))?.path, "/Volumes/Made Up", "a path under /Volumes is on that drive")
    check(DriveCheck.volumeRoot(URL(fileURLWithPath: "/opt/made-up/servers")) == nil, "a path outside /Volumes is on the Mac's own disk")
    check(DriveCheck.isConnected(URL(fileURLWithPath: NSHomeDirectory())), "and the Mac's own disk always counts as connected")
    let unplugged = URL(fileURLWithPath: "/Volumes/MadeUp-\(UUID().uuidString.prefix(6))/LeafJuice/server", isDirectory: true)
    check(!DriveCheck.isConnected(unplugged), "a drive that isn't mounted isn't connected")

    // A real made-up server. The drive is a scratch folder, with a stand-in saying whether it's plugged in.
    let root = folder("fallback-server")
    write("level-name=world\n", root.appendingPathComponent("server.properties"))
    write("made up level", root.appendingPathComponent("world/level.dat"))
    guard let c = try? await ServerController.adopt(root: root, name: "Made-up Fallback") else { check(false, "couldn't adopt a made-up server"); return }
    let drive = folder("fallback-drive"), mac = folder("fallback-mac"), other = folder("fallback-target")
    var plugged = true
    DriveCheck.standIn = { $0.path.hasPrefix(drive.path) ? plugged : true }
    DiskGuard.standIn = { _ in (300 * GB, 1000 * GB) }
    defer { DriveCheck.standIn = nil; DiskGuard.standIn = nil }
    c.profile.backup.mirror = nil
    c.profile.backup.destination = drive.appendingPathComponent("made-up", isDirectory: true).path
    c.profile.backup.smart.targets = [other.path]
    c.profile.backup.fallback = BackupFallback(path: mac.path)
    let macFolder = Backups.targetFolder(mac.path, for: c.profile)
    func onMac() -> [String] { FileOps.children(macFolder).map(\.lastPathComponent).filter { $0.hasSuffix(".tar.gz") || $0.hasSuffix(".partial") } }

    section("Drive-only backups: drive connected")
    do {
        let made = try await c.backupNow(trigger: "after-play")
        equal(made.location, Backups.destination(c.profile).path, "a routine backup goes to the drive, passing over the storage targets")
        check(c.profile.backup.driveLastSeen != nil && c.profile.backup.driveMissingSince == nil, "and the drive is noted as seen")
        check(onMac().isEmpty, "nothing on the Mac's disk")
    } catch { check(false, "backup with the drive connected threw: \(error)") }

    section("Drive-only backups: drive missing under 24 hours")
    plugged = false
    do { _ = try await c.backupNow(trigger: "after-play"); check(false, "a backup with the drive just pulled should be skipped") }
    catch { check(error.localizedDescription.contains("skipped"), "skipped: \(error.localizedDescription)") }
    check(c.profile.backup.driveMissingSince != nil, "the time it went missing is kept")
    check(c.issues.contains { $0.id == "wrapper:backup-drive-missing" }, "and a warning is shown")
    check(onMac().isEmpty, "and nothing was written to the Mac's disk")
    do { _ = try await c.backupNow(trigger: "before-update"); check(false, "a restore point should be skipped too") }
    catch { check(error.localizedDescription.contains("skipped"), "a restore point is skipped the same way") }

    section("Drive-only backups: missing 24 hours, too little room")
    c.profile.backup.driveMissingSince = Date().addingTimeInterval(-25 * 3600)
    DiskGuard.standIn = { _ in (75 * GB, 1000 * GB) }
    do { _ = try await c.backupNow(trigger: "after-play"); check(false, "a fallback leaving under 75 GB should be skipped") }
    catch { check(error.localizedDescription.contains("75 GB"), "skipped, as it would leave under 75 GB: \(error.localizedDescription)") }
    check(onMac().isEmpty, "nothing written")

    section("Drive-only backups: missing 24 hours, enough room")
    DiskGuard.standIn = { _ in (300 * GB, 1000 * GB) }
    do {
        // Another trigger, so its name differs from the drive's backup made in the same second.
        let made = try await c.backupNow(trigger: "world-changed")
        equal(made.location, macFolder.path, "goes to the server's own folder on the Mac's disk")
        check(c.backups.contains { $0.fileName == made.fileName && $0.location == macFolder.path }, "and is listed, with where it is")
        check(c.issues.contains { $0.id == "wrapper:backup-on-fallback" && ($0.explanation ?? "").contains("Mac's own disk") }, "with a note that it's on the Mac's disk")
    } catch { check(false, "fallback backup threw: \(error)") }

    section("Drive-only backups: the drive comes back")
    plugged = true
    check(c.noteBackupDrive(), "the drive is seen again")
    check(c.profile.backup.driveMissingSince == nil, "the missing time is cleared")
    check(!c.issues.contains { $0.id == "wrapper:backup-drive-missing" }, "the missing warning goes")
    check(c.issues.contains { $0.id == "wrapper:backup-on-fallback" && ($0.explanation ?? "").contains("is back") }, "the fallback backups stay listed, to be moved")
    do {
        let made = try await c.backupNow(trigger: "after-play")
        equal(made.location, Backups.destination(c.profile).path, "the next backup goes to the drive again")
    } catch { check(false, "backup after the drive returned threw: \(error)") }

    section("Drive-only backups: never written where a drive should be")
    DriveCheck.standIn = nil
    c.profile.backup.fallback = nil
    c.profile.backup.smart.targets = []
    c.profile.backup.destination = unplugged.path
    do { _ = try await c.backupNow(trigger: "manual"); check(false, "a backup to a drive that isn't mounted should be refused") }
    catch { check(error.localizedDescription.contains("isn't connected"), "a backup to an unmounted drive is refused: \(error.localizedDescription)") }
    check(!FileManager.default.fileExists(atPath: unplugged.deletingLastPathComponent().deletingLastPathComponent().path), "and nothing was made where the drive would be")
}
