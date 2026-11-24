import Foundation
@testable import GilaMonsterCore

/// The throwaway lab (D229, owner, 2026-11-16): each status-board run deletes its lab when it ends, pass or fail; a
/// copy is kept only when asked; a lab left by a quit or crash goes at the next launch, and only if it's GilaMonster's own.
/// Uses a stand-in for the station's work, so nothing is downloaded or started. Everything made here is removed.
@MainActor func labRunChecks() async {
    section("The lab: built for a run, deleted after it")
    let root = LabFiles.root
    guard root.path.hasPrefix(AppPaths.servers.path), ProcessInfo.processInfo.environment["GILAMONSTER_SERVERS"] != nil else {
        failures.append("lab run checks aren't in the sandbox: \(root.path)")
        return
    }
    let modelRoot = AppPaths.servers.appendingPathComponent("made-up-model-\(UUID().uuidString.prefix(6))", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: modelRoot)
        try? FileManager.default.removeItem(at: LabFiles.saves)
        try? FileManager.default.removeItem(at: LabFiles.state)
    }
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: LabFiles.saves)
    try? FileManager.default.removeItem(at: LabFiles.state)

    /// What a run's lab looks like on disk: GilaMonster's mark, in the lab folder.
    func makeLab() throws -> ServerController {
        try FileOps.ensureDir(ServerPaths(root: root).meta)
        write("server-port=25598\nserver-ip=127.0.0.1\nmotd=made up\n", root.appendingPathComponent("server.properties"))
        var profile = ServerProfile()
        profile.isLab = true
        profile.name = LabFiles.serverName
        try JSONStore.save(profile, to: ServerPaths(root: root).profile)
        guard let c = ServerController.open(root: root) else { throw AppError("the stand-in lab didn't open") }
        return c
    }

    do {
        try FileOps.ensureDir(modelRoot)
        let model = ServerController(root: modelRoot, profile: ServerProfile())
        defer { model.stopTicker() }
        let lab = LabController()
        lab.acceptEULA()
        var listed: [String] = []
        var dropped = 0
        lab.onServerChanged = { _, new in if let new { listed.append(new.profile.name) } else { dropped += 1 } }

        // Pass.
        lab.stationStandIn = { station in
            let c = try makeLab()
            lab.place(station, outcome: .passed, model: model)
            return c
        }
        await lab.run(.plugins, model: model)
        equal(listed, ["lab"], "a run's lab is listed while it exists, named lab")
        equal(lab.result(.plugins)?.outcome, .passed, "a passing run keeps its result")
        check(!FileOps.exists(root), "the lab is deleted after a pass")
        check(lab.server == nil && dropped == 1, "and the app is told to drop it")
        check(lab.saves.isEmpty, "no copy is kept unless asked")

        // Fail.
        lab.stationStandIn = { _ in
            _ = try makeLab()
            throw AppError("Made-up failure")
        }
        await lab.run(.plugins, model: model)
        check(lab.failure?.contains("Made-up failure") == true, "a failing run says why: \(lab.failure ?? "-")")
        equal(lab.result(.plugins)?.outcome, .failed, "and keeps a red light")
        check(!FileOps.exists(root), "the lab is deleted after a failure too")

        // Save This Lab.
        lab.stationStandIn = { station in
            let c = try makeLab()
            lab.place(station, outcome: .passed, model: model)
            return c
        }
        lab.keepCopy(note: "Made-up note")
        await lab.run(.plugins, model: model)
        equal(lab.saves.count, 1, "Save This Lab keeps one copy")
        check(lab.saves.first?.fileName.hasSuffix("_made-up-note.tar.gz") == true, "named from the note: \(lab.saves.first?.fileName ?? "-")")
        check(!FileOps.exists(root), "and the lab is still deleted")
        check(lab.keepRequest == nil, "the request was for that run only")
        await lab.run(.plugins, model: model)
        equal(lab.saves.count, 1, "the next run keeps nothing")

        // Run Checks: the ticked stations in order, skipping any still locked, with the reason.
        var ran: [LabStation] = []
        lab.stationStandIn = { station in
            ran.append(station)
            let c = try makeLab()
            lab.place(station, outcome: .passed, model: model)
            return c
        }
        let skipped = await lab.runChecks([.settings, .plugins, .upgrade], model: model)
        equal(ran, [.plugins, .settings], "Run Checks runs the ticked checks in board order")
        equal(skipped.map(\.0), [.upgrade], "and skips one still locked")
        check(skipped.first?.1.isEmpty == false, "saying why: \(skipped.first?.1 ?? "-")")
        check(!FileOps.exists(root), "each run's lab is deleted")
        ran = []
        let none = await lab.runChecks([], model: model)
        check(ran.isEmpty && none.isEmpty, "nothing ticked runs nothing")

        // Interrupted: a quit or crash mid-run leaves the lab, and the next launch removes it.
        let left = try makeLab()
        left.stopTicker()
        let next = LabController()
        check(next.server != nil, "a leftover lab is found at launch")
        await next.removeLeftover()
        check(!FileOps.exists(root), "and removed")
        check(next.server == nil, "and no longer listed")

        // Someone's own folder called lab is never removed.
        try FileOps.ensureDir(root)
        write("mine", root.appendingPathComponent("precious.txt"))
        let third = LabController()
        await third.removeLeftover()
        check(FileOps.exists(root.appendingPathComponent("precious.txt")), "a folder called lab that GilaMonster didn't make is left alone")
        try? FileManager.default.removeItem(at: root)
    } catch {
        failures.append("lab run checks threw: \(error)")
    }
}
