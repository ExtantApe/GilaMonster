import Foundation
@testable import GilaMonsterCore

/// A snapshot run starts nothing (K829). With `GILAMONSTER_SNAPSHOT` set the app only draws pages, so its ticker,
/// its schedules, its launch-time work and every way of starting Java have to stand down, and they all ask
/// `AppMode.isSnapshot`. These read the source, so a new timer can't forget to ask, and then try each refusal on a
/// made-up server in the suite's temp folder. Nothing here starts Java or opens a port.
@MainActor func snapshotGateChecks() async {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    var files: [String: String] = [:]   // "GilaMonsterCore/Lab.swift" -> its text
    for target in ["GilaMonster", "GilaMonsterCore", "GilaMonsterAdvisor"] {
        for file in FileOps.children(sources.appendingPathComponent(target)) where file.pathExtension == "swift" {
            files["\(target)/\(file.lastPathComponent)"] = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }
    }
    check(files.count > 60, "the app's sources were read (\(files.count) files)")

    section("Snapshot: the mode is read in one place (K829)")
    let raw = "environment[\"GILAMONSTER_SNAPSHOT\"]"
    let readers = files.filter { $0.value.contains(raw) }.keys.sorted()
    equal(readers, [], "no file reads GILAMONSTER_SNAPSHOT for itself; they ask AppMode")
    check(files["GilaMonsterCore/AppMode.swift"]?.contains("environment[snapshotVariable]") == true, "AppMode reads it")
    equal(AppMode.snapshotVariable, "GILAMONSTER_SNAPSHOT", "under the name the snapshot script sets")

    section("Snapshot: every scheduled path asks the gate (K829)")
    // Each of these runs on a timer, on a schedule or at launch, or is a way of starting Java, a copy or a listener.
    // The gate has to be among the first lines of its body.
    let gated: [(file: String, opening: String, what: String)] = [
        ("GilaMonsterCore/ServerController.swift", "private func startTicker() {", "a server's ticker"),
        ("GilaMonsterCore/ServerController.swift", "func tick() async {", "a tick: scheduled backups and restarts, update checks, the weekly drill"),
        ("GilaMonsterCore/ServerController.swift", "public func start() async {", "starting a server"),
        ("GilaMonsterCore/ServerController.swift", "private func launch() {", "launching Java, as a crash restart or a restart after a stop does"),
        ("GilaMonsterCore/ServerController.swift", "public func backupNow(", "a backup"),
        ("GilaMonsterCore/ServerProcess.swift", "public func start() throws {", "the one place a server's Java process is run"),
        ("GilaMonsterCore/ServerController+Deep.swift", "public func runBackupDrill(", "a backup drill"),
        ("GilaMonsterCore/ServerController+Deep.swift", "public func startTrial(", "a test copy"),
        ("GilaMonsterCore/Lab.swift", "private func perform(", "a Lab run"),
        ("GilaMonsterCore/Lab.swift", "public func removeLeftover() async {", "clearing a left-over lab at launch"),
        ("GilaMonsterCore/LinksWeb.swift", "public func startLinksPage() throws {", "the links page and its hourly tidy"),
        ("GilaMonsterCore/PackHosting.swift", "public func startPackHostIfWanted() {", "the pack host"),
        ("GilaMonster/AppModel.swift", "func lookForAppUpdate() async {", "the look for a new GilaMonster, which reaches GitHub"),
        ("GilaMonster/AdvisorPage.swift", "func watch(_ model: AppModel) {", "the Advisor's ten-minute watch"),
    ]
    for site in gated {
        let text = files[site.file] ?? ""
        guard let at = text.range(of: site.opening) else { check(false, "\(site.what): \(site.opening) is still in \(site.file)"); continue }
        // The declaration can run over a line or two; the gate is within the first few lines after it.
        let body = text[at.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).prefix(5).joined(separator: "\n")
        check(body.contains("AppMode.isSnapshot"), "\(site.what) asks the gate first (\(site.opening))")
    }

    // What a launch starts by itself lives in one function, called only behind the gate, so the list above can't be
    // sidestepped by a new line in init.
    let model = files["GilaMonster/AppModel.swift"] ?? ""
    let initBody = model.range(of: "\n    init() {").flatMap { from in model.range(of: "\n    }\n", range: from.upperBound..<model.endIndex).map { String(model[from.upperBound..<$0.lowerBound]) } } ?? ""
    check(initBody.contains("if !AppMode.isSnapshot { startAtLaunch() }"), "AppModel's init starts its launch work only outside a snapshot")
    check(!initBody.isEmpty && !initBody.contains("Task {") && !initBody.contains("Task.detached") && !initBody.contains(".start()") && !initBody.contains("sweep("),
          "and starts no task, server or sweep of its own")
    equal(model.components(separatedBy: "startAtLaunch()").count - 1, 2, "that launch work is called from that one line")
    check(model.contains("LaunchStart.servers(servers, advisorTrial: AdvisorTrial.isOn, snapshot: AppMode.isSnapshot)"), "the servers to start at launch are chosen with the same gate")

    section("Snapshot: no timer is left out (K829)")
    // Anything that repeats: a loop whose first act is to wait, or a timer. Each has to ask the gate in the lines
    // just above it, or be named here with the reason it's safe.
    let exempt: [String: String] = [
        "GilaMonster/AllowlistPage.swift": "re-reads the server's in-memory lists every five seconds while that page is open, to redraw; it starts nothing",
        "GilaMonster/LinksPage.swift": "re-reads the sign-in list every fifteen seconds while that page is open, to redraw; it starts nothing",
        "GilaMonsterCore/LinksWeb.swift": "the hourly tidy, begun only by startLinksPage, which asks the gate (listed above)",
        "GilaMonsterCore/SessionActions.swift": "the time-out on a session-access question, which only exists once one has been asked; it starts nothing",
        "GilaMonster/QuitDuringBackup.swift": "counts down the quit question, which only a quit during a backup opens; it reads a clock and starts nothing",
    ]
    var repeating = 0
    for (name, text) in files.sorted(by: { $0.key < $1.key }) {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let next = index + 1 < lines.count ? lines[index + 1].trimmingCharacters(in: .whitespaces) : ""
            let waitingLoop = trimmed.hasPrefix("while ") && trimmed.hasSuffix("{") && next.hasPrefix("try? await Task.sleep")
            let timer = ["Timer.scheduledTimer", "Timer.publish", "makeTimerSource", "NSBackgroundActivityScheduler", "repeats: true"].contains { trimmed.contains($0) }
            guard waitingLoop || timer else { continue }
            repeating += 1
            if let reason = exempt[name] { check(!reason.isEmpty, "\(name):\(index + 1) is listed as safe"); continue }
            let above = lines[max(0, index - 8)...index].joined(separator: "\n")
            check(above.contains("AppMode.isSnapshot"), "\(name):\(index + 1) repeats, so it asks the gate first: \(trimmed)")
        }
    }
    check(repeating >= 6, "the scan found the timers it knows about (\(repeating))")
    let script = (try? String(contentsOf: sources.deletingLastPathComponent().appendingPathComponent("scripts/snapshot-fixtures.sh"), encoding: .utf8)) ?? ""
    let harness = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("main.swift"), encoding: .utf8)) ?? ""
    check(!harness.contains("autoDrill = false\n    let there"), "the made-up backups for pictures no longer switch the drill off for one server: the gate covers every server")
    check(script.contains("STARTABLE"), "the snapshot script can make a server that would start, to prove it doesn't")

    section("Snapshot: a made-up server opened in a snapshot starts nothing (K829)")
    let base = AppPaths.servers.appendingPathComponent("snapshot-gate-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let pictures = folder("snapshot-gate-pictures")
    defer { try? FileManager.default.removeItem(at: base) }
    let was = ProcessInfo.processInfo.environment[AppMode.snapshotVariable]
    defer { if let was { setenv(AppMode.snapshotVariable, was, 1) } else { unsetenv(AppMode.snapshotVariable) } }
    unsetenv(AppMode.snapshotVariable)
    check(!AppMode.isSnapshot && AppMode.snapshotFolder == nil, "an ordinary run isn't a snapshot")
    do {
        let root = base.appendingPathComponent("made-up-quiet", isDirectory: true)
        try FileOps.ensureDir(root.appendingPathComponent("world"))
        write("server-port=25611\nserver-ip=127.0.0.1\nmotd=made up\n", root.appendingPathComponent("server.properties"))
        write("", root.appendingPathComponent("world/level.dat"))
        let first = try await ServerController.adopt(root: root, name: "Made-up Quiet")
        check(first.tickerIsRunning, "opened in an ordinary run, a server has its ticker")
        // A whole-folder backup that is a week overdue for its drill, as the pictures' made-up server has.
        let record = writeMadeUpBackup(in: Backups.destination(first.profile), madeAt: Date().addingTimeInterval(-23 * 3600), serverName: first.profile.name)
        first.profile.launch.startWhenAppOpens = true
        first.stopTicker()

        setenv(AppMode.snapshotVariable, pictures.path, 1)
        check(AppMode.isSnapshot, "with the variable set, it is a snapshot")
        equal(AppMode.snapshotFolder, pictures.path, "and the folder for the pictures is read from it")
        guard let quiet = ServerController.open(root: root) else { check(false, "the made-up server opens in a snapshot"); return }
        check(!quiet.tickerIsRunning, "opened in a snapshot, a server has no ticker")
        check(quiet.backups.contains { $0.fileName == record.fileName && $0.scope == .everything }, "its whole-folder backup is still listed, for the pictures")
        check(quiet.profile.backup.autoDrill, "and the weekly drill is still switched on for it")
        check(LaunchStart.servers([quiet], advisorTrial: false, snapshot: AppMode.isSnapshot).isEmpty, "set to start when GilaMonster opens, it isn't picked to start")

        let events = quiet.timeline.count
        await quiet.tick()
        await quiet.runBackupDrill()
        check(quiet.profile.lastDrill == nil && !quiet.drillRunning, "asked for by hand, a drill doesn't run either: nothing is recorded")
        equal(quiet.timeline.count, events, "nothing goes on the timeline")
        check(!quiet.issues.contains { $0.id.hasPrefix("wrapper:drill") }, "and no drill issue is raised")
        for place in [DrillCopies.folder(besideServer: root), DrillCopies.folder(besideBackups: Backups.destination(quiet.profile))] {
            check(!FileOps.exists(place), "no drill copy folder was made (\(place.lastPathComponent))")
        }
        await quiet.start()
        check(quiet.state.canStart && quiet.blockers.isEmpty, "Start does nothing: the server stays stopped and isn't even checked over")
        var refused = false
        do { _ = try await quiet.backupNow(trigger: "manual", scope: .everything) } catch { refused = error.localizedDescription == AppMode.snapshotRefusal }
        check(refused, "a backup is refused, and says why")
        equal(Backups.listAll(quiet.profile).count, 1, "so no new backup was written")

        // The last line of defence: the one place a server's Java is run. /usr/bin/true stands in for Java.
        // It ignores the -Xmx, which is there because the suite's audit wants every launch to name a small heap (K817).
        var threw = false
        do { try ServerProcess(java: "/usr/bin/true", arguments: ["-Xmx64m"], directory: root).start() } catch { threw = error.localizedDescription == AppMode.snapshotRefusal }
        check(threw, "running a server process is refused in a snapshot, whatever asked for it")
        unsetenv(AppMode.snapshotVariable)
        let allowed = ServerProcess(java: "/usr/bin/true", arguments: ["-Xmx64m"], directory: root)
        check((try? allowed.start()) != nil, "and runs as before in an ordinary run")
        for _ in 0..<100 where allowed.isRunning { try? await Task.sleep(for: .milliseconds(20)) }
        check(!allowed.isRunning, "the stand-in has exited")
        quiet.stopTicker()

        // What the whole-run check below counts as Java being run.
        check(isJavaRun("/made/up/jdk/bin/java -Xmx512M -jar server.jar nogui") && isJavaRun("java -jar server.jar"), "Java by its path or its name is counted")
        check(isJavaRun("/bin/sh /made/up/standin/java -Xmx512M -jar server.jar nogui"), "so is the stand-in, which shows as the shell running it")
        check(!isJavaRun("/made/up/debug/gilamonster-check --startable-fixture /made/up/home /made/up/servers /made/up/servers/made-up-server /made/up/standin/java"),
              "a program only told where the stand-in is, as the fixture's helper is, isn't counted")
        check(!isJavaRun("/bin/sh /made/up/snapshot-fixtures.sh /made/up/out normal"), "nor is another shell script")
    } catch {
        check(false, "snapshot gate: \(error)")
    }
}

