import Darwin
import Foundation
@testable import GilaMonsterCore

/// A backup drill's throwaway server never outlives GilaMonster (K813). Everything here is made up and lives in the
/// suite's own temp folder. The only processes signalled are ones these checks started themselves.

/// Names, marks and the launch sweep, with no Java: which folders are GilaMonster's drill copies, and which process
/// may be signalled.
@MainActor func drillCopyChecks() {
    section("Backup drills: which folders are GilaMonster's drill copies")
    let fm = FileManager.default
    check(DrillCopies.isDrillName("drill-made-up-server-1795000000"), "drill-, the server's folder and the time")
    check(DrillCopies.isDrillName(DrillCopies.newName(forServer: URL(fileURLWithPath: "/tmp/Made Up Server"))), "the name a new drill copy gets")
    for name in ["made-up-server-1795000000", "drill-1795000000", "drill--1795000000", "drill-made-up-server", "drill-made-up-server-", "drill-made-up-server-17950000x0",
                 "drill-made-up-server-1795000000.zip", "Drill-made-up-server-1795000000", ""] {
        check(!DrillCopies.isDrillName(name), "\"\(name)\" isn't a drill copy's name")
    }
    equal(DrillCopies.folder(besideServer: URL(fileURLWithPath: "/tmp/servers/made-up-server")).path, "/tmp/servers/GilaMonster/test-copies", "drills unpack beside the server, in GilaMonster's folder")
    equal(DrillCopies.folder(besideBackups: URL(fileURLWithPath: "/tmp/backups/made-up-server")).path, "/tmp/backups/made-up-server/.test-copies", "or beside the backup")

    section("Backup drills: a copy is marked when it's made, and removed with its mark")
    DrillCopies.reopen()
    defer { DrillCopies.reopen() }
    let base = folder("drill-sweep")
    let copies = base.appendingPathComponent("servers/GilaMonster/test-copies", isDirectory: true)
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    try! FileOps.ensureDir(outside)
    write("a world that must survive", outside.appendingPathComponent("level.dat"))
    let fresh = copies.appendingPathComponent("drill-made-up-server-1795000001", isDirectory: true)
    check(DrillCopies.begin(fresh), "a new drill copy is made")
    check(DrillCopies.isMarkedCopy(fresh) && fm.fileExists(atPath: DrillCopies.markURL(fresh).path), "with its mark beside it")
    equal(DrillCopies.live.map(\.path), [fresh.path], "and it's listed as running")
    check(!DrillCopies.begin(fresh), "a copy is never made over one that's there")
    equal(DrillCopies.sweep(copies, otherCopyRunning: false).removed, [], "the sweep leaves a drill this GilaMonster is running")
    check(fm.fileExists(atPath: fresh.path), "and its folder is still there")
    DrillCopies.finish(fresh)
    check(!fm.fileExists(atPath: fresh.path) && !fm.fileExists(atPath: DrillCopies.markURL(fresh).path) && DrillCopies.live.isEmpty, "finishing removes the copy, its mark and its listing")
    check(!DrillCopies.begin(copies.appendingPathComponent("made-up-server-1795000001")), "a folder without a drill's name is never made or marked")
    DrillCopies.close()
    let late = copies.appendingPathComponent("drill-made-up-server-1795000002", isDirectory: true)
    check(!DrillCopies.begin(late) && !fm.fileExists(atPath: late.path) && !fm.fileExists(atPath: DrillCopies.markURL(late).path), "once GilaMonster is quitting, no drill copy is made")
    DrillCopies.reopen()
    // A tar still unpacking into a copy is stopped when GilaMonster starts quitting. A sleep stands in for the tar.
    let unpacking = copies.appendingPathComponent("drill-made-up-server-1795000003", isDirectory: true)
    check(DrillCopies.begin(unpacking), "a copy to unpack into")
    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/bin/sleep")
    tar.arguments = ["120"]
    try! tar.run()
    defer { if tar.isRunning { tar.terminate(); tar.waitUntilExit() } }
    DrillCopies.unpacking(unpacking, with: tar)
    DrillCopies.close()
    for _ in 0..<50 where tar.isRunning { Thread.sleep(forTimeInterval: 0.1) }
    check(!tar.isRunning, "quitting stops what's unpacking into a drill copy")
    equal(DrillCopies.endAll(patience: 1).map(\.result), [.removed(stopped: nil)], "and removes the copy")
    check(!fm.fileExists(atPath: unpacking.path) && !fm.fileExists(atPath: DrillCopies.markURL(unpacking).path) && DrillCopies.live.isEmpty, "with its mark and its listing")
    DrillCopies.reopen()

    section("Backup drills: the launch sweep removes leftover copies and nothing else")
    func mark(_ url: URL) { write("made up", DrillCopies.markURL(url)) }
    func make(_ name: String, marked: Bool) -> URL {
        let url = copies.appendingPathComponent(name, isDirectory: true)
        try! FileOps.ensureDir(url.appendingPathComponent("world/region"))
        write("made up", url.appendingPathComponent("world/region/r.0.0.mca"))
        if marked { mark(url) }
        return url
    }
    func pidFile(_ copy: URL, _ text: String) {
        try! FileOps.ensureDir(ServerPaths(root: copy).meta)
        write(text, ServerPaths(root: copy).pid)
    }
    let leftover = make("drill-made-up-server-1795000010", marked: true)
    try! fm.createSymbolicLink(at: leftover.appendingPathComponent("world_nether"), withDestinationURL: outside)
    // No mark: made by an older GilaMonster, or by someone else. Left for the owner.
    let unmarked = make("drill-made-up-older-1795000011", marked: false)
    // A test copy that isn't a drill, even with a mark planted beside it.
    let trial = make("made-up-server-1795000012", marked: true)
    // A mark that is a link doesn't count.
    let fakeMarked = make("drill-made-up-faked-1795000013", marked: false)
    try! fm.createSymbolicLink(at: DrillCopies.markURL(fakeMarked), withDestinationURL: outside.appendingPathComponent("level.dat"))
    // A link with a drill's name and a mark: never followed, never removed.
    let link = copies.appendingPathComponent("drill-made-up-linked-1795000014")
    try! fm.createSymbolicLink(at: link, withDestinationURL: outside)
    mark(link)
    write("a file with a drill's name", copies.appendingPathComponent("drill-made-up-file-1795000015"))
    mark(copies.appendingPathComponent("drill-made-up-file-1795000015"))
    // A mark whose copy is already gone.
    mark(copies.appendingPathComponent("drill-made-up-gone-1795000016"))
    write("a note", copies.appendingPathComponent("notes.txt"))
    // Pid files that name something else. None of these may be signalled.
    let ownPid = make("drill-made-up-self-1795000020", marked: true)
    pidFile(ownPid, "\(getpid())")
    let initPid = make("drill-made-up-init-1795000021", marked: true)
    pidFile(initPid, "1")
    let nonsense = make("drill-made-up-nonsense-1795000022", marked: true)
    pidFile(nonsense, "not a number\n")
    // A program that isn't Java, working in a drill copy and named by its pid file: left running.
    let squatted = make("drill-made-up-squatted-1795000023", marked: true)
    let sleeper = Process()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["120"]
    sleeper.currentDirectoryURL = squatted
    try! sleeper.run()
    defer { if sleeper.isRunning { sleeper.terminate(); sleeper.waitUntilExit() } }
    pidFile(squatted, "\(sleeper.processIdentifier)")
    check(!DrillCopies.isDrillJava(pid: sleeper.processIdentifier, copy: squatted), "a program that isn't Java isn't a drill's Java, even working in the copy")
    check(DrillCopies.javaPID(in: squatted) == nil && DrillCopies.javaPID(in: ownPid) == nil && DrillCopies.javaPID(in: initPid) == nil && DrillCopies.javaPID(in: nonsense) == nil,
          "a pid file naming this program, process 1, nonsense or another program names no Java to stop")

    func names() -> [String] { ((try? fm.contentsOfDirectory(atPath: copies.path)) ?? []).sorted() }
    let before = names()
    let busy = DrillCopies.sweep(copies, otherCopyRunning: true)
    check(busy.removed.isEmpty && busy.skipped == "another GilaMonster is running", "with another GilaMonster running, nothing is removed")
    equal(names(), before, "and the folder is as it was")
    let wrong = DrillCopies.sweep(copies.deletingLastPathComponent(), otherCopyRunning: false)
    check(wrong.removed.isEmpty && wrong.skipped != nil && names() == before, "a folder that isn't test-copies is refused")
    equal(DrillCopies.stopAndRemove(unmarked), .notOurs, "an unmarked folder is refused outright")
    equal(DrillCopies.stopAndRemove(trial), .notOurs, "and so is a marked folder without a drill's name")
    equal(DrillCopies.stopAndRemove(link), .notOurs, "and a link")

    let done = DrillCopies.sweep(copies, otherCopyRunning: false, patience: 2)
    equal(done.removed, ["drill-made-up-init-1795000021", "drill-made-up-nonsense-1795000022", "drill-made-up-self-1795000020", "drill-made-up-server-1795000010", "drill-made-up-squatted-1795000023"],
          "the marked leftover copies are removed")
    equal(done.stopped, [], "and nothing was signalled for them")
    check(done.failed.isEmpty && done.skipped == nil, "with nothing failed")
    equal(done.unmarked, ["drill-made-up-faked-1795000013", "drill-made-up-older-1795000011"], "copies without a real mark are left alone and named")
    equal(names(), ["drill-made-up-faked-1795000013", "drill-made-up-faked-1795000013.gilamonster-drill", "drill-made-up-file-1795000015", "drill-made-up-file-1795000015.gilamonster-drill",
                    "drill-made-up-linked-1795000014", "drill-made-up-linked-1795000014.gilamonster-drill", "drill-made-up-older-1795000011",
                    "made-up-server-1795000012", "made-up-server-1795000012.gilamonster-drill", "notes.txt"],
          "everything else is still there, and the removed copies' marks and the stray mark went with them")
    check(fm.fileExists(atPath: unmarked.appendingPathComponent("world/region/r.0.0.mca").path), "an unmarked folder keeps its files")
    check(fm.fileExists(atPath: trial.appendingPathComponent("world/region/r.0.0.mca").path), "a test copy that isn't a drill keeps its files")
    equal(try? String(contentsOf: outside.appendingPathComponent("level.dat"), encoding: .utf8), "a world that must survive", "nothing a link points at was touched")
    check(sleeper.isRunning, "the other program named by a stale pid file is still running")
    check(kill(getpid(), 0) == 0, "and so is this one")
    check(done.line(copies)?.hasPrefix("Removed 5 leftover backup drill copies from ") == true, "the log line says what was removed")
    equal(DrillCopies.Sweep().line(copies), nil, "and nothing is logged when there was nothing to do")

    // Beside a backup: the folder goes once it's empty, and stays while anything is in it.
    let backups = base.appendingPathComponent("backups/made-up-server", isDirectory: true)
    let beside = DrillCopies.folder(besideBackups: backups)
    let besideCopy = beside.appendingPathComponent("drill-made-up-server-1795000030", isDirectory: true)
    try! FileOps.ensureDir(besideCopy.appendingPathComponent("world"))
    mark(besideCopy)
    write("made up", backups.appendingPathComponent("made-up-backup.tar.gz"))
    let swept = DrillCopies.sweep(besideServers: [base.appendingPathComponent("servers/made-up-server")], serversFolder: base.appendingPathComponent("servers"),
                                  backupFolders: [backups, backups], otherCopyRunning: false, patience: 2)
    equal(swept.count, 2, "each place is swept once")
    equal(swept.last?.result.removed, ["drill-made-up-server-1795000030"], "a leftover beside a backup is removed")
    check(!fm.fileExists(atPath: beside.path) && fm.fileExists(atPath: backups.appendingPathComponent("made-up-backup.tar.gz").path), "its empty folder goes, and the backup beside it stays")
    check(fm.fileExists(atPath: copies.path), "the usual folder stays, since other things are in it")

    section("Backup drills: every way out of the app ends them (from the source)")
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let model = (try? String(contentsOf: sources.appendingPathComponent("GilaMonster/AppModel.swift"), encoding: .utf8)) ?? ""
    check(model.contains("for server in servers {\n            // A backup drill's throwaway server isn't on the list, and used to be left running (K813).\n            server.stopDrill(by: source)"),
          "stopping every server stops each server's drill first")
    check(model.contains("where anyLive { try? await Task.sleep(for: .milliseconds(250)) }\n        DrillCopies.endAll()\n    }"), "and ends with the drills stopped and their copies removed")
    check(model.contains("await model.stopAll(by: .signal(name))\n            // Nothing runs between this and the exit, so no drill can start in the gap (K813).\n            DrillCopies.endAll()\n            exit(0)"),
          "a quit signal ends the drills right before the exit")
    check(model.contains("func applicationWillTerminate(_ notification: Notification) {\n        Backups.cancelInFlight(wait: 2)\n        DrillCopies.endAll()"), "an ordinary quit ends them as the app terminates")
    check(model.contains("Self.signalSources = QuitSignals.watch { sig in MainActor.assumeIsolated { AppDelegate.quitOnSignal(sig) } }"), "the app watches the same signals the check sends")
    check(model.contains("DrillCopies.sweep(besideServers: roots, serversFolder: servers, backupFolders: backupFolders, otherCopyRunning: otherCopy)"), "and sweeps for leftover drills at launch")
    let deep = (try? String(contentsOf: sources.appendingPathComponent("GilaMonsterCore/ServerController+Deep.swift"), encoding: .utf8)) ?? ""
    check(deep.contains("DrillCopies.finish(folder)\n            if base == beside { DrillCopies.removeIfEmpty(beside) }") && !deep.contains("removeItem(at: beside)"),
          "a finished drill removes its own marked copy, and its folder only when empty")
}

