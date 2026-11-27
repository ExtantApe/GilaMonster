import Foundation
@testable import GilaMonsterCore

// K804: the Lab reads what a paper-plugin.yml requires, keeps a plugin with what it requires in one group, reports a
// plugin as skipped when what it requires isn't in the run, and keeps each group's restart log with the result.
// Every plugin here is made up, and every jar holds only a descriptor. Nothing is downloaded or started.
// What's made here is under the suite's own temp folder or the sandbox servers folder, and is removed at the end.

/// A made-up Paper plugin's descriptor, in Paper's own nested format.
private func paperYAML(_ name: String, needs: [String] = [], optional: [String] = []) -> String {
    var text = "name: \(name)\nversion: '1.0'\nmain: com.example.madeup.Main\napi-version: '26.1'\n"
    if !needs.isEmpty || !optional.isEmpty {
        text += "dependencies:\n  server:\n"
        for other in needs { text += "    \(other):\n      load: BEFORE\n      required: true\n      join-classpath: true\n" }
        for other in optional { text += "    \(other):\n      load: BEFORE\n      required: false\n" }
    }
    return text + "permissions:\n  madeup.use:\n    description: Made up.\n    default: true\n"
}

/// The plugin as the app would see it after reading that descriptor from a jar.
private func paperPlugin(_ name: String, needs: [String] = [], optional: [String] = [], enabled: Bool = true) -> InstalledPlugin {
    InstalledPlugin(fileName: "\(name).jar\(enabled ? "" : ".disabled")", enabled: enabled,
                    descriptor: PluginYAML.parse(paperYAML(name, needs: needs, optional: optional), paper: true), digests: nil, size: 1)
}

/// A jar holding only a paper-plugin.yml, made with the system zip tool in the suite's temp folder.
private func makePaperJar(_ url: URL, yaml: String) {
    let work = folder("paper-jar-\(UUID().uuidString)")
    write(yaml, work.appendingPathComponent("paper-plugin.yml"))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    p.arguments = ["-q", url.path, "paper-plugin.yml"]
    p.currentDirectoryURL = work
    try! p.run()
    p.waitUntilExit()
}