/// The whole thing, as the pictures are really made (K829): `scripts/snapshot-fixtures.sh` draws one theme with a
/// made-up server that is set to start when GilaMonster opens, has a whole-folder backup that really unpacks, a
/// placeholder jar, and a stand-in for Java that only writes its arguments to a log. While it runs, this watches the
/// script's own process tree and its temp folder. No Java may start and no drill copy may appear. Needs a debug
/// build of GilaMonster. Opens no port, and the stand-in is a shell script, so it needs no test-server lock.
@MainActor func snapshotStartsNothingChecks() async {
    section("Snapshot: the fixture run starts no Java and makes no drill copy (K829)")
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let script = root.appendingPathComponent("scripts/snapshot-fixtures.sh")
    guard FileManager.default.isExecutableFile(atPath: script.path) else { check(false, "scripts/snapshot-fixtures.sh is missing"); return }
    let own = folder("snapshot-quiet")
    let temp = own.appendingPathComponent("tmp", isDirectory: true), out = own.appendingPathComponent("out", isDirectory: true)
    try? FileOps.ensureDir(temp); try? FileOps.ensureDir(out)
    let log = own.appendingPathComponent("stand-in-java.log")
    // Build where this program was built, unless told otherwise, so the script doesn't start a second build tree.
    var environment = ["TMPDIR": temp.path, "THEMES": "bold", "LOOKS": "light", "STARTABLE": log.path]
    if ProcessInfo.processInfo.environment["SCRATCH"] == nil, let me = Bundle.main.executableURL {
        // <scratch>/debug/gilamonster-check, or <scratch>/<platform>/debug/gilamonster-check when run by swift run.
        var build = me.deletingLastPathComponent().deletingLastPathComponent()
        if build.lastPathComponent.contains("-apple-") { build = build.deletingLastPathComponent() }
        environment["SCRATCH"] = build.path
    }
    let run = Process()
    run.executableURL = script
    run.arguments = [out.path, "normal"]
    run.currentDirectoryURL = root
    run.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    run.standardOutput = FileHandle.nullDevice
    run.standardError = FileHandle.nullDevice
    do { try run.run() } catch { check(false, "couldn't run the snapshot script: \(error)"); return }

    var javas = Set<String>(), probes = Set<String>(), drillSigns = Set<String>(), drillRecorded = false
    var appFirstSeen: Date?, appLastSeen: Date?
    while run.isRunning {
        // Every process under the script, by parent: the app, and whatever the app itself runs.
        var parents: [Int32: Int32] = [:], commands: [Int32: String] = [:]
        for line in shell("/bin/ps", ["-axo", "pid=,ppid=,command="]).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let parent = Int32(parts[1]) else { continue }
            parents[pid] = parent; commands[pid] = String(parts[2])
        }
        for (pid, command) in commands {
            var up = pid, mine = false
            for _ in 0..<12 { guard let parent = parents[up] else { break }; if parent == run.processIdentifier { mine = true; break }; up = parent }
            guard mine else { continue }
            let program = command.split(separator: " ").first.map(String.init) ?? ""
            if program.hasSuffix("/debug/GilaMonster") { appFirstSeen = appFirstSeen ?? Date(); appLastSeen = Date() }
            guard isJavaRun(command) else { continue }
            // Looking up which Javas are installed asks each for its version, which the Launch page shows. That isn't a server.
            if command.hasSuffix(" -version") { probes.insert(command) } else { javas.insert(command) }
        }
        // Drill copies, wherever one could be unpacked under the fixture's folders.
        if let walk = FileManager.default.enumerator(at: temp, includingPropertiesForKeys: nil) {
            for case let url as URL in walk {
                let name = url.lastPathComponent
                if walk.level > 6 { walk.skipDescendants() }
                if name == DrillCopies.usualFolderName || name == DrillCopies.besideBackupsFolderName || name.hasSuffix(DrillCopies.markSuffix) || DrillCopies.isDrillName(name) {
                    drillSigns.insert(name); walk.skipDescendants()
                }
                if name == "server.json", (try? String(contentsOf: url, encoding: .utf8))?.contains("\"lastDrill\"") == true { drillRecorded = true }
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
    }
    equal(run.terminationStatus, 0, "the snapshot script finished")
    let report = Overflow.readReport((try? String(contentsOf: out.appendingPathComponent("normal/bold-light/overflow-report.txt"), encoding: .utf8)) ?? "")
    check(report.expected > 0 && report.pages == report.expected, "every page was still drawn (\(report.pages) of \(report.expected))")
    let lasted = appLastSeen.flatMap { last in appFirstSeen.map { last.timeIntervalSince($0) } } ?? 0
    check(lasted >= 12, "the app was up for more than two of the ticker's five-second turns, long enough for scheduled work to have begun (\(Int(lasted)) s)")
    let logged = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    equal(logged.filter { $0 != "-version" }, [], "the stand-in for Java was never run as a server")
    equal(javas.sorted(), [], "no Java process started under the snapshot, beyond being asked its version")
    equal(drillSigns.sorted(), [], "no drill copy, mark or test-copies folder ever appeared")
    check(!drillRecorded, "and no drill result was written to the made-up server's settings")
    print("    the app ran \(Int(lasted)) s; version questions seen: \(probes.count); stand-in log lines: \(logged.count)")
    // swift's own lock and scratch files may sit in the same folder; the script's is gm-fixture.<random>.
    let left = ((try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []).filter { $0.hasPrefix("gm-fixture.") }
    equal(left, [], "the script removed its own temp folder")
}

/// Whether a line from `ps` is Java, or the stand-in for it, being run. The stand-in is a shell script, so it shows as
/// the shell followed by its path. A path further along is only something the program was told about.
func isJavaRun(_ command: String) -> Bool {
    let words = command.split(separator: " ", maxSplits: 2).map(String.init)
    guard let program = words.first else { return false }
    if program == "java" || program.hasSuffix("/java") { return true }
    return ["sh", "bash", "zsh"].contains((program as NSString).lastPathComponent) && words.count > 1 && words[1].hasSuffix("/standin/java")
}

private func shell(_ tool: String, _ arguments: [String]) -> String {
    let run = Process(), pipe = Pipe()
    run.executableURL = URL(fileURLWithPath: tool)
    run.arguments = arguments
    run.standardOutput = pipe
    run.standardError = FileHandle.nullDevice
    guard (try? run.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    run.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}
