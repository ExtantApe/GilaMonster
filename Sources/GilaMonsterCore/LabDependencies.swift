import Foundation

/// What the Lab does about a plugin that needs another plugin (K804). A plugin whose required plugin isn't in the run
/// can't load, and that says nothing about the plugin itself, so it's reported as skipped with what it needs.
public enum LabDependencies {
    /// Why a needed plugin isn't there.
    public enum Why: String, Sendable {
        case leftOut, notInstalled, turnedOff, didntLoad, skipped

        var words: String {
            switch self {
            case .leftOut: "left out of the lab"
            case .notInstalled: "not installed"
            case .turnedOff: "turned off"
            case .didntLoad: "didn't load"
            case .skipped: "skipped too"
            }
        }
    }

    public struct Need: Equatable, Sendable {
        public var name: String
        public var why: Why
    }

    public struct Skip: Equatable, Sendable {
        public var plugin: InstalledPlugin
        public var needs: [Need]
        /// "Skipped: needs MadeUpMaps (left out of the lab)."
        public var detail: String { LabDependencies.detail(needs) }
        /// The row shown in place of the plugin's "loads" check.
        public var check: LabCheck { LabCheck(LabDependencies.loadsTitle(plugin), .skipped, detail) }
    }

    /// The title of a plugin's "loads" check, the same whether it ran or was skipped.
    static func loadsTitle(_ plugin: InstalledPlugin) -> String { "\(plugin.name) \(plugin.version) loads" }

    static func detail(_ needs: [Need]) -> String {
        let parts = needs.map { "\($0.name) (\($0.why.words))" }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1] : parts.first ?? ""
        return "Skipped: needs \(list)."
    }

    /// The plugins that can't run in a lab because something they require isn't in it, with what and why.
    /// `installed` is everything in the server's plugins folder, on or off. `leftOut` says which the Lab leaves out.
    /// A plugin that needs a skipped plugin is skipped too, however long the chain. Optional needs never count.
    public static func skips(installed: [InstalledPlugin], leftOut: (InstalledPlugin) -> Bool) -> [Skip] {
        let enabled = installed.filter(\.enabled)
        let running = enabled.filter { !leftOut($0) }
        let runningKeys = Set(running.map(\.key))
        let leftOutNames = Dictionary(enabled.filter(leftOut).map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        let offNames = Dictionary(installed.filter { !$0.enabled }.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(running.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })

        var needs: [String: [Need]] = [:]
        for plugin in running {
            for wanted in plugin.descriptor?.depend ?? [] {
                let key = wanted.lowercased()
                if runningKeys.contains(key) { continue }
                let need: Need
                if let name = leftOutNames[key] { need = Need(name: name, why: .leftOut) }
                else if let name = offNames[key] { need = Need(name: name, why: .turnedOff) }
                else { need = Need(name: wanted, why: .notInstalled) }
                if needs[plugin.fileName]?.contains(need) != true { needs[plugin.fileName, default: []].append(need) }
            }
        }
        // Then whatever needs one of those, until nothing more follows. A circle of plugins that only need each other
        // never gets here, because none of them is missing anything.
        var skippedKeys = Set(running.filter { needs[$0.fileName] != nil }.map(\.key))
        var grew = true
        while grew {
            grew = false
            for plugin in running where needs[plugin.fileName] == nil {
                let chained = (plugin.descriptor?.depend ?? []).map { $0.lowercased() }.filter { skippedKeys.contains($0) && $0 != plugin.key }
                guard !chained.isEmpty else { continue }
                var seen: Set<String> = []
                needs[plugin.fileName] = chained.filter { seen.insert($0).inserted }.map { Need(name: names[$0] ?? $0, why: .skipped) }
                skippedKeys.insert(plugin.key)
                grew = true
            }
        }
        return running.compactMap { plugin in needs[plugin.fileName].map { Skip(plugin: plugin, needs: $0) } }
    }

    /// After a group has run: a plugin that didn't load, and needs a plugin in the same group that didn't load for its
    /// own reasons, is shown as skipped. The plugin at the root of it stays failed, so the cause is still on the page.
    /// Plugins that only need each other all stay failed, because none of them explains the others.
    static func markCascades(_ checks: [LabCheck], group: [InstalledPlugin]) -> [LabCheck] {
        func failedToLoad(_ plugin: InstalledPlugin) -> Bool {
            checks.contains { $0.outcome == .failed && $0.title == loadsTitle(plugin) }
        }
        let failed = group.filter(failedToLoad)
        let failedKeys = Set(failed.map(\.key))
        func failedNeeds(_ plugin: InstalledPlugin) -> [String] {
            (plugin.descriptor?.depend ?? []).map { $0.lowercased() }.filter { failedKeys.contains($0) && $0 != plugin.key }
        }
        var explained = Set(failed.filter { failedNeeds($0).isEmpty }.map(\.key))
        var details: [String: String] = [:]
        var grew = true
        while grew {
            grew = false
            for plugin in failed where !explained.contains(plugin.key) {
                let cause = failedNeeds(plugin).filter(explained.contains)
                guard !cause.isEmpty else { continue }
                var seen: Set<String> = []
                let needs = cause.filter { seen.insert($0).inserted }.map { key in Need(name: failed.first { $0.key == key }?.name ?? key, why: .didntLoad) }
                details[loadsTitle(plugin)] = detail(needs)
                explained.insert(plugin.key)
                grew = true
            }
        }
        return checks.map { check in
            guard check.outcome == .failed, let detail = details[check.title] else { return check }
            return LabCheck(check.title, .skipped, detail)
        }
    }

    /// The end of a group's console from its restart step: the newest lines, each cut to a sane width, so a result can
    /// keep it without the lab's file growing without limit.
    static func restartLog(_ lines: [String], limit: Int = 400, width: Int = 400) -> [String] {
        lines.suffix(limit).map { $0.count > width ? String($0.prefix(width)) + "…" : $0 }
    }
}