/// Reading what a plugin requires, grouping by it, and leaving out what can't run.
@MainActor func labDependencyChecks() async {
    section("The lab: what a plugin requires (K804)")

    // Paper's nested format: required unless it says otherwise, in either phase, block or inline.
    let nested = """
    name: MadeUpMinimap
    version: '1.0'
    main: com.example.madeup.Main
    # A comment before the section.
    dependencies:
      bootstrap:
        MadeUpBoot:
          load: BEFORE
      server:
        # MadeUpMaps must load first.
        MadeUpMaps:
          load: BEFORE
          required: true
          join-classpath: true
        MadeUpDefault:
          load: AFTER
        'MadeUpExtras':
          load: BEFORE
          required: false   # optional
        MadeUpInline: { load: BEFORE, required: false }
        MadeUpInlineNeeded: {load: BEFORE, required: true}
    permissions:
      madeup.use:
        required: false
        default: true
    """
    let read = PluginYAML.parse(nested, paper: true)
    equal(read?.depend ?? [], ["MadeUpBoot", "MadeUpMaps", "MadeUpDefault", "MadeUpInlineNeeded"], "a paper-plugin.yml's required plugins are read, with required as the default")
    equal(read?.softDepend ?? [], ["MadeUpExtras", "MadeUpInline"], "and its optional ones are kept apart")
    equal(PluginYAML.parse(nested)?.depend ?? [], [], "a plugin.yml has no such section, so nothing is read from one")
    let both = PluginYAML.parse("name: MadeUpBoth\ndependencies:\n  bootstrap:\n    MadeUpLib:\n      required: false\n  server:\n    MadeUpLib:\n      required: true\n", paper: true)
    equal(both?.depend ?? [], ["MadeUpLib"], "required in one phase is required")
    equal(both?.softDepend ?? [], [], "and isn't listed as optional too")
    let jar = folder("paper-read").appendingPathComponent("MadeUpMinimap.jar")
    makePaperJar(jar, yaml: paperYAML("MadeUpMinimap", needs: ["MadeUpMaps"], optional: ["MadeUpExtras"]))
    let fromJar = await PluginYAML.read(jar: jar)
    equal(fromJar?.depend ?? [], ["MadeUpMaps"], "and they're read from a real jar")
    equal(fromJar?.softDepend ?? [], ["MadeUpExtras"], "optional ones too")

    // Groups. Fourteen fillers spread "everything else" over three groups, so the plugins below start out apart.
    let fillers = (1...14).map { paperPlugin("Other\($0)") }
    func home(_ name: String, in groups: [PluginThemes.Batch]) -> String? { groups.first { $0.plugins.contains { $0.name == name } }?.title }
    func whole(_ groups: [PluginThemes.Batch], _ count: Int) -> Bool {
        let names = groups.flatMap(\.plugins).map(\.name)
        return names.count == count && Set(names).count == count
    }

    let chain = PluginThemes.batches(fillers + [paperPlugin("AaTop", needs: ["MmMiddle"]), paperPlugin("MmMiddle", needs: ["ZzBase"]), paperPlugin("ZzBase")])
    check(home("AaTop", in: chain) != nil && home("AaTop", in: chain) == home("MmMiddle", in: chain) && home("MmMiddle", in: chain) == home("ZzBase", in: chain),
          "a plugin, what it requires and what that requires share a group: \(chain.map { "\($0.title): \($0.plugins.map(\.name))" })")
    check(whole(chain, 17), "nobody lost or doubled")

    let later = PluginThemes.batches(fillers + [paperPlugin("AaBase"), paperPlugin("ZzNeedsBase", needs: ["AaBase"])])
    equal(home("ZzNeedsBase", in: later), home("AaBase", in: later), "a plugin sorted after what it requires joins its group")
    check(whole(later, 16), "nobody lost or doubled")

    let circle = PluginThemes.batches(fillers + [paperPlugin("AaLoop", needs: ["ZzLoop"]), paperPlugin("ZzLoop", needs: ["AaLoop"]), paperPlugin("MmSelf", needs: ["MmSelf"])])
    equal(home("AaLoop", in: circle), home("ZzLoop", in: circle), "two plugins that require each other share a group, and grouping still ends")
    check(whole(circle, 17), "nobody lost or doubled, even one that names itself")

    let optional = PluginThemes.batches(fillers + [paperPlugin("AaSoft", optional: ["ZzExtra"]), paperPlugin("ZzExtra")])
    check(home("AaSoft", in: optional) != nil && home("AaSoft", in: optional) != home("ZzExtra", in: optional), "an optional plugin doesn't pull anything into a group")

    let themed = PluginThemes.batches(fillers + [paperPlugin("LuckPerms"), paperPlugin("ZzNeedsPerms", needs: ["LuckPerms"])])
    equal(themed.first?.title, "Worlds and permissions", "worlds and permissions still go first")
    equal(home("ZzNeedsPerms", in: themed), "Worlds and permissions", "and a plugin that requires one of them joins it there")

    // What the lab is built from: a plugin whose required plugin isn't in the run is not installed.
    guard ProcessInfo.processInfo.environment["GILAMONSTER_SERVERS"] != nil else {
        failures.append("lab dependency checks aren't in the sandbox")
        return
    }
    let modelRoot = AppPaths.servers.appendingPathComponent("made-up-needs-\(UUID().uuidString.prefix(6))", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: modelRoot) }
    do {
        let paths = ServerPaths(root: modelRoot)
        try FileOps.ensureDir(paths.plugins)
        // Dynmap is one the Lab leaves out, because it reaches outside this Mac. The rest are made up.
        makePaperJar(paths.plugins.appendingPathComponent("Dynmap.jar"), yaml: paperYAML("Dynmap"))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpMinimap.jar"), yaml: paperYAML("MadeUpMinimap", needs: ["Dynmap"]))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpChain.jar"), yaml: paperYAML("MadeUpChain", needs: ["MadeUpMinimap"]))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpNeedsGone.jar"), yaml: paperYAML("MadeUpNeedsGone", needs: ["MadeUpGone"]))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpOff.jar.disabled"), yaml: paperYAML("MadeUpOff"))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpNeedsOff.jar"), yaml: paperYAML("MadeUpNeedsOff", needs: ["MadeUpOff"]))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpSoft.jar"), yaml: paperYAML("MadeUpSoft", optional: ["Dynmap", "MadeUpGone"]))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpSolo.jar"), yaml: paperYAML("MadeUpSolo"))
        makePaperJar(paths.plugins.appendingPathComponent("MadeUpPair.jar"), yaml: paperYAML("MadeUpPair", needs: ["MadeUpSolo"]))
        let model = ServerController(root: modelRoot, profile: ServerProfile())
        defer { model.stopTicker() }
        let build = SoftwareBuild(flavor: .paper, mcVersion: "26.3", build: 1, channel: "STABLE", downloadURL: "https://example.invalid/made-up.jar", fileName: "made-up.jar", hashes: ExpectedHashes())
        let spec = try await LabController.spec(copying: model, build: build)
        equal(spec.jars.map(\.lastPathComponent).sorted(), ["MadeUpPair.jar", "MadeUpSoft.jar", "MadeUpSolo.jar"],
              "the lab gets only the plugins that have what they require")
        equal(spec.leftOut, ["Dynmap reaches outside this Mac, so it doesn't run here."], "the plugin left out is still named as left out")
        labSkipChecks(spec)
    } catch {
        failures.append("lab dependency checks threw: \(error)")
    }
}

