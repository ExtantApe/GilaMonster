import Foundation
@testable import GilaMonsterCore

/// The drive-only rule (D250, 2026-11-21): backups go to one drive. While it's missing or full, each backup is skipped
/// and reported, and nothing is written to any other drive or to the Mac's disk, however long it's been gone.
@MainActor func driveFallbackChecks() async {
    let GB: Int64 = 1 << 30
    section("Drive-only backups: the rule")
    let rule = BackupFallback(path: "/made/up")
    let now = Date()
    let hours: (Double) -> Date = { now.addingTimeInterval(-$0 * 3600) }
    equal(rule.decide(connected: true, missingSince: nil, now: now, driveName: "Drive"), .drive, "drive connected: it's used")
    for away: Double in [0, 23.5, 24, 30, 720] {
        if case .skip(let why) = rule.decide(connected: false, missingSince: hours(away), now: now, driveName: "Drive") {
            check(why.contains("isn't connected") && why.contains("Mac's own disk"), "missing \(away) hours: skipped, never the Mac's disk (\(why))")
        } else { check(false, "missing \(away) hours should skip") }
    }
    if case .skip = rule.decide(connected: false, missingSince: nil, now: now, driveName: "Drive") {
        check(true, "missing, first noticed just now: skipped")
    } else { check(false, "first noticed missing should skip") }
    let old = #"{"path":"/made/up","afterHours":24,"keepFreeGB":75}"#.data(using: .utf8)!
    equal(try? JSONDecoder().decode(BackupFallback.self, from: old), rule, "a setting saved under the old rule still reads, as drive-only")

    section("Drive-only backups: which drive a path is on")
    equal(DriveCheck.volumeRoot(URL(fileURLWithPath: "/Volumes/Made Up/GilaMonster/x"))?.path, "/Volumes/Made Up", "a path under /Volumes is on that drive")
    check(DriveCheck.volumeRoot(URL(fileURLWithPath: "/opt/made-up/servers")) == nil, "a path outside /Volumes is on the Mac's own disk")
    check(DriveCheck.isConnected(URL(fileURLWithPath: NSHomeDirectory())), "and the Mac's own disk always counts as connected")
    let unplugged = URL(fileURLWithPath: "/Volumes/MadeUp-\(UUID().uuidString.prefix(6))/GilaMonster/server", isDirectory: true)
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

    section("Drive-only backups: drive missing")
    plugged = false
    do { _ = try await c.backupNow(trigger: "after-play"); check(false, "a backup with the drive just pulled should be skipped") }
    catch { check(error.localizedDescription.contains("skipped"), "skipped: \(error.localizedDescription)") }
    check(c.profile.backup.driveMissingSince != nil, "the time it went missing is kept")
    check(c.issues.contains { $0.id == "wrapper:backup-drive-missing" }, "and a warning is shown")
    check(onMac().isEmpty, "and nothing was written to the Mac's disk")
    do { _ = try await c.backupNow(trigger: "before-update"); check(false, "a restore point should be skipped too") }
    catch { check(error.localizedDescription.contains("skipped"), "a restore point is skipped the same way") }

    section("Drive-only backups: missing for days, plenty of room on the Mac")
    c.profile.backup.driveMissingSince = Date().addingTimeInterval(-72 * 3600)
    DiskGuard.standIn = { _ in (900 * GB, 1000 * GB) }
    do { _ = try await c.backupNow(trigger: "world-changed"); check(false, "a drive gone 72 hours should still skip") }
    catch { check(error.localizedDescription.contains("skipped"), "still skipped after 72 hours: \(error.localizedDescription)") }
    check(onMac().isEmpty, "and still nothing on the Mac's disk")
    check(!FileManager.default.fileExists(atPath: macFolder.path) || onMac().isEmpty, "the old fallback folder gets nothing new")

    section("Drive-only backups: the drive comes back")
    plugged = true
    check(c.noteBackupDrive(), "the drive is seen again")
    check(c.profile.backup.driveMissingSince == nil, "the missing time is cleared")
    check(!c.issues.contains { $0.id == "wrapper:backup-drive-missing" }, "the missing warning goes")
    do {
        let made = try await c.backupNow(trigger: "after-play")
        equal(made.location, Backups.destination(c.profile).path, "the next backup goes to the drive again")
    } catch { check(false, "backup after the drive returned threw: \(error)") }

    section("Drive-only backups: the drive is full")
    DiskGuard.standIn = { _ in (1 * (1 << 20), 1000 * GB) }
    do { _ = try await c.backupNow(trigger: "manual"); check(false, "a backup to a full drive should be refused") }
    catch { check(!error.localizedDescription.isEmpty, "refused on a full drive: \(error.localizedDescription)") }
    check(onMac().isEmpty, "and nothing went to the Mac's disk instead")
    DiskGuard.standIn = { _ in (300 * GB, 1000 * GB) }

    section("Drive-only backups: never written where a drive should be")
    DriveCheck.standIn = nil
    c.profile.backup.fallback = nil
    c.profile.backup.smart.targets = []
    c.profile.backup.destination = unplugged.path
    do { _ = try await c.backupNow(trigger: "manual"); check(false, "a backup to a drive that isn't mounted should be refused") }
    catch { check(error.localizedDescription.contains("isn't connected"), "a backup to an unmounted drive is refused: \(error.localizedDescription)") }
    check(!FileManager.default.fileExists(atPath: unplugged.deletingLastPathComponent().deletingLastPathComponent().path), "and nothing was made where the drive would be")
}
