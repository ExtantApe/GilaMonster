import Foundation

/// Rules for keeping long content readable (owner, 2026-11-23: "make sure they factor in things like sections getting
/// too big because of overflow info, and breaking that info proactively into more readable and discernible areas").
/// The views use these, and gilamonster-check holds them with heavy made-up data.
public enum Overflow {
    /// A callout's title is one plain sentence. Anything longer, such as a raw error used as the title, keeps its first
    /// sentence (up to 120 characters) as the title and moves the rest into the detail, ahead of any detail it had.
    public static func callout(title: String, detail: String?) -> (title: String, detail: String?) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = clean.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? clean
        var cut = firstLine
        if let end = firstLine.range(of: ". ") { cut = String(firstLine[..<end.lowerBound]) + "." }
        if cut.count > 120 { cut = String(cut.prefix(117)).trimmingCharacters(in: .whitespaces) + "…" }
        guard cut != clean else { return (clean, detail) }
        let rest = cut.hasSuffix("…") ? clean : String(clean.dropFirst(cut.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = [rest, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return (cut, joined.isEmpty ? nil : joined)
    }

    /// Lines of detail a callout shows before "Show Details".
    public static let detailLines = 3

    /// Whether a detail needs "Show Details": more than three lines, or more than about three lines' worth of text.
    public static func isLong(_ detail: String?) -> Bool {
        guard let detail else { return false }
        return detail.split(separator: "\n", omittingEmptySubsequences: false).count > detailLines || detail.count > 240
    }

    /// The first `limit` items, unless expanded, and how many are left for "Show N More".
    public static func slice<T>(_ items: [T], limit: Int, expanded: Bool) -> (shown: [T], hidden: Int) {
        guard !expanded, items.count > limit else { return (items, 0) }
        return (Array(items.prefix(limit)), items.count - limit)
    }

    /// Items matching a search, case and accents ignored. An empty search matches everything.
    public static func matching<T>(_ items: [T], _ query: String, _ text: (T) -> String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { text($0).range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Worlds the server loads when it starts: its own worlds, and Multiverse worlds that autoload. Everything else
    /// (a folder Multiverse doesn't know, a missing folder, a world set not to autoload) is "Not loaded". GilaMonster
    /// doesn't ask the running server what it has loaded, so a world unloaded by hand still shows as Loaded.
    public static func loadsAtStartup(_ world: WorldEntry) -> Bool {
        if world.folderMissing { return false }
        if world.isCore || world.isMain { return true }
        guard let mv = world.multiverse else { return false }
        return mv.autoLoad
    }

    /// The groups the Changes page lists, in this order. Plugin installs, removals and toggles are one group.
    public enum ChangeGroup: Int, CaseIterable, Sendable {
        case software, plugins, configs, players
        public var title: String {
            switch self {
            case .software: "Software"
            case .plugins: "Plugins"
            case .configs: "Settings and files"
            case .players: "Player restores"
            }
        }
        public var symbol: String {
            switch self {
            case .software: "shippingbox"
            case .plugins: "puzzlepiece.extension"
            case .configs: "doc.text"
            case .players: "person.crop.circle.badge.clock"
            }
        }
    }

    public static func group(of change: PendingChange) -> ChangeGroup {
        switch change.kind {
        case .software: .software
        case .pluginInstall, .pluginRemove, .pluginToggle: .plugins
        case .config: .configs
        case .playerRestore: .players
        }
    }

    /// Changes grouped by kind, empty groups left out, each keeping its order.
    public static func grouped(_ changes: [PendingChange]) -> [(group: ChangeGroup, changes: [PendingChange])] {
        ChangeGroup.allCases.compactMap { g in
            let mine = changes.filter { group(of: $0) == g }
            return mine.isEmpty ? nil : (g, mine)
        }
    }

    /// Reads the snapshot's overflow-report.txt: how many pages it drew, and the pages that were wider than the window.
    /// A report with no "checked N pages" line, or with N of zero, counts as not having run.
    public static func readReport(_ text: String) -> (pages: Int, overflowing: [String]) {
        let lines = text.split(separator: "\n").map(String.init)
        let pages = lines.compactMap { line -> Int? in
            guard line.hasPrefix("checked "), line.hasSuffix(" pages") else { return nil }
            return Int(line.dropFirst(8).dropLast(6))
        }.first ?? 0
        return (pages, lines.filter { $0.hasPrefix("OVERFLOW ") })
    }

    /// The limits each list uses, in one place (from Brand's review, 2026-11-23).
    public enum Limit {
        public static let allowlistSearchFrom = 12, allowlistShown = 25
        public static let turnedAway = 5, warnings = 3, profiles = 6, changesPerGroup = 8, recentSignIns = 10
        public static let worldsFilterFrom = 10
    }
}