/// Skipped, with what's needed, and never failed. `spec` is the lab made from the made-up server above.
@MainActor private func labSkipChecks(_ spec: LabSpec) {
    section("The lab: skipped when what it requires isn't in the run (K804)")
    func detail(_ name: String, in skips: [LabDependencies.Skip]) -> String? { skips.first { $0.plugin.name == name }?.detail }

    equal(spec.skipped.map(\.plugin.name), ["MadeUpChain", "MadeUpMinimap", "MadeUpNeedsGone", "MadeUpNeedsOff"], "each plugin that can't run is listed as skipped")
    equal(detail("MadeUpMinimap", in: spec.skipped), "Skipped: needs Dynmap (left out of the lab).", "one that requires a left-out plugin says so")
    equal(detail("MadeUpChain", in: spec.skipped), "Skipped: needs MadeUpMinimap (skipped too).", "one further along the chain names the plugin it requires")
    equal(detail("MadeUpNeedsGone", in: spec.skipped), "Skipped: needs MadeUpGone (not installed).", "one whose required plugin is missing says so")
    equal(detail("MadeUpNeedsOff", in: spec.skipped), "Skipped: needs MadeUpOff (turned off).", "one whose required plugin is turned off says so")
    check(detail("MadeUpSoft", in: spec.skipped) == nil, "a plugin missing only optional plugins still runs")
    let row = spec.skipped.first { $0.plugin.name == "MadeUpMinimap" }?.check
    equal(row?.outcome, .skipped, "the row is skipped, not failed")
    equal(row?.title, "MadeUpMinimap 1.0 loads", "under the same title its loads check would have had")
    check(spec.skipped.allSatisfy { $0.detail.hasPrefix("Skipped: needs ") }, "every one says Skipped in words, so it doesn't rest on the icon or its color")

    // The same rule on its own, with whatever is left out.
    func skips(_ plugins: [InstalledPlugin], leftOut: Set<String> = []) -> [LabDependencies.Skip] {
        LabDependencies.skips(installed: plugins, leftOut: { leftOut.contains($0.name) })
    }
    let two = skips([paperPlugin("MadeUpTwo", needs: ["MadeUpMaps", "MadeUpGone", "MadeUpOff"]), paperPlugin("MadeUpMaps"), paperPlugin("MadeUpOff", enabled: false)], leftOut: ["MadeUpMaps"])
    equal(detail("MadeUpTwo", in: two), "Skipped: needs MadeUpMaps (left out of the lab), MadeUpGone (not installed) and MadeUpOff (turned off).", "several missing plugins are all named")
    check(skips([paperPlugin("AaLoop", needs: ["ZzLoop"]), paperPlugin("ZzLoop", needs: ["AaLoop"])]).isEmpty, "two plugins that require each other, both there, both run")
    let brokenCircle = skips([paperPlugin("AaLoop", needs: ["ZzLoop"]), paperPlugin("ZzLoop", needs: ["AaLoop", "MadeUpGone"])])
    equal(brokenCircle.map(\.plugin.name), ["AaLoop", "ZzLoop"], "and when one of them is missing something, both are skipped")
    equal(detail("AaLoop", in: brokenCircle), "Skipped: needs ZzLoop (skipped too).", "the other naming it")
    check(skips([paperPlugin("MadeUpMaps", needs: ["MadeUpGone"])], leftOut: ["MadeUpMaps"]).isEmpty, "a left-out plugin is only ever left out")

    // A group's badge and the light.
    let passed = LabCheck("MadeUpSolo 1.0 loads", .passed), skipped = LabCheck("MadeUpMinimap 1.0 loads", .skipped, "Skipped: needs Dynmap (left out of the lab).")
    equal(MirrorBatch(title: "g", plugins: [], fresh: [skipped]).outcome, .skipped, "a group where nothing ran is skipped, not passed")
    equal(MirrorBatch(title: "g", plugins: [], fresh: [passed, skipped]).outcome, .passed, "a group with a skipped plugin passes on the rest")
    equal(MirrorBatch(title: "g", plugins: [], fresh: [LabCheck("MadeUpSolo 1.0 loads", .failed), skipped]).outcome, .pluginProblem, "a real failure still counts")
    equal(StationResult.outcome(checks: [skipped], groups: [MirrorBatch(title: "g", plugins: [], fresh: [skipped]), MirrorBatch(title: "h", plugins: [], fresh: [passed])]), .passed, "skipped plugins don't turn the light red")
    equal(StationResult.outcome(checks: [], groups: [MirrorBatch(title: "g", plugins: [], fresh: [LabCheck("Starts", .failed)])]), .failed, "a failure does")
    equal(LabController.note("Paper 26.3 build 1", skipped: 0), "Paper 26.3 build 1", "the line under the check is unchanged with nothing skipped")
    equal(LabController.note("Paper 26.3 build 1", skipped: 1), "Paper 26.3 build 1. 1 plugin skipped.", "and counts what was skipped")
    equal(LabController.note("Paper 26.3 build 1", skipped: 4), "Paper 26.3 build 1. 4 plugins skipped.", "in the plural too")

    // Within one group: the plugin that broke stays failed, and the one that only required it is skipped.
    let base = paperPlugin("MadeUpBase"), needy = paperPlugin("MadeUpNeedy", needs: ["MadeUpBase"]), far = paperPlugin("MadeUpFar", needs: ["MadeUpNeedy"]), fine = paperPlugin("MadeUpFine")
    let ran = [LabCheck("Starts", .passed), LabCheck("MadeUpBase 1.0 loads", .failed, "It was never enabled."), LabCheck("MadeUpNeedy 1.0 loads", .failed, "It was never enabled."),
               LabCheck("MadeUpFar 1.0 loads", .failed, "It was never enabled."), LabCheck("MadeUpFine 1.0 loads", .passed)]
    let marked = LabDependencies.markCascades(ran, group: [base, needy, far, fine])
    equal(marked.first { $0.title == "MadeUpBase 1.0 loads" }, ran[1], "the plugin that didn't load stays failed")
    equal(marked.first { $0.title == "MadeUpNeedy 1.0 loads" }, LabCheck("MadeUpNeedy 1.0 loads", .skipped, "Skipped: needs MadeUpBase (didn't load)."), "the one that required it is skipped")
    equal(marked.first { $0.title == "MadeUpFar 1.0 loads" }, LabCheck("MadeUpFar 1.0 loads", .skipped, "Skipped: needs MadeUpNeedy (didn't load)."), "and so is the next along")
    equal(marked.filter { $0.outcome == .passed }.count, 2, "what passed is untouched")
    let loopA = paperPlugin("AaLoop", needs: ["ZzLoop"]), loopZ = paperPlugin("ZzLoop", needs: ["AaLoop"])
    let loopRan = [LabCheck("AaLoop 1.0 loads", .failed, "It was never enabled."), LabCheck("ZzLoop 1.0 loads", .failed, "It was never enabled.")]
    equal(LabDependencies.markCascades(loopRan, group: [loopA, loopZ]), loopRan, "two that require each other and both fail both stay failed, since neither explains the other")
    equal(LabDependencies.markCascades([LabCheck("MadeUpNeedy 1.0 loads", .failed)], group: [base, needy]).first?.outcome, .failed, "a plugin that fails when what it requires loaded stays failed")
}

