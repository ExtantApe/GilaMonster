import Foundation

/// Allowed-command entries with typed slots (K679, 2026-11-16). An entry like `rewild why {world} {int} {int}` lets a
/// session send exactly those words with each slot filled by a value of that type, and nothing else: no extra words,
/// no other characters, no second command. Only the owner adds entries, in Settings. Patterns are refused for commands
/// that change who may do what, or that stop or remove anyone, because a slot there would hand over that power.
public enum CommandPattern {
    public enum Slot: String, CaseIterable, Sendable {
        case world, int, player
        /// What a session may put in this slot. Worlds are checked again against the server's real world folders.
        func accepts(_ value: String, worlds: [String]?) -> Bool {
            func only(_ v: Substring, _ extra: String = "") -> Bool {
                v.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || extra.unicodeScalars.contains($0)) }
            }
            switch self {
            case .int:
                let digits = value.hasPrefix("-") ? value.dropFirst() : Substring(value)
                return (1...9).contains(digits.count) && digits.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
            case .player: return (3...16).contains(value.count) && only(Substring(value))
            case .world:
                guard (1...64).contains(value.count), let first = value.first, first != "." && first != "-", only(Substring(value), ".-") else { return false }
                return worlds.map { $0.contains(value) } ?? true
            }
        }
        var example: [String] {
            switch self {
            case .world: ["world"]
            case .int: ["120", "-64"]
            case .player: ["MadeUp_Fox", "Sample42"]
            }
        }
    }

    /// Command roots, and root-plus-word pairs, that never take a pattern.
    static let writeRoots: Set<String> = [
        "lp", "luckperms", "perm", "perms", "permissions", "op", "deop", "whitelist", "ban", "ban-ip", "pardon", "pardon-ip",
        "stop", "restart", "kick", "kill", "give", "gamemode", "tp", "teleport", "execute", "sudo", "clear", "effect",
        "setblock", "fill", "summon", "data", "attribute", "item", "enchant", "xp", "experience", "tell", "msg", "w", "say",
        "me", "tellraw", "title", "function", "reload", "plugman", "eco", "money", "mute", "unmute", "tempban", "jail",
    ]
    static let writePairs: Set<String> = ["rewild approve", "rewild reset", "rewild undo", "mayor set", "mayor grant", "mayor remove", "sheriff set", "sheriff add", "sheriff remove"]

    public static func isPattern(_ entry: String) -> Bool { entry.contains("{") || entry.contains("}") }

    /// The command's root as a group key: lowercased, without a `plugin:` namespace.
    public static func root(_ entry: String) -> String {
        let first = entry.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        return first.split(separator: ":").last.map(String.init) ?? first
    }

    /// Why this entry can't be a pattern, or nil when it can. `entry` is already normalized.
    public static func problem(_ entry: String) -> String? {
        let words = entry.split(separator: " ").map(String.init)
        guard let first = words.first, !isSlot(first) && !first.contains("{") else { return "A pattern starts with the command's own name, not a slot." }
        for w in words where w.contains("{") || w.contains("}") {
            guard isSlot(w) else { return "Slots are {world}, {int} or {player}, each as a word of its own." }
        }
        guard words.contains(where: isSlot) else { return "A pattern needs at least one slot." }
        let r = root(entry)
        let literals = words.prefix { !isSlot($0) }.map { $0.lowercased() }
        let pair = literals.count > 1 ? "\(r) \(literals[1])" : nil
        if writeRoots.contains(r) || pair.map(writePairs.contains) == true || words.contains(where: { $0.lowercased() == "approve" }) {
            return "\(entry.split(separator: " ").prefix(2).joined(separator: " ")) changes the server or who may do what, so it only goes on the list exactly as written."
        }
        return nil
    }

    static func isSlot(_ word: String) -> Bool { word.hasPrefix("{") && word.hasSuffix("}") && Slot(rawValue: String(word.dropFirst().dropLast())) != nil }

    /// Whether a normalized command fills this pattern. With `worlds` nil, a world only has to look like a folder name.
    public static func matches(_ command: String, pattern: String, worlds: [String]?) -> Bool {
        guard problem(pattern) == nil else { return false }
        let got = command.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let want = pattern.split(separator: " ").map(String.init)
        guard got.count == want.count else { return false }
        for (g, w) in zip(got, want) {
            if isSlot(w) {
                guard let slot = Slot(rawValue: String(w.dropFirst().dropLast())), slot.accepts(g, worlds: worlds) else { return false }
            } else if g != w {
                return false
            }
        }
        return true
    }

    /// The pattern filled with sample values, for Settings.
    public static func example(_ pattern: String, worlds: [String] = []) -> String {
        var used: [Slot: Int] = [:]
        return pattern.split(separator: " ").map { word -> String in
            let w = String(word)
            guard isSlot(w), let slot = Slot(rawValue: String(w.dropFirst().dropLast())) else { return w }
            let n = used[slot, default: 0]; used[slot] = n + 1
            if slot == .world, !worlds.isEmpty { return worlds[n % worlds.count] }
            return slot.example[n % slot.example.count]
        }.joined(separator: " ")
    }

    // MARK: Groups

    /// Vanilla and Paper commands, shown together as Server.
    static let serverRoots: Set<String> = [
        "list", "tps", "mspt", "save-all", "save-on", "save-off", "seed", "time", "weather", "difficulty", "gamerule",
        "worldborder", "version", "ver", "plugins", "pl", "paper", "spark", "help", "banlist", "whitelist", "say", "tellraw",
    ]

    public struct Group: Equatable, Sendable {
        public let name: String
        public let entries: [String]
    }

    /// The list as Settings shows it: Server first, then plugins alphabetically; inside each, read-only commands
    /// first and reloads after, each alphabetical. `plugins` gives proper names for roots, such as WelcomeWagon.
    public static func grouped(_ entries: [String], plugins: [String] = []) -> [Group] {
        let names = Dictionary(plugins.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var buckets: [String: [String]] = [:]
        for e in entries {
            let r = root(e)
            let name = serverRoots.contains(r) || e.lowercased().hasPrefix("minecraft:") ? "Server" : (names[r] ?? r)
            buckets[name, default: []].append(e)
        }
        func isReload(_ e: String) -> Bool { e.split(separator: " ").contains { ["reload", "rl"].contains($0.lowercased()) } }
        func alpha(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        return buckets.keys.sorted { a, b in
            if a == "Server" || b == "Server" { return a == "Server" && b != "Server" }
            return alpha(a, b)
        }.map { name in
            let list = buckets[name]!
            return Group(name: name, entries: list.filter { !isReload($0) }.sorted(by: alpha) + list.filter(isReload).sorted(by: alpha))
        }
    }
}
