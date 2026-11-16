import Foundation
@testable import LeafJuiceCore

/// Drive caps (D213): what counts, what's removed to make room, what's never removed, the warning, skipping when it
/// can't fit, the in-flight watch, and partial files left by a quit.
@MainActor func backupCapChecks() async {
    let GB: Int64 = 1_000_000_000
    let now = Date()
    func rec(_ name: String, hoursAgo: Double, size: Int64, pinned: Bool = false, scope: BackupScope = .worlds) -> BackupRecord {
        BackupRecord(fileName: name, date: now.addingTimeInterval(-hoursAgo * 3600), size: size, scope: scope, trigger: "manual",
                     software: "Paper", mcVersion: "26.1", serverName: "Made-up", pinned: pinned)
    }
    let cap = DriveCap(name: "MadeUpDrive", bytes: 150 * GB)

    section("Backup caps: making room")
    let first = rec("first", hoursAgo: 24 * 60, size: 1 * GB)
    let a = rec("a", hoursAgo: 24 * 30, size: 40 * GB), b = rec("b", hoursAgo: 24 * 20, size: 40 * GB)
    let c = rec("c", hoursAgo: 24 * 2, size: 40 * GB), d = rec("d", hoursAgo: 1, size: 20 * GB)
    var p = BackupCaps.plan(used: 100 * GB, cap: cap, estimate: 45 * GB, onDrive: [a, b, c, d], all: [first, a, b, c, d], tierDrops: [])
    check(p.fits && p.remove.isEmpty, "a backup that fits under the cap removes nothing")
    p = BackupCaps.plan(used: 140 * GB, cap: cap, estimate: 45 * GB, onDrive: [a, b, c, d], all: [first, a, b, c, d], tierDrops: [])
    equal(p.remove.map(\.fileName), ["a"], "over the cap: the oldest goes first, and only as many as needed")
    check(p.fits && p.after <= cap.bytes, "and then it fits (\(Format.bytes(p.after)))")
    p = BackupCaps.plan(used: 140 * GB, cap: cap, estimate: 45 * GB, onDrive: [a, b, c, d], all: [first, a, b, c, d], tierDrops: ["c"])
    equal(p.remove.map(\.fileName), ["c"], "the ones the keeping tiers would drop anyway go before older ones the tiers keep")
    p = BackupCaps.plan(used: 140 * GB, cap: cap, estimate: 45 * GB, onDrive: [rec("a", hoursAgo: 720, size: 40 * GB, pinned: true), b, c, d],
                        all: [first, a, b, c, d], tierDrops: [])
    equal(p.remove.map(\.fileName), ["b"], "a pinned backup is never removed, however old")
    p = BackupCaps.plan(used: 141 * GB, cap: cap, estimate: 45 * GB, onDrive: [first, a, b, c, d], all: [first, a, b, c, d], tierDrops: ["first"])
    equal(p.remove.map(\.fileName), ["a"], "the server's very first backup is kept, as the keeping tiers keep it")
    p = BackupCaps.plan(used: 150 * GB, cap: cap, estimate: 140 * GB, onDrive: [a, b, c, d], all: [first, a, b, c, d], tierDrops: ["d"])
    check(!p.remove.contains { $0.fileName == "d" }, "the server's newest backup is never removed, even if the tiers would drop it")
    let elsewhere = rec("e", hoursAgo: 0.5, size: 10 * GB)
    p = BackupCaps.plan(used: 150 * GB, cap: cap, estimate: 140 * GB, onDrive: [a, b, c, d], all: [first, a, b, c, d, elsewhere], tierDrops: [])
    check(!p.remove.contains { $0.fileName == "d" }, "nor the newest on this drive, when a newer one is on another drive")
    check(!p.fits && p.remove.isEmpty, "when even that isn't enough, nothing is removed and it doesn't fit")
    check(p.reason.contains("150 GB") && p.reason.contains("MadeUpDrive"), "and it says why, naming the drive and cap: \(p.reason)")
    let t1 = rec("t", hoursAgo: 1, size: 40 * GB), t2 = rec("t-2", hoursAgo: 1, size: 40 * GB), t3 = rec("t-3", hoursAgo: 1, size: 40 * GB)
    p = BackupCaps.plan(used: 120 * GB, cap: cap, estimate: 40 * GB, onDrive: [t3, t1, t2], all: [first, t3, t1, t2], tierDrops: [])
    equal(p.remove.map(\.fileName), ["t"], "backups made in the same second go in the order they were made, and the last of them is the newest")
    p = BackupCaps.plan(used: 20 * GB, cap: cap, estimate: 140 * GB, onDrive: [d], all: [d], tierDrops: [])
    check(!p.fits && p.remove.isEmpty, "a server's only backup is never removed to make room")

    section("Backup caps: estimates and warnings")
    equal(BackupCaps.estimate(records: [a, d], scope: .worlds, sourceBytes: 300 * GB), 24 * GB, "the next backup is guessed from the newest of its kind, with 20% to grow")
    equal(BackupCaps.estimate(records: [a, d], scope: .everything, sourceBytes: 300 * GB), 300 * GB, "with none of that kind, the files' full size")
    check(BackupCaps.warning(used: 127 * GB, cap: cap) == nil, "at 84% of the cap: no warning yet")
    check(BackupCaps.warning(used: 128 * GB, cap: cap)?.contains("85%") == true, "at 85%: a warning, before anything has to be removed")

    section("Backup caps: what counts")
    let target = folder("cap-target")
    let mine = target.appendingPathComponent("made-up-a", isDirectory: true)
    let theirs = target.appendingPathComponent("made-up-b", isDirectory: true)
    func bytes(_ n: Int, _ url: URL) { FileManager.default.createFile(atPath: url.path, contents: Data(count: n)) }
    try? FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: theirs, withIntermediateDirectories: true)
    bytes(1000, mine.appendingPathComponent("1.tar.gz")); bytes(10, mine.appendingPathComponent("1.json"))
    bytes(500, mine.appendingPathComponent("2.partial"))
    bytes(300, mine.appendingPathComponent("stray.tar.gz"))
    bytes(4096, mine.appendingPathComponent("._1.tar.gz"))
    write("x", theirs.appendingPathComponent(".leafjuice-server"))
    bytes(2000, theirs.appendingPathComponent("9.tar.gz")); bytes(10, theirs.appendingPathComponent("9.json"))
    bytes(7000, target.appendingPathComponent("someone-elses.mkv"))
    equal(BackupCaps.used([mine]), 3520, "counts finished backups with their records, a partial in progress and other servers' backups beside it, but not stray files or other things on the drive")
    let small = DriveCap(name: "MadeUpDrive", bytes: 4000)
    check(BackupCaps.watch([mine], cap: small)() == nil, "the in-flight watch lets a backup run under the cap")
    bytes(1000, mine.appendingPathComponent("2.partial"))
    check(BackupCaps.watch([mine], cap: small)()?.contains("cap") == true, "and stops it once its growing partial file takes the drive's backups past the cap")

    section("Backup caps: partial files left by a quit")
    let removed = BackupCaps.sweepPartials([mine])
    equal(removed.map(\.name), ["2.partial"], "a leftover partial file is removed")
    check(FileOps.exists(mine.appendingPathComponent("1.tar.gz")) && FileOps.exists(mine.appendingPathComponent("stray.tar.gz")), "and nothing else is touched")
    // A backup being written when the app quits: tar is stopped and its partial removed.
    let quitting = folder("cap-quit").appendingPathComponent("3.partial")
    bytes(100, quitting)
    let sleeper = Process(); sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep"); sleeper.arguments = ["30"]
    try? sleeper.run()
    let job = UUID()
    Backups.inFlight.with { $0[job] = Backups.Job(process: sleeper, partial: quitting) }
    check(Backups.writing, "a backup in progress is known")
    let cancelled = Backups.cancelInFlight(wait: 3)
    check(!sleeper.isRunning && !FileOps.exists(quitting) && cancelled == [quitting] && !Backups.writing, "Quit stops it and removes its partial file")
    if sleeper.isRunning { sleeper.terminate() }

    section("Storage that's passed over says why")
    let blocked = SmartBackup.missingReason(URL(fileURLWithPath: "/Volumes/MadeUpDrive/LeafJuice-backups/made-up")) { path in
        if path.hasPrefix("/Volumes/MadeUpDrive") { throw CocoaError(.fileReadNoPermission) }
        return ["Macintosh HD"]
    }
    check(blocked.contains("isn't allowed") && blocked.contains("Removable Volumes"), "a drive macOS won't let LeafJuice open says so, and how to allow it: \(blocked)")
    let posix = SmartBackup.missingReason(URL(fileURLWithPath: "/Volumes/MadeUpDrive/x/y")) { path in
        if path.hasPrefix("/Volumes/MadeUpDrive") { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)) }
        return []
    }
    check(posix.contains("isn't allowed"), "the same when macOS refuses with a plain permission error")
    let unplugged = SmartBackup.missingReason(URL(fileURLWithPath: "/Volumes/MadeUpDrive/LeafJuice-backups/made-up")) { path in
        if path.hasPrefix("/Volumes/MadeUpDrive") { throw CocoaError(.fileReadNoSuchFile) }
        return ["Macintosh HD"]
    }
    equal(unplugged, "Not connected.", "an unplugged drive is still just not connected")

    section("Quitting during a backup: progress (D215)")
    let t0 = Date()
    let half = BackupProgress(server: "Made-up", written: 20 * GB, expected: 40 * GB, started: t0.addingTimeInterval(-600))
    equal(half.fraction, 0.5, "progress is what's written over the expected size")
    equal(half.secondsLeft(now: t0).map { Int($0) }, 600, "time left is at the speed so far: half done in ten minutes, ten to go")
    check(half.words(now: t0) == "Made-up: 20 GB of about 40 GB, about 10 minutes left.", "and it's said in words: \(half.words(now: t0))")
    let early = BackupProgress(server: "Made-up", written: 1 * GB, expected: 40 * GB, started: t0.addingTimeInterval(-5))
    check(early.secondsLeft(now: t0) == nil && !early.words(now: t0).contains("left"), "no time left is guessed in the first ten seconds")
    let over = BackupProgress(server: "Made-up", written: 45 * GB, expected: 40 * GB, started: t0.addingTimeInterval(-900))
    check(over.fraction == 0.99 && over.words(now: t0).contains("nearly done"), "past the guess, it holds at 99% and says nearly done, never 100% before it is")
    let unknown = BackupProgress(server: "Made-up", written: 3 * GB, expected: 0, started: t0.addingTimeInterval(-60))
    check(unknown.fraction == nil && unknown.secondsLeft(now: t0) == nil, "with nothing to go by, no progress or time is made up")
    let runningPartial = folder("quit-progress").appendingPathComponent("4.partial")
    bytes(2048, runningPartial)
    let runningJob = UUID()
    Backups.inFlight.with { $0[runningJob] = Backups.Job(process: nil, partial: runningPartial, server: "Made-up", started: t0, expected: 4096) }
    let seen = Backups.running()
    check(seen.count == 1 && seen[0].written == 2048 && seen[0].fraction == 0.5, "a running backup's progress is read from its growing partial file")
    let other = folder("quit-progress").appendingPathComponent("older-backup.tar.gz")
    bytes(10, other)
    Backups.cancelInFlight(wait: 1)
    check(!FileOps.exists(runningPartial) && FileOps.exists(other), "Cancel and quit deletes only the running backup's unfinished file")

    section("Backup caps: a real made-up server")
    let root = folder("cap-server")
    write("server-port=25593\nlevel-name=world\n", root.appendingPathComponent("server.properties"))
    write(String(repeating: "made up level ", count: 2000), root.appendingPathComponent("world/level.dat"))
    guard let s = try? await ServerController.adopt(root: root, name: "Made-up Capped") else { check(false, "couldn't adopt a made-up server"); return }
    s.profile.backup.mirror = nil
    s.profile.backup.smart.tiered = false
    s.profile.backup.keepLast = 100
    s.profile.backup.keepDays = 0
    DiskGuard.standIn = { _ in (500 * GB, 1000 * GB) }
    defer { DiskGuard.standIn = nil; try? BackupCaps.set(nil, for: Backups.destination(s.profile)) }
    var made: [BackupRecord] = []
    for _ in 0..<3 {
        if let r = try? await s.backupNow(trigger: "manual") { made.append(r) }
        try? await Task.sleep(for: .milliseconds(1100))  // a second apart, as real ones are
    }
    equal(made.count, 3, "three backups made with no cap")
    let dest = Backups.destination(s.profile)
    let one = made.first?.size ?? 1
    // A leftover partial from a quit counts and is cleared before the next backup.
    bytes(Int(one) * 5, dest.appendingPathComponent("left-behind.partial"))
    s.sweepLeftoverPartials()
    check(!FileOps.exists(dest.appendingPathComponent("left-behind.partial")), "opening or backing up clears a partial left by a quit")
    // Cap just over three backups: the fourth needs one removed.
    try? BackupCaps.set(BackupCaps.used([dest]) + one / 2, for: dest)
    do {
        let fourth = try await s.backupNow(trigger: "manual")
        let left = Backups.list(s.profile).map(\.fileName)
        check(left.contains(made[0].fileName) && !left.contains(made[1].fileName) && left.contains(made[2].fileName) && left.contains(fourth.fileName),
              "over the cap, the oldest after the server's first is removed, the newest kept, then the backup is made")
        check(BackupCaps.used([dest]) <= (BackupCaps.cap(for: dest)?.bytes ?? 0), "and the drive's backups stay under the cap")
        check(s.issues.contains { $0.id == "wrapper:backup-cap-near" }, "near the cap, an issue warns")
    } catch { check(false, "the capped backup should have made room: \(error)") }
    // A cap smaller than one backup: skipped, nothing removed, and the owner is told.
    let before = Backups.list(s.profile).map(\.fileName)
    try? BackupCaps.set(one / 2, for: dest)
    do { _ = try await s.backupNow(trigger: "manual"); check(false, "a backup that can't fit under the cap should be skipped") }
    catch { check(error.localizedDescription.contains("skipped"), "a backup that can't fit is skipped: \(error.localizedDescription)") }
    equal(Backups.list(s.profile).map(\.fileName), before, "and nothing was removed for it")
    check(!FileOps.children(dest).contains { $0.lastPathComponent.hasSuffix(".partial") }, "or left half-written")
    check(s.issues.contains { $0.id == "wrapper:backup-cap-skipped" }, "and an issue says it was skipped")
    // A cap that's raised again lets backups resume, and clears the skipped issue.
    try? BackupCaps.set(nil, for: dest)
    _ = try? await s.backupNow(trigger: "manual")
    check(!s.issues.contains { $0.id == "wrapper:backup-cap-skipped" }, "once a backup runs again, the skipped issue goes")
    let driveRows = s.driveUse()
    check(driveRows.count == 1 && driveRows[0].cap == nil, "the Backups page lists the drive, with no cap once it's removed")
}
