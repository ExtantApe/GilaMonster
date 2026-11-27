import Foundation
@testable import GilaMonsterCore

/// A made-up GilaMonster backup: a placeholder archive with GilaMonster's record beside it, as a listing reads it.
/// Nothing is packed. Returns the record.
@discardableResult
func writeMadeUpBackup(in folder: URL, madeAt date: Date, serverName: String, trigger: String = "after-play", size: Int64 = 412_000_000) -> BackupRecord {
    try? FileOps.ensureDir(folder)
    let name = "\(Backups.stamp(date))_\(trigger).tar.gz"
    let record = BackupRecord(fileName: name, date: date, size: size, scope: .everything, trigger: trigger,
                              software: "Paper 26.3", mcVersion: "26.3", serverName: serverName)
    let archive = folder.appendingPathComponent(name)
    write("made-up archive", archive)
    try! JSONStore.encoder.encode(record).write(to: Backups.sidecar(for: archive), options: .atomic)
    return record
}

/// Backup ages are GilaMonster's own, and say so (K823). GilaMonster lists only the backups it made, in this server's
/// folder and the storage folders the owner added, so another tool's fresher backups never change an age it shows.
@MainActor func backupSeenChecks() {
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    func source(_ name: String) -> String { (try? String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    // Whole seconds: a backup's record keeps its date to the second.
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let hour: TimeInterval = 3600

    section("Backup ages: labelled as GilaMonster's own (K823)")
    let fact = NeedsYou.factLine(software: "Paper 26.3", running: true, since: now.addingTimeInterval(-2 * hour), lastBackup: now.addingTimeInterval(-23 * hour), isLab: false, needs: 0, openIssues: 0, now: now)
    check(fact.contains(" · GilaMonster backup ") && !fact.contains("backed up"), "the Overview's line names whose backup the age is (\(fact))")
    equal(NeedsYou.factLine(software: "Paper 26.3", running: false, since: nil, lastBackup: nil, isLab: false, needs: 1, openIssues: 0, now: now),
          "Paper 26.3 · no GilaMonster backup yet · 1 thing needs you", "with none, it says GilaMonster has made none, and claims nothing about other tools")
    let status = NeedsYou.statusLine(running: false, starting: false, since: nil, players: 0, software: "Paper", lastBackup: now.addingTimeInterval(-23 * hour), isLab: false, now: now)
    check(status.contains("Last GilaMonster backup "), "the status line does too (\(status))")
    var facts = NeedsYouFacts(); facts.autoBackups = true
    let none = NeedsYou.items(facts).first { $0.kind == .noBackup }
    equal(none?.title, "No GilaMonster backup yet", "Needs you: the item says whose backup is missing")
    check(none?.detail.contains("It can't see backups other tools make.") == true, "and that other tools' backups can't be seen")
    check(none?.detail.contains("Nothing to restore") == false, "it no longer says there is nothing at all to restore, which GilaMonster can't know")
    equal(none?.action, .backUpNow, "Back Up Now is still its button")
    check(!NeedsYou.items(facts).contains { $0.title.lowercased().contains("old") }, "there is no old-backup item, so a fresh backup elsewhere has nothing to silence")
    check(!NeedsYou.factLine(software: "Paper", running: false, since: nil, lastBackup: nil, isLab: true, needs: 0, openIssues: 0, now: now).contains("backup"), "the Lab still has no backup words")

    section("Backup ages: only what GilaMonster made is counted (K823)")
    // A made-up server with its own backup folder, one storage folder it was given, and another tool's folder.
    let root = folder("backup-seen")
    var profile = ServerProfile()
    profile.name = "Made-up Seen"
    let own = root.appendingPathComponent("own", isDirectory: true)
    let storage = root.appendingPathComponent("made-up-drive", isDirectory: true)
    try? FileOps.ensureDir(storage)
    profile.backup.destination = own.path
    try? Backups.claim(own, for: profile.id)
    writeMadeUpBackup(in: own, madeAt: now.addingTimeInterval(-23 * hour), serverName: profile.name)
    // Another tool's backups, newer than GilaMonster's: dated folders in a place nobody gave GilaMonster, the same
    // kind of folder inside its own backup folder, and an archive with no GilaMonster record beside it.
    let elsewhere = root.appendingPathComponent("other-tool/play", isDirectory: true)
    let foreign = [elsewhere.appendingPathComponent("madeup-20261126-220925/world/level.dat"),
                   own.appendingPathComponent("madeup-20261126-221500/world/level.dat"),
                   own.appendingPathComponent("other-tool-newest.tar.gz")]
    for file in foreign { write("made up, from another tool", file) }
    var listed = Backups.listAll(profile)
    equal(listed.count, 1, "another tool's folders and archives aren't listed, even inside GilaMonster's own backup folder")
    equal(listed.first.map { Int(now.timeIntervalSince($0.date).rounded()) }, Int(23 * hour), "so the newest backup GilaMonster reports is its own, 23 hours old")
    check(foreign.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "listing left the other tool's files alone")

    // A storage folder the owner added is counted, once GilaMonster has a backup there.
    profile.backup.smart.targets = [storage.path]
    let there = Backups.targetFolder(storage.path, for: profile)
    equal(BackupSeen.storageLine(newest: BackupSeen.newestByFolder(Backups.listAll(profile))[there.path], readable: true, now: now),
          "No GilaMonster backup here yet.", "an added storage folder with nothing of GilaMonster's says so")
    write("made up, from another tool", storage.appendingPathComponent("madeup-20261126-223000/world/level.dat"))
    equal(Backups.listAll(profile).count, 1, "another tool's folder inside the added storage isn't counted either")
    try? Backups.claim(there, for: profile.id)
    writeMadeUpBackup(in: there, madeAt: now.addingTimeInterval(-4 * 24 * hour), serverName: profile.name)
    writeMadeUpBackup(in: there, madeAt: now.addingTimeInterval(-2 * hour), serverName: profile.name)
    listed = Backups.listAll(profile)
    equal(listed.count, 3, "GilaMonster's backups in the added storage are listed with its own folder's")
    equal(listed.first?.location, there.path, "and the newest of them all is the one the Overview's age comes from")
    let newest = BackupSeen.newestByFolder(listed)
    equal(newest.count, 2, "each folder with a GilaMonster backup has its own newest time")
    equal(newest[own.path].map { Int(now.timeIntervalSince($0).rounded()) }, Int(23 * hour), "the server's own folder: 23 hours")
    equal(newest[there.path].map { Int(now.timeIntervalSince($0).rounded()) }, Int(2 * hour), "the added storage: its newest, 2 hours, and the 4-day-old one doesn't replace it")
    check(newest[elsewhere.path] == nil && newest[storage.path] == nil, "a folder GilaMonster wasn't given has no time at all")
    let line = BackupSeen.storageLine(newest: newest[there.path], readable: true, now: now) ?? ""
    check(line.hasPrefix("Newest GilaMonster backup here: ") && line.hasSuffix("."), "the storage row's line (\(line))")
    check(BackupSeen.storageLine(newest: now, readable: false, now: now) == nil, "a drive that isn't connected gets no line: what's on it is unknown")
    equal(BackupSeen.newestByFolder([BackupRecord(fileName: "a", date: now, size: 1, scope: .worlds, trigger: "t", software: "", mcVersion: "", serverName: "")]).count, 0,
          "a record with no folder is never guessed a place")

    section("Backup ages: the pages use those words (K823)")
    let overview = source("OverviewPage.swift"), backups = source("BackupsPage.swift")
    check(overview.contains("Fact(label: BackupSeen.latestLabel") && !overview.contains("Fact(label: \"Latest\""), "the Overview's Backups card labels its age as GilaMonster's latest")
    check(overview.contains("Hint(BackupSeen.cardNote)"), "and says other tools' backups aren't counted")
    check(backups.contains("Hint(BackupSeen.listNote)"), "the Backups page says the same under its list")
    check(backups.contains("BackupSeen.storageLine(newest: newest[folders[index]]") && backups.contains("DriveCheck.isConnected"), "each storage row shows its own newest backup, only for a connected drive")
    equal(BackupSeen.latestLabel, "GilaMonster's latest", "the card's label")
    for text in [BackupSeen.cardNote, BackupSeen.listNote] { check(text.contains("other tools"), "the note names other tools (\(text))") }
}
