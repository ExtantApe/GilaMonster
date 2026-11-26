import Foundation
@testable import GilaMonsterCore

/// Leftover backup clones are removed at launch (K799), and only those: made-up folders in the suite's own temp
/// folder, with links pointing outside to prove nothing is followed.
@MainActor func backupCloneChecks() {
    section("Backup clones: which names are GilaMonster's")
    check(BackupClones.isCloneName("made-up-server-1A2B3C4D"), "a server folder, a hyphen and 8 hex digits")
    check(BackupClones.isCloneName(BackupClones.newName(forServer: URL(fileURLWithPath: "/tmp/made-up-server"))), "the name a new clone gets")
    check(BackupClones.isCloneName("Made Up Server-0a1b2c3d"), "spaces in the server's folder name are fine")
    for name in ["made-up-server", "made-up-server-1A2B3C", "made-up-server-1A2B3C4D5", "made-up-server-1A2B3C4G", "-1A2B3C4D", "1A2B3C4D", "made-up-server-1A2B3C4D.zip", "made-up-server_1A2B3C4D", ""] {
        check(!BackupClones.isCloneName(name), "\"\(name)\" isn't a clone's name")
    }
    equal(BackupClones.folder(besideServer: URL(fileURLWithPath: "/tmp/servers/made-up-server")).path, "/tmp/servers/GilaMonster/backup-clones", "clones go beside the server, in GilaMonster's folder")

    section("Backup clones: the sweep removes leftovers and nothing else")
    let fm = FileManager.default
    let base = folder("clone-sweep")
    let clones = base.appendingPathComponent("servers/GilaMonster/backup-clones", isDirectory: true)
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    try! FileOps.ensureDir(clones)
    try! FileOps.ensureDir(outside)
    write("a world that must survive", outside.appendingPathComponent("level.dat"))
    func make(_ name: String, marked: Bool = true) -> URL {
        let url = clones.appendingPathComponent(name, isDirectory: true)
        try! FileOps.ensureDir(url.appendingPathComponent("world/region"))
        write("made up", url.appendingPathComponent("world/region/r.0.0.mca"))
        if marked, BackupClones.isCloneName(name) { check(BackupClones.mark(url), "a clone's mark is written") }
        return url
    }
    let leftover = make("made-up-server-1A2B3C4D")
    try! fm.createSymbolicLink(at: leftover.appendingPathComponent("world_nether"), withDestinationURL: outside)
    _ = make("made-up-other-0a1b2c3d")
    let plain = make("keep-me")
    // Made before 0.6.1, or by something else: a clone's name and no mark. The owner decides on these (K527).
    let older = make("made-up-older-ABCDEF12", marked: false)
    // A mark that is a link doesn't count.
    let fakeMarked = make("made-up-faked-0F0F0F0F", marked: false)
    try! fm.createSymbolicLink(at: BackupClones.markURL(fakeMarked), withDestinationURL: outside.appendingPathComponent("level.dat"))
    let short = make("made-up-server-1A2B3C")
    write("a note", clones.appendingPathComponent("notes.txt"))
    write("a file with a clone's name", clones.appendingPathComponent("made-up-file-1A2B3C4D"))
    let link = clones.appendingPathComponent("made-up-linked-1A2B3C4D")
    try! fm.createSymbolicLink(at: link, withDestinationURL: outside)
    func names() -> [String] { ((try? fm.contentsOfDirectory(atPath: clones.path)) ?? []).sorted() }
    let before = names()

    let busy = BackupClones.sweep(clones, backupRunning: true)
    check(busy.removed.isEmpty && busy.skipped == "a backup is running", "with a backup running, nothing is removed")
    equal(names(), before, "and the folder is as it was")

    let wrong = BackupClones.sweep(clones.deletingLastPathComponent(), backupRunning: false)
    check(wrong.removed.isEmpty && wrong.skipped != nil && fm.fileExists(atPath: clones.path), "a folder that isn't backup-clones is refused")

    let done = BackupClones.sweep(clones, backupRunning: false)
    equal(done.removed, ["made-up-other-0a1b2c3d", "made-up-server-1A2B3C4D"], "the two leftover clones are removed")
    check(done.failed.isEmpty && done.skipped == nil, "with nothing failed")
    equal(names(), ["keep-me", "made-up-faked-0F0F0F0F", "made-up-faked-0F0F0F0F.gilamonster-clone", "made-up-file-1A2B3C4D", "made-up-linked-1A2B3C4D", "made-up-older-ABCDEF12", "made-up-server-1A2B3C", "notes.txt"], "everything else is still there, and the removed clones' marks went with them")
    equal(done.unmarked, ["made-up-faked-0F0F0F0F", "made-up-older-ABCDEF12"], "clones without a real mark are left alone and named")
    check(fm.fileExists(atPath: older.appendingPathComponent("world/region/r.0.0.mca").path), "an unmarked clone keeps its files")
    check(fm.fileExists(atPath: outside.appendingPathComponent("level.dat").path) && (try? fm.destinationOfSymbolicLink(atPath: BackupClones.markURL(fakeMarked).path)) != nil, "a linked mark is left as it is, and what it points at too")
    check(fm.fileExists(atPath: plain.appendingPathComponent("world/region/r.0.0.mca").path) && fm.fileExists(atPath: short.appendingPathComponent("world/region/r.0.0.mca").path), "other folders keep their files")
    check(fm.fileExists(atPath: outside.appendingPathComponent("level.dat").path), "a link inside a clone wasn't followed: what it pointed at is untouched")
    check((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil, "a link with a clone's name is left as a link")
    let line = done.line(clones) ?? ""
    check(line.contains("Removed 2 leftover backup clones") && line.contains("made-up-server-1A2B3C4D") && line.contains(clones.path), "the log line names what was removed and where (\(line))")
    let again = BackupClones.sweep(clones, backupRunning: false)
    check(again.removed.isEmpty && again.line(clones) == nil, "a second sweep finds nothing and says nothing")

    section("Backup clones: links and missing folders")
    let realElsewhere = base.appendingPathComponent("elsewhere/backup-clones", isDirectory: true)
    try! FileOps.ensureDir(realElsewhere.appendingPathComponent("made-up-server-1A2B3C4D"))
    let linkedHome = base.appendingPathComponent("linked/GilaMonster", isDirectory: true)
    try! FileOps.ensureDir(linkedHome)
    let linkedClones = linkedHome.appendingPathComponent("backup-clones")
    try! fm.createSymbolicLink(at: linkedClones, withDestinationURL: realElsewhere)
    let viaLink = BackupClones.sweep(linkedClones, backupRunning: false)
    check(viaLink.removed.isEmpty && viaLink.skipped != nil, "a backup-clones that is a link isn't followed")
    check(fm.fileExists(atPath: realElsewhere.appendingPathComponent("made-up-server-1A2B3C4D").path), "so what's behind it stays")
    let linkedParent = base.appendingPathComponent("linked-parent/GilaMonster")
    try! FileOps.ensureDir(linkedParent.deletingLastPathComponent())
    try! fm.createSymbolicLink(at: linkedParent, withDestinationURL: realElsewhere.deletingLastPathComponent())
    let viaParent = BackupClones.sweep(linkedParent.appendingPathComponent("backup-clones"), backupRunning: false)
    check(viaParent.removed.isEmpty && viaParent.skipped != nil && fm.fileExists(atPath: realElsewhere.appendingPathComponent("made-up-server-1A2B3C4D").path), "nor one reached through a linked GilaMonster folder")
    let missing = BackupClones.sweep(base.appendingPathComponent("nowhere/GilaMonster/backup-clones"), backupRunning: false)
    check(missing == BackupClones.Sweep() && !fm.fileExists(atPath: base.appendingPathComponent("nowhere").path), "no folder: nothing done, and nothing made")

    section("Backup clones: every server's folder, once")
    let s1 = base.appendingPathComponent("servers/made-up-server"), s2 = base.appendingPathComponent("servers/made-up-other"), s3 = base.appendingPathComponent("more/made-up-third")
    _ = make("made-up-server-9F8E7D6C")
    let third = BackupClones.folder(besideServer: s3).appendingPathComponent("made-up-third-00000000")
    try! FileOps.ensureDir(third)
    check(BackupClones.mark(third), "the third server's clone is marked")
    let both = BackupClones.sweep(besideServers: [s1, s2, s3], backupRunning: false)
    equal(both.count, 2, "two servers in one folder share a clones folder, swept once")
    equal(both.flatMap(\.result.removed).sorted(), ["made-up-server-9F8E7D6C", "made-up-third-00000000"], "and a server kept elsewhere has its own swept too")
    check(BackupClones.sweep(besideServers: [s1, s3], backupRunning: true).allSatisfy { $0.result.removed.isEmpty }, "none of it while a backup runs")
    _ = make("made-up-gone-0000AAAA")
    let listless = BackupClones.sweep(besideServers: [], serversFolder: base.appendingPathComponent("servers"), backupRunning: false)
    equal(listless.flatMap(\.result.removed), ["made-up-gone-0000AAAA"], "the servers folder is swept even for a server no longer on the list")

    section("Backup clones: wired in")
    let core = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonsterCore")
    let saving = (try? String(contentsOf: core.appendingPathComponent("ServerController+Saving.swift"), encoding: .utf8)) ?? ""
    check(saving.contains("BackupClones.folder(besideServer: paths.root)") && saving.contains("BackupClones.newName(forServer: paths.root)"), "a backup's clone is made where the sweep looks, with the name it knows")
    check(saving.contains("guard BackupClones.mark(folder) else { Self.removeClone(folder); return nil }") && saving.contains("BackupClones.unmark(folder)"), "each new clone is marked before anything is copied, and the mark goes with it")
    let model = (try? String(contentsOf: core.deletingLastPathComponent().appendingPathComponent("GilaMonster/AppModel.swift"), encoding: .utf8)) ?? ""
    check(model.contains("BackupClones.sweep(besideServers: servers.map(\\.paths.root), serversFolder: AppPaths.servers, backupRunning: Backups.writing || Self.anotherCopyIsRunning)"), "the app sweeps at launch, and not while a backup or another copy of the app runs")
    check(model.contains("Self.cloneLog.notice"), "and logs what it removed")
}
