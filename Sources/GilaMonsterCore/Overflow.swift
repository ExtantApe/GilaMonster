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

    /// Reads the snapshot's overflow-report.txt: "checked N of M pages", where M is every page the run was asked to
    /// draw, then one OVERFLOW line for each page wider than the window. A report that isn't in that form counts as
    /// not having run (0 of 0), and the check then fails: N must equal M, and M must be more than zero.
    public static func readReport(_ text: String) -> (pages: Int, expected: Int, overflowing: [String]) {
        let lines = text.split(separator: "\n").map(String.init)
        var pages = 0, expected = 0
        for line in lines where line.hasPrefix("checked ") && line.hasSuffix(" pages") {
            let parts = line.dropFirst(8).dropLast(6).split(separator: " ")
            if parts.count == 3, parts[1] == "of", let n = Int(parts[0]), let m = Int(parts[2]) { pages = n; expected = m }
        }
        return (pages, expected, lines.filter { $0.hasPrefix("OVERFLOW ") })
    }

    /// Which things go on which row when a row of buttons is laid out in `available` points: as many as fit, in
    /// order, then the next row. The fit is exact: things fit when their widths and the gaps between them are no
    /// wider than the room, so a row breaks only when it really doesn't fit. One thing wider than the room still
    /// gets a row to itself.
    public static func flowRows(_ widths: [Double], spacing: Double, available: Double) -> [[Int]] {
        var rows: [[Int]] = [], used = 0.0
        for (index, width) in widths.enumerated() {
            if let last = rows.last, !last.isEmpty, used + spacing + width <= available + 0.0001 {
                rows[rows.count - 1].append(index)
                used += spacing + width
            } else {
                rows.append([index])
                used = width
            }
        }
        return rows
    }

    /// A long path or name on a button, cut in its middle to `limit` characters. The whole of it goes in the
    /// button's tooltip and VoiceOver label.
    public static func middle(_ text: String, limit: Int) -> String {
        guard limit >= 5, text.count > limit else { return text }
        let keep = limit - 1, head = (keep + 1) / 2, tail = keep / 2
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }

    /// Reads the snapshot's dialog-report.txt: "checked N of M dialogs", a CLIPPED line for each sheet whose content
    /// reaches the left or right edge of its picture, and a SKIPPED line naming each sheet that can't be judged that
    /// way and why. A report that isn't in that form counts as not having run.
    public static func readDialogReport(_ text: String) -> (checked: Int, expected: Int, clipped: [String], skipped: [String]) {
        let lines = text.split(separator: "\n").map(String.init)
        var checked = 0, expected = 0
        for line in lines where line.hasPrefix("checked ") && line.hasSuffix(" dialogs") {
            let parts = line.dropFirst(8).dropLast(8).split(separator: " ")
            if parts.count == 3, parts[1] == "of", let n = Int(parts[0]), let m = Int(parts[2]) { checked = n; expected = m }
        }
        return (checked, expected, lines.filter { $0.hasPrefix("CLIPPED ") }, lines.filter { $0.hasPrefix("SKIPPED ") })
    }

    /// Whether a row of one column's pixels shows content at a picture's edge: any pixel that differs from the
    /// column's first by more than a little. A sheet has padding all round, so its edge columns are one flat color
    /// unless something has run off the side. Each pixel is red, green and blue, 0 to 255.
    public static func edgeHasContent(_ column: [(r: Int, g: Int, b: Int)], tolerance: Int = 10) -> Bool {
        guard let first = column.first else { return false }
        return column.contains { abs($0.r - first.r) > tolerance || abs($0.g - first.g) > tolerance || abs($0.b - first.b) > tolerance }
    }

    /// Whether the allowlist shows its search field.
    public static func showsAllowlistSearch(entries: Int) -> Bool { entries > Limit.allowlistSearchFrom }
    /// Whether the Worlds page shows its filter.
    public static func showsWorldsFilter(worlds: Int) -> Bool { worlds > Limit.worldsFilterFrom }

    /// Seconds after a page opens, or the app starts, when announcements stay quiet: VoiceOver reads the page then.
    public static let quietAfterPageChange: TimeInterval = 1
    public static let quietAtLaunch: TimeInterval = 2

    /// Words the views use that checks hold.
    public static func updateBadge(_ version: String) -> String { "Update \(version)" }
    public static let onlineWord = "online"
    public static func onlineMark(_ online: Bool) -> String? { online ? onlineWord : nil }

    /// The limits each list uses, in one place (from Brand's review, 2026-11-23).
    public enum Limit {
        public static let allowlistSearchFrom = 12, allowlistShown = 25
        public static let turnedAway = 5, warnings = 3, profiles = 6, changesPerGroup = 8, recentSignIns = 10
        public static let worldsFilterFrom = 10
    }
}