/// Each group's restart log stays with its own result, after the lab is deleted and after the app is opened again.
@MainActor func labRestartLogChecks() async {
    section("The lab: each group keeps its restart log (K804)")
    let root = LabFiles.root
    guard root.path.hasPrefix(AppPaths.servers.path), ProcessInfo.processInfo.environment["GILAMONSTER_SERVERS"] != nil else {
        failures.append("lab restart log checks aren't in the sandbox: \(root.path)")
        return
    }
    let modelRoot = AppPaths.servers.appendingPathComponent("made-up-logs-\(UUID().uuidString.prefix(6))", isDirectory: true)
    // Another check may have left results here. They're put back as they were.
    let stateBefore = try? Data(contentsOf: LabFiles.state)
    let madeRoot = !FileOps.exists(root)
    defer {
        if madeRoot { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.removeItem(at: modelRoot)
        if let stateBefore { try? stateBefore.write(to: LabFiles.state) } else { try? FileManager.default.removeItem(at: LabFiles.state) }
    }
    guard madeRoot else { failures.append("a lab folder was already there, so the restart log checks didn't run"); return }

    let long = String(repeating: "x", count: 900)
    let cut = LabDependencies.restartLog((1...450).map { "line \($0)" } + [long])
    equal(cut.count, 400, "a kept log is the newest 400 lines")
    equal(cut.first, "line 52", "starting where the newest 400 start")
    equal(cut.last?.count, 401, "and a very long line is cut")
    equal(LabDependencies.restartLog(["one", "two"]), ["one", "two"], "a short log is kept whole")

    do {
        try FileOps.ensureDir(modelRoot)
        let model = ServerController(root: modelRoot, profile: ServerProfile())
        defer { model.stopTicker() }
        let lab = LabController()
        lab.acceptEULA()
        let firstLog = ["[GilaMonster] Server stopped.", "Done (1.234s)! For help, type \"help\"", "Alice joined the game"]
        let secondLog = ["[GilaMonster] Server stopped.", "Done (2.345s)! For help, type \"help\"", "[GilaMonster] Lab: Alice couldn't get back in after the restart."]
        var first = MirrorBatch(title: "Worlds and permissions", plugins: ["MadeUpWorlds"], fresh: [LabCheck("A change survives a restart", .passed)])
        first.rejoinLog = firstLog
        var second = MirrorBatch(title: "Everything else", plugins: ["MadeUpSolo"], fresh: [LabCheck("A change survives a restart", .failed, "Alice couldn't get back in after the restart.")])
        second.rejoinLog = secondLog
        let none = MirrorBatch(title: "Everything else 2", plugins: ["MadeUpMinimap"], fresh: [LabCheck("MadeUpMinimap 1.0 loads", .skipped, "Skipped: needs Dynmap (left out of the lab).")])
        // A run, with a stand-in for the station's work: it builds a lab, records the groups, and the run deletes the lab.
        lab.stationStandIn = { station in
            try FileOps.ensureDir(ServerPaths(root: root).meta)
            write("server-port=25598\nserver-ip=127.0.0.1\nmotd=made up\n", root.appendingPathComponent("server.properties"))
            var profile = ServerProfile()
            profile.isLab = true
            profile.name = LabFiles.serverName
            try JSONStore.save(profile, to: ServerPaths(root: root).profile)
            guard let c = ServerController.open(root: root) else { throw AppError("the stand-in lab didn't open") }
            lab.place(station, outcome: .failed, model: model, groups: [first, second, none])
            return c
        }
        await lab.run(.plugins, model: model)
        check(!FileOps.exists(root), "the lab is deleted when the run ends")
        let kept = lab.result(.plugins)?.groups ?? []
        equal(kept.map(\.rejoinLog), [firstLog, secondLog, nil], "each group's restart log is still with its own result, and one group's doesn't replace another's")

        // Opened again: read back from the results file.
        let reopened = LabController()
        equal(reopened.result(.plugins)?.groups.map(\.rejoinLog), [firstLog, secondLog, nil], "and they're still there when GilaMonster opens again")

        // Results saved before logs were kept have no such field, and still open.
        struct Old: Codable { var title: String; var plugins: [String]; var fresh: [LabCheck]; var notes: [String] }
        let old = try JSONEncoder().encode(Old(title: "Everything else", plugins: ["MadeUpSolo"], fresh: [], notes: []))
        let opened = try JSONDecoder().decode(MirrorBatch.self, from: old)
        check(opened.rejoinLog == nil && opened.title == "Everything else", "a result saved before logs were kept still opens, with no log")

        // Running the check again replaces the old result, logs and all.
        lab.stationStandIn = { station in
            try FileOps.ensureDir(ServerPaths(root: root).meta)
            write("server-port=25598\nserver-ip=127.0.0.1\nmotd=made up\n", root.appendingPathComponent("server.properties"))
            var profile = ServerProfile()
            profile.isLab = true
            profile.name = LabFiles.serverName
            try JSONStore.save(profile, to: ServerPaths(root: root).profile)
            guard let c = ServerController.open(root: root) else { throw AppError("the stand-in lab didn't open") }
            lab.place(station, outcome: .passed, model: model, groups: [first])
            return c
        }
        await lab.run(.plugins, model: model)
        equal(lab.result(.plugins)?.groups.map(\.rejoinLog), [firstLog], "a new run's result has only that run's logs")
        check(!FileOps.exists(root), "and its lab is deleted too")
    } catch {
        failures.append("lab restart log checks threw: \(error)")
    }
}