/// One line at a time from a helper's output.
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func add(_ data: Data) { lock.lock(); text += String(decoding: data, as: UTF8.self); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return text.split(separator: "\n").map(String.init) }
}

/// The real thing, with the stand-in jar: a Java left running in a marked drill copy is stopped by the launch sweep, a
/// Java named by a stale pid file is left running, and a GilaMonster told to quit by a signal takes its drill with it.
@MainActor func drillCopyLifecycle(jar: URL, jdk: JavaRuntime) async {
    let fm = FileManager.default
    DrillCopies.reopen()
    defer { DrillCopies.reopen() }
    var started: [Process] = []
    defer { for p in started where p.isRunning { p.terminate(); p.waitUntilExit() } }
    func standIn(in root: URL, port: Int) throws -> Process {
        try FileOps.ensureDir(root.appendingPathComponent("plugins"))
        try fm.copyItem(at: jar, to: root.appendingPathComponent("standin.jar"))
        write("server-port=\(port)\nserver-ip=127.0.0.1\nmotd=made up\nlevel-name=world\n", root.appendingPathComponent("server.properties"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: jdk.path)
        p.arguments = ["-Xmx64M", "-jar", "standin.jar"]
        p.currentDirectoryURL = root
        p.standardInput = Pipe()   // kept open, so the stand-in waits as a server does
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        started.append(p)
        return p
    }

    section("Backup drills: the launch sweep stops a leftover drill's Java (stand-in jar)")
    do {
        let base = folder("drill-leftover")
        let copies = base.appendingPathComponent("servers/GilaMonster/test-copies", isDirectory: true)
        // The leftover: a marked copy with its Java still running and its pid file, as after a force quit.
        let leftover = copies.appendingPathComponent("drill-made-up-server-1795000100", isDirectory: true)
        let orphan = try standIn(in: leftover, port: 25597)
        write("made up", DrillCopies.markURL(leftover))
        try JSONStore.save(orphan.processIdentifier, to: ServerPaths(root: leftover).pid)
        // A server that isn't a drill, and a copy whose stale pid file names it. A copy unpacked from a backup taken
        // while the server ran can carry exactly this.
        let real = base.appendingPathComponent("servers/made-up-server", isDirectory: true)
        let other = try standIn(in: real, port: 25596)
        let stale = copies.appendingPathComponent("drill-made-up-server-1795000101", isDirectory: true)
        try FileOps.ensureDir(stale.appendingPathComponent("world"))
        write("made up", DrillCopies.markURL(stale))
        try JSONStore.save(other.processIdentifier, to: ServerPaths(root: stale).pid)
        // A folder with a drill's name and no mark, with a Java of its own. Not GilaMonster's: left running.
        let unmarked = copies.appendingPathComponent("drill-made-up-other-1795000102", isDirectory: true)
        try FileOps.ensureDir(unmarked)
        try JSONStore.save(other.processIdentifier, to: ServerPaths(root: unmarked).pid)

        await checkUntil(20, "the leftover drill's Java is up, working in its copy") { DrillCopies.isDrillJava(pid: orphan.processIdentifier, copy: leftover) }
        await checkUntil(20, "and the other server's Java is up in its own folder") { DrillCopies.isDrillJava(pid: other.processIdentifier, copy: real) }
        equal(DrillCopies.javaPID(in: leftover), orphan.processIdentifier, "the leftover's pid file names its Java")
        equal(DrillCopies.javaPID(in: stale), nil, "a stale pid file that names another server's Java names nothing to stop")
        check(!DrillCopies.isDrillJava(pid: other.processIdentifier, copy: stale), "that Java works in another folder, so it isn't this copy's")

        let done = DrillCopies.sweep(copies, otherCopyRunning: false, patience: 10)
        equal(done.removed, ["drill-made-up-server-1795000100", "drill-made-up-server-1795000101"], "both marked copies are removed")
        equal(done.stopped, ["drill-made-up-server-1795000100"], "and only the leftover's own Java was stopped")
        equal(done.unmarked, ["drill-made-up-other-1795000102"], "the unmarked folder is left alone and named")
        check(done.failed.isEmpty, "nothing failed")
        await checkUntil(10, "the leftover drill's Java has exited") { !orphan.isRunning }
        check(!fm.fileExists(atPath: leftover.path) && !fm.fileExists(atPath: DrillCopies.markURL(leftover).path), "its copy and mark are gone")
        check(!fm.fileExists(atPath: stale.path), "the copy with the stale pid file is gone")
        check(other.isRunning && DrillCopies.isDrillJava(pid: other.processIdentifier, copy: real), "the Java its stale pid file named was not signalled: it's still running")
        check(fm.fileExists(atPath: ServerPaths(root: unmarked).pid.path), "the unmarked folder is as it was")
        check(fm.fileExists(atPath: real.appendingPathComponent("standin.jar").path), "and the other server's folder was not touched")
        check(done.line(copies)?.contains("Stopped the Java still running in drill-made-up-server-1795000100 first") == true, "the log line says a Java was stopped")
        other.terminate()
        await checkUntil(20, "the check's own stand-in server stopped at the end") { !other.isRunning }
    } catch { failures.append("drill leftover: \(error)") }

    // A second copy of this program plays GilaMonster: it runs a real drill and is told to quit by a signal.
    for (signalName, sig, how) in [("SIGTERM", SIGTERM, "stop"), ("SIGHUP", SIGHUP, "terminate")] {
        section("Backup drills: \(signalName) to GilaMonster stops its drill (stand-in jar, \(how == "stop" ? "servers being stopped" : "nothing else running"))")
        guard let program = Bundle.main.executableURL else { check(false, "this program's own path is known"); continue }
        let base = folder("drill-signal-\(signalName)")
        let helper = Process()
        helper.executableURL = program
        helper.arguments = ["--drill-signal-child", base.path, jdk.path, String(jdk.major), jar.path, how]
        let out = Pipe()
        let lines = Lines()
        out.fileHandleForReading.readabilityHandler = { lines.add($0.availableData) }
        helper.standardOutput = out
        helper.standardError = FileHandle.nullDevice
        do { try helper.run() } catch { check(false, "the helper started: \(error)"); continue }
        started.append(helper)
        defer { out.fileHandleForReading.readabilityHandler = nil }
        func up() -> (pid: Int32, copy: URL)? {
            guard let line = lines.all.first(where: { $0.hasPrefix("DRILL-UP ") }) else { return nil }
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3, let pid = Int32(parts[1]) else { return nil }
            return (pid, URL(fileURLWithPath: parts[2], isDirectory: true))
        }
        guard await until(90, { up() != nil || !helper.isRunning }), let drill = up() else {
            check(false, "the helper's drill came up: \(lines.all.suffix(3))")
            continue
        }
        let server = base.appendingPathComponent("servers/made-up-drill-server", isDirectory: true)
        check(DrillCopies.isDrillJava(pid: drill.pid, copy: drill.copy), "the drill's Java is running in its copy")
        check(DrillCopies.isMarkedCopy(drill.copy), "the copy is marked as GilaMonster's own")
        check(drill.copy.path.hasPrefix(base.path) && drill.copy.deletingLastPathComponent().lastPathComponent == ".test-copies", "and sits beside the backup, inside this check's folder")
        // The helper is a process this check started.
        kill(helper.processIdentifier, sig)
        await checkUntil(30, "the helper quit after \(signalName)") { !helper.isRunning }
        equal(helper.isRunning ? -1 : helper.terminationStatus, 0, "with a clean exit")
        check(!lines.all.contains("DRILL-ENDED") && !lines.all.contains("NOT-SIGNALLED"), "while its drill was still running")
        // Looked for by number alone: with its copy removed, a Java left running would no longer read as that copy's.
        await checkUntil(15, "the drill's Java is gone, not left running without GilaMonster") { !SystemInfo.isAlive(pid: drill.pid) }
        check(!fm.fileExists(atPath: drill.copy.path), "the drill's copy was removed")
        check(!fm.fileExists(atPath: DrillCopies.markURL(drill.copy).path), "and its mark")
        check(fm.fileExists(atPath: server.appendingPathComponent("standin.jar").path), "the server it was a drill for was not touched")
        let backup = lines.all.first { $0.hasPrefix("BACKUP ") }.map { String($0.dropFirst(7)) } ?? ""
        check(backup.hasPrefix(base.path) && fm.fileExists(atPath: backup), "and its backup is still there")
        // Only if the check failed: the Java it left is this check's own (the helper's child, still Java and still
        // working in this check's folder), and is stopped here so nothing outlives the run.
        if SystemInfo.isAlive(pid: drill.pid), SystemInfo.executablePath(pid: drill.pid).map({ URL(fileURLWithPath: $0).lastPathComponent == "java" }) == true,
           let cwd = SystemInfo.workingDirectory(pid: drill.pid), DrillCopies.resolved(cwd).hasPrefix(DrillCopies.resolved(base)) {
            kill(drill.pid, SIGKILL)
        }
    }
}

/// `--drill-signal-child <folder> <java> <java major> <stand-in jar> <stop|terminate>`: plays GilaMonster for the check above. It
/// makes a made-up server in <folder>, backs it up, runs a real drill on the backup, says when the drill's Java is up,
/// and then waits to be told to quit by a signal. On the signal it does what the app does: `stop` is what
/// `AppModel.stopAll` does about drills, `terminate` is what `applicationWillTerminate` does.
@MainActor func runDrillSignalChild(_ args: [String]) async -> Never {
    guard args.count == 5, let major = Int(args[2]) else { print("usage: --drill-signal-child <folder> <java> <java major> <stand-in jar> <stop|terminate>"); exit(2) }
    let dir = URL(fileURLWithPath: args[0], isDirectory: true)
    setenv("GILAMONSTER_HOME", dir.appendingPathComponent("home").path, 1)
    setenv("GILAMONSTER_SERVERS", dir.appendingPathComponent("servers").path, 1)
    do {
        let root = dir.appendingPathComponent("servers/made-up-drill-server", isDirectory: true)
        try FileOps.ensureDir(root.appendingPathComponent("plugins"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: args[3]), to: root.appendingPathComponent("standin.jar"))
        write("server-port=25596\nserver-ip=127.0.0.1\nmotd=made up\nlevel-name=world\n", root.appendingPathComponent("server.properties"))
        // The stand-in takes 15 seconds to start with this, so the drill is still booting when the signal comes.
        write("x", root.appendingPathComponent("slow-boot"))
        // A real server keeps running when GilaMonster goes away and its console closes. So does the stand-in, with this.
        write("x", root.appendingPathComponent("outlive-console"))
        let c = try await ServerController.adopt(root: root, name: "Made-up Drill Server")
        c.requiresEULA = false
        c.profile.software.flavor = .custom
        c.profile.software.jarName = "standin.jar"
        c.profile.software.mcVersion = "1.21.11"
        c.profile.software.lastCheck = Date()
        c.profile.lastPluginCheck = Date()
        c.profile.software.requiredJava = major
        c.profile.launch.javaPath = args[1]
        c.profile.launch.preset = .none
        c.profile.launch.minMemoryMB = 64
        c.profile.launch.maxMemoryMB = 256
        c.profile.backup.enabled = false
        let record = try await c.backupNow(trigger: "manual", scope: .everything)
        print("BACKUP \(Backups.folder(of: record, profile: c.profile).appendingPathComponent(record.fileName).path)"); fflush(stdout)
        let how = args[4]
        let watching = QuitSignals.watch { sig in
            MainActor.assumeIsolated {
                if how == "stop" { c.stopDrill(by: .signal(QuitSignals.name(sig))) }
                DrillCopies.endAll()
                exit(0)
            }
        }
        Task { @MainActor in
            await c.runBackupDrill(record)
            print("DRILL-ENDED \(c.profile.lastDrill?.detail ?? "")"); fflush(stdout)
        }
        for _ in 0..<240 {
            if let copy = DrillCopies.live.first, let pid = DrillCopies.javaPID(in: copy) {
                print("DRILL-UP \(pid) \(copy.path)"); fflush(stdout)
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .seconds(60))
        withExtendedLifetime(watching) {}
        print("NOT-SIGNALLED"); fflush(stdout)
        DrillCopies.endAll()
        exit(3)
    } catch {
        print("FAILED \(error)"); fflush(stdout)
        DrillCopies.endAll()
        exit(1)
    }
}
