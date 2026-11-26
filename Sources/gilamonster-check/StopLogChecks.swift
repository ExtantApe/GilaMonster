import Darwin
import Foundation
@testable import GilaMonsterCore

/// Each server's stop file (K798): what asked for every stop, the server's own exit, the cap on the file's size, and
/// the sentence the Overview shows. Made-up names only, in the suite's own temp folder.
@MainActor func stopLogChecks() {
    section("Stop file: every source names itself")
    equal(StopSource.button("Overview").words(), "the Stop button (Overview)", "the Stop button, with where it is")
    equal(StopSource.button("toolbar").words(restart: true), "the Restart button (toolbar)", "a restart says Restart")
    equal(StopSource.menu.words(), "Stop in the Server menu", "the menu")
    equal(StopSource.menuBar.words(), "Stop in the menu bar", "the menu bar")
    equal(StopSource.keyboardShortcut.words(), "the Stop keyboard shortcut", "the keyboard shortcut")
    equal(StopSource.menu(keyPress: true), .keyboardShortcut, "the Server menu's item by a key press is the shortcut")
    equal(StopSource.menu(keyPress: false), .menu, "and by the pointer is the menu")
    equal(StopSource.session(caller: "helper").words(), "a session (helper)", "a session, with the name it gave")
    equal(StopSource.session(caller: "helper").caller, "helper", "and that name is kept on its own too")
    equal(StopSource.quit.words(), "quitting GilaMonster", "a quit")
    equal(StopSource.mac(.shutdown).words(), "the Mac shutting down", "the Mac shutting down")
    equal(StopSource.mac(.restart).words(), "the Mac restarting", "the Mac restarting")
    equal(StopSource.mac(.logout).words(), "logging out of the Mac", "logging out")
    equal(StopSource.signal("SIGTERM").words(), "a quit signal sent to GilaMonster (SIGTERM)", "a signal")
    equal(StopSource.lab.words(), "the Lab", "the Lab")
    equal(StopSource.console.words(), "stop typed in the console", "stop typed in the console")
    equal(StopSource.forceStop.words(), "Force Stop", "Force Stop")
    equal(StopSource.app("to restore a backup").words(), "GilaMonster, to restore a backup", "GilaMonster itself, with what for")
    equal(StopSource.outside.words(), "the server stopped on its own or from outside", "and when GilaMonster didn't ask")
    let all: [StopSource] = [.button("x"), .menu, .menuBar, .keyboardShortcut, .session(caller: "x"), .quit, .mac(.shutdown), .mac(.restart), .mac(.logout),
                             .signal("x"), .lab, .console, .forceStop, .app("x"), .outside]
    equal(Set(all.map(\.key)).count, all.count, "every source has its own key in the file")
    equal(StopSource.mac(.user).key, StopSource.quit.key, "a quit the owner asked for is a quit, however it arrives")

    section("Stop file: lines, and the exit carries what asked")
    let dir = folder("stop-log")
    let file = dir.appendingPathComponent(".gilamonster/\(StopLog.fileName)")
    let at = Date(timeIntervalSince1970: 1_795_651_320)  // 2026-11-26 00:02 UTC
    let ask = StopRecord.asked(.session(caller: "helper"), restart: false, date: at)
    check(StopLog.append(ask, to: file), "an ask is written, and the folder made for it")
    let exit = StopRecord.exited(code: 0, outcome: .stopped, ask: ask, ownShutdown: true, crashInLog: false, date: at.addingTimeInterval(4))
    StopLog.append(exit, to: file)
    let read = StopLog.read(file)
    equal(read.count, 2, "two lines: asked, then exited")
    equal(read.first?.event, .asked, "the ask comes first")
    equal(read.last, exit, "the exit reads back as it was written")
    equal(read.last?.source, "session", "the exit says a session asked")
    equal(read.last?.caller, "helper", "with the session's name")
    equal(read.last?.asked, at, "and when")
    equal(read.last?.code, 0, "and the server's own exit code")
    equal(StopLog.last(read), exit, "the last stop is the newest line")
    let alone = StopRecord.exited(code: 143, outcome: .stopped, ask: nil, ownShutdown: true, crashInLog: false, date: at)
    equal(alone.source, "outside", "an exit nobody here asked for is from outside")
    equal(alone.by, "the server stopped on its own or from outside", "in those words")
    check(alone.asked == nil && alone.caller == nil, "with no ask time and no name")
    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    check(text.hasSuffix("\n") && text.split(separator: "\n").count == 2, "one JSON line each")
    check(StopLog.read(dir.appendingPathComponent("nothing-here.jsonl")).isEmpty, "no file reads as no stops")
    write("not json\n" + text, file)
    equal(StopLog.read(file).count, 2, "a damaged line is skipped, the rest still read")

    section("Stop file: capped")
    let long = String(repeating: "a made-up name ", count: 40)
    let clipped = StopRecord.asked(.session(caller: long + "\nsecond line"), restart: false, date: at)
    check((clipped.caller ?? long).count <= StopLog.maxField && !clipped.by.contains("\n"), "a long name is cut to \(StopLog.maxField) characters and kept on one line")
    check(StopRecord.asked(.app(long), restart: false, note: long, date: at).note!.count <= StopLog.maxField, "and so is a note")
    let capped = dir.appendingPathComponent("capped.jsonl")
    var row = 0
    while row < 3000 {
        StopLog.append(StopRecord.asked(.app("to fill the file, line \(row)"), restart: false, note: long, date: at.addingTimeInterval(Double(row))), to: capped)
        row += 1
    }
    let size = FileOps.size(capped)
    check(size > 0 && size <= Int64(StopLog.maxBytes) + 4096, "3000 lines leave a file no bigger than the cap (\(size) bytes, cap \(StopLog.maxBytes))")
    let kept = StopLog.read(capped)
    check(kept.count <= 3000 && kept.count >= 1, "it was cut back (\(kept.count) lines left)")
    equal(kept.last?.by, "GilaMonster, to fill the file, line 2999", "and the newest line is still there")
    check(kept.first.map { $0.date > at } == true, "the oldest lines are the ones that went")

    section("Stop file: the sentence on Overview")
    let us = Locale(identifier: "en_US"), utc = TimeZone(identifier: "UTC")!
    func say(_ r: StopRecord) -> String { StopLog.sentence(r, locale: us, timeZone: utc).replacingOccurrences(of: "\u{202F}", with: " ") }
    equal(say(StopRecord.exited(code: 0, outcome: .stopped, ask: StopRecord.asked(.button("Overview"), restart: false, date: at), date: at)),
          "Last stop: Nov 26, 2026 at 12:02 AM, from the Stop button (Overview). Exit code 0.", "a stop from the button")
    equal(say(alone), "Last stop: Nov 26, 2026 at 12:02 AM. The server stopped on its own or from outside. GilaMonster didn't ask. Exit code 143, after the server's own shutdown.", "a stop GilaMonster didn't ask for")
    equal(say(StopRecord.exited(code: 1, outcome: .crashed, ask: nil, date: at)),
          "Last stop: Nov 26, 2026 at 12:02 AM. The server stopped on its own or from outside. GilaMonster didn't ask. The server crashed, exit code 1.", "a crash")
    equal(say(StopRecord.asked(.mac(.shutdown), restart: false, date: at)),
          "Last stop: asked for on Nov 26, 2026 at 12:02 AM, from the Mac shutting down. GilaMonster didn't see the server exit.", "an ask with no exit seen")
    equal(say(StopRecord.exited(code: 0, outcome: .stopped, ask: StopRecord.asked(.session(caller: "helper"), restart: true, date: at), date: at)),
          "Last restart: Nov 26, 2026 at 12:02 AM, from a session (helper). Exit code 0.", "a restart")
    equal(say(StopRecord.exited(code: 137, outcome: .stopped, ask: StopRecord.asked(.quit, restart: false, date: at), note: "GilaMonster forced it to stop after it didn't shut down", date: at)),
          "Last stop: Nov 26, 2026 at 12:02 AM, from quitting GilaMonster. Exit code 137. GilaMonster forced it to stop after it didn't shut down.", "a forced stop says so")
    for line in [say(alone), say(exit)] { check(!line.contains("—") && !line.contains("–"), "no dashes in it") }

    section("Stop file: every way to stop passes its source")
    let core = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonsterCore")
    let app = core.deletingLastPathComponent().appendingPathComponent("GilaMonster")
    func source(_ folder: URL, _ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    let controller = source(core, "ServerController.swift")
    check(controller.contains("public func stop(by source: StopSource) {") && controller.contains("public func forceStop(by source: StopSource) {")
          && controller.contains("public func restart(reason: String = \"Restart\", by source: StopSource) {") && controller.contains("public func stopExternalServer(by source: StopSource) async {"),
          "stop, force stop, restart and stopping a left-over server can't be called without a source")
    check(controller.contains("if bare == \"stop\" {\n            noteStopAsked(source)"), "stop typed in the console is noted before it's sent")
    check(controller.contains("ask: stopAsk,\n                                     ownShutdown: sawShutdown, crashInLog: sawCrash, note: stopNote)"), "every exit is written with what asked, or as from outside")
    check(source(app, "OverviewPage.swift").contains("server.stop(by: .button(\"Overview\"))") && source(app, "RootView.swift").contains("server.stop(by: .button(\"toolbar\"))"), "the Stop buttons say which they are")
    let model = source(app, "AppModel.swift")
    check(model.contains("model.selected?.stop(by: .menu(keyPress: NSApp.currentEvent?.type == .keyDown))"), "the Server menu tells its shortcut from a click")
    check(model.contains("server.stop(by: .menuBar)"), "the menu bar")
    check(model.contains("await model.stopAll(by: .quit)") && model.contains("await model.stopAll(by: .mac(reason))") && model.contains("await model.stopAll(by: .signal(name))"), "a quit, the Mac shutting down and a quit signal")
    check(!model.contains("stopAll()"), "nothing stops every server without saying why")
    check(source(core, "SessionActions.swift").contains("server.stop(by: .session(caller: caller))"), "a session, with its name")
    check(source(core, "Lab.swift").contains("c.stop(by: .lab)"), "the Lab")
    check(source(app, "OverviewPage.swift").contains("if !server.state.isLive, let stop = server.lastStop {\n                Text(StopLog.sentence(stop))"), "Overview shows the last stop while the server is down")
}

/// The real thing, with the stand-in jar: a stop from a button, a session, the console and from outside each leave
/// their own lines in the server's stop file.
@MainActor func stopLogLifecycle(_ c: ServerController, startupTimeout: Int) async {
    section("Stop file: a real server process")
    let file = StopLog.file(c.paths)
    func up() async -> Bool {
        if c.state.isLive { c.stop(by: .app("for a check")); _ = await until(60) { c.state == .stopped } }
        await c.start()
        return await until(startupTimeout) { c.state == .running }
    }
    func lastTwo() -> [StopRecord] { Array(StopLog.read(file).suffix(2)) }
    c.profile.launch.restartOnCrash = false

    guard await up() else { check(false, "the stand-in started for the stop checks: \(c.state)"); return }
    c.stop(by: .button("Overview"))
    equal(StopLog.read(file).last?.event, .asked, "the ask is in the file before the server has exited")
    await checkUntil(60, "stopped from the button") { c.state == .stopped }
    var two = lastTwo()
    equal(two.map(\.event), [.asked, .exited], "asked, then exited")
    equal(two.last?.by, "the Stop button (Overview)", "the exit says the Stop button asked")
    equal(two.last?.code, 0, "with the server's exit code")
    equal(two.last?.outcome, .stopped, "as a stop")
    // The file keeps whole seconds, so the two are compared by what they say.
    check(c.lastStop?.event == .exited && c.lastStop?.by == two.last?.by && c.lastStop?.code == two.last?.code, "and the server shows it as its last stop")
    check(c.timeline.first { $0.kind == .stop }?.detail?.contains("the Stop button (Overview)") == true, "History's stop says what asked too")

    guard await up() else { check(false, "started again"); return }
    c.stop(by: .session(caller: "helper"))
    await checkUntil(60, "stopped by a session") { c.state == .stopped }
    two = lastTwo()
    equal(two.last?.source, "session", "a session's stop is marked as one")
    equal(two.last?.caller, "helper", "with the name it gave")

    guard await up() else { check(false, "started a third time"); return }
    c.send("stop")
    await checkUntil(60, "stopped from the console") { c.state == .stopped }
    two = lastTwo()
    equal(two.map(\.by), ["stop typed in the console", "stop typed in the console"], "stop typed in the console, asked and exited")

    guard await up() else { check(false, "started a fourth time"); return }
    let before = StopLog.read(file).count
    if let pid = try? JSONStore.decoder.decode(Int32.self, from: Data(contentsOf: c.paths.pid)), pid > 1 {
        kill(pid, SIGTERM)
        await checkUntil(60, "gone after a signal from outside: \(c.state)") { !c.state.isLive }
        let after = StopLog.read(file)
        equal(after.count, before + 1, "one line, the exit: nothing here asked")
        equal(after.last?.source, "outside", "marked as from outside")
        equal(after.last?.by, StopLog.outsideWords, "in the words for it")
        check(after.last?.asked == nil && after.last?.code != nil, "with the exit code and no ask time (code \(after.last?.code ?? -1))")
        check(StopLog.sentence(after.last!).contains("GilaMonster didn't ask."), "and Overview would say GilaMonster didn't ask")
    } else { check(false, "the stand-in's pid could be read") }

    guard await up() else { check(false, "started a fifth time"); return }
    c.restart(by: .button("toolbar"))
    await checkUntil(60, "the restart's stop was written") { StopLog.read(file).last?.event == .exited && StopLog.read(file).last?.restart == true }
    equal(StopLog.read(file).last?.by, "the Restart button (toolbar)", "a restart's stop says Restart, and from where")
    await checkUntil(startupTimeout, "back up after the restart") { c.state == .running }
    c.stop(by: .app("for a check"))
    await checkUntil(60, "stopped at the end") { c.state == .stopped }
    let whole = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    check(!whole.contains("127.0.0.1") && !whole.contains("Alice"), "the file holds no address and no player's name")
}
