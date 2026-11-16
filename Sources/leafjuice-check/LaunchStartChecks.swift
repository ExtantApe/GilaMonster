import Foundation
@testable import LeafJuiceCore

/// "Start when LeafJuice opens" (owner, 2026-11-16): off by default, the old setting reads as off, and a fresh launch
/// with servers that were running at quit starts nothing. Made-up servers in the sandbox home only; each is removed
/// at the end, pass or fail.
@MainActor func launchStartChecks() async {
    section("Starting servers when LeafJuice opens")
    check(!LaunchConfig().startWhenAppOpens, "a new server doesn't start when LeafJuice opens")

    let base = AppPaths.servers.appendingPathComponent("launch-start-\(UUID().uuidString.prefix(8))", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }
    do {
        var roots: [URL] = []
        for name in ["Made-up Server", "Made-up Other"] {
            let root = base.appendingPathComponent(name.replacingOccurrences(of: " ", with: "-"), isDirectory: true)
            try FileOps.ensureDir(root)
            write("server-port=25599\nserver-ip=127.0.0.1\nmotd=made up\n", root.appendingPathComponent("server.properties"))
            _ = try await ServerController.adopt(root: root, name: name)
            roots.append(root)
        }
        // Both were set to start with the app under the old key, and both were running when the app quit.
        for root in roots {
            let file = ServerPaths(root: root).profile
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var launch = json["launch"] as? [String: Any] ?? [:]
            launch["startWithApp"] = true
            launch.removeValue(forKey: "startWhenAppOpens")
            json["launch"] = launch
            try JSONSerialization.data(withJSONObject: json).write(to: file)
        }

        // A fresh launch: open them as the app does.
        let opened = roots.compactMap { ServerController.open(root: $0) }
        equal(opened.count, 2, "both made-up servers open")
        check(opened.allSatisfy { !$0.profile.launch.startWhenAppOpens }, "the old start-with-app setting reads as off")
        check(LaunchStart.servers(opened, advisorTrial: false, snapshot: false).isEmpty,
              "a fresh launch with servers that were running at quit starts nothing")
        check(opened.allSatisfy { !$0.state.isLive }, "and each server opens stopped")

        // Turned on by hand for one server, it's the only one that starts, and it stays on after a save.
        opened[0].profile.launch.startWhenAppOpens = true
        let again = roots.compactMap { ServerController.open(root: $0) }
        equal(LaunchStart.servers(again, advisorTrial: false, snapshot: false).map { $0.profile.name }, ["Made-up Server"],
              "with the box on for one server, only that one starts")
        let saved = (try? String(contentsOf: ServerPaths(root: roots[0]).profile, encoding: .utf8)) ?? ""
        check(saved.contains("startWhenAppOpens") && !saved.contains("startWithApp"), "the setting saves under its new name only")
        check(LaunchStart.servers(again, advisorTrial: true, snapshot: false).isEmpty, "the Advisor trial starts nothing")
        check(LaunchStart.servers(again, advisorTrial: false, snapshot: true).isEmpty, "a snapshot starts nothing")
    } catch {
        failures.append("launch start checks threw: \(error)")
    }
}
