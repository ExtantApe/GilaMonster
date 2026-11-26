import Foundation

/// The window's five sections (K786, owner's pick 2026-11-25: "B: desert base, calmed down"). The basalt spine shows
/// one bead per section, and the trail across the top shows the chosen section's pages as tabs. Home holds Overview;
/// the other four are SidebarGroups' groups, unchanged, so every page keeps exactly one place.
public enum Sections {
    public struct Section: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// (page key, page title), in trail order.
        public let pages: [(key: String, title: String)]
        public static func == (a: Section, b: Section) -> Bool { a.id == b.id && a.pages.map(\.key) == b.pages.map(\.key) }
    }

    /// Home first, then the sidebar's groups in their agreed order.
    public static let all: [Section] = [Section(id: "home", title: "Home", pages: [SidebarGroups.top])]
        + SidebarGroups.groups.map { Section(id: $0.id, title: $0.title, pages: $0.pages) }

    /// The section a page belongs to.
    public static func section(of pageKey: String) -> Section? { all.first { s in s.pages.contains { $0.key == pageKey } } }

    /// ⌥⌘1 to ⌥⌘5 pick a section, in spine order. Anything else picks nothing.
    public static func section(forDigit digit: Int) -> Section? { (1...all.count).contains(digit) ? all[digit - 1] : nil }

    /// What VoiceOver reads for a bead: its word, how many pages it holds, and what's waiting there.
    public static func spoken(_ title: String, pages: Int, waiting: Int) -> String {
        var text = "\(title), \(pages) \(pages == 1 ? "page" : "pages")"
        if waiting > 0 { text += ", \(waiting) waiting" }
        return text
    }

    /// The page before or after `current` on the trail, wrapping round at the ends (⌃Tab and ⌃⇧Tab).
    /// A page that isn't on the trail goes to the first one.
    public static func step(from current: String, in pages: [String], by offset: Int) -> String? {
        guard !pages.isEmpty else { return nil }
        guard let at = pages.firstIndex(of: current) else { return pages.first }
        let n = pages.count
        return pages[((at + offset) % n + n) % n]
    }

    /// The page a bead opens: the one last used in that section if it's still shown, otherwise the first.
    public static func landing(_ section: Section, visible: [String], last: String?) -> String? {
        let shown = section.pages.map(\.key).filter { visible.contains($0) }
        if let last, shown.contains(last) { return last }
        return shown.first
    }

    /// A bead's badge: the sum of its pages' badges.
    public static func badge(_ section: Section, badges: [String: Int]) -> Int {
        section.pages.reduce(0) { $0 + (badges[$1.key] ?? 0) }
    }
}

/// The 8 by 8 pixel status glyphs (K786). A state always shows its shape and its word, so it never rests on color:
/// Up is a filled circle, Starting a ring, Down a triangle and Stopped a square.
public enum PixelGlyph: String, CaseIterable, Sendable {
    case up, starting, down, stopped

    /// Eight rows of eight, `#` for a filled pixel.
    public var rows: [String] {
        switch self {
        case .up: ["..####..", ".######.", "########", "########", "########", "########", ".######.", "..####.."]
        case .starting: ["..####..", ".######.", "##....##", "##....##", "##....##", "##....##", ".######.", "..####.."]
        case .down: ["...##...", "...##...", "..####..", "..####..", ".######.", ".######.", "########", "########"]
        case .stopped: ["........", ".######.", ".######.", ".######.", ".######.", ".######.", ".######.", "........"]
        }
    }

    /// The filled pixels as (column, row), for drawing.
    public var pixels: [(x: Int, y: Int)] {
        rows.enumerated().flatMap { y, row in row.enumerated().compactMap { x, c in c == "#" ? (x, y) : nil } }
    }

    /// The shape's own name, for the key under a list.
    public var shapeName: String {
        switch self {
        case .up: "Filled circle"
        case .starting: "Ring"
        case .down: "Triangle"
        case .stopped: "Square"
        }
    }
}

extension ServerState {
    /// The pixel glyph for a state: shape first, so it never rests on color. A crash and a server running outside
    /// GilaMonster get the triangle, as both need looking at; the word beside it says which.
    public var glyph: PixelGlyph {
        switch self {
        case .running: .up
        case .starting, .stopping: .starting
        case .crashed, .external: .down
        case .stopped: .stopped
        }
    }
}

/// An 8 by 8 face made up on the Mac from a player's name (K786). Nothing is fetched: real skins would send player
/// names to an outside service, and children play here. The same name always gives the same face.
public enum PixelFace {
    /// Art colors, never text: skins, hair, the whites of the eyes, eye colors and a mouth shadow.
    public static let skins: [UInt32] = [0xF1C9A5, 0xD9A27A, 0xB97A52, 0x8D5A3B, 0xE8B48C]
    public static let hairs: [UInt32] = [0x3B2A1E, 0x6B4226, 0xC9A15A, 0x2A282C, 0xA0412D, 0x5A5560]
    public static let eyes: [UInt32] = [0x1C5E8C, 0x3F7A2A, 0x5A3A22, 0x2A282C]
    public static let white: UInt32 = 0xFFFFFF

    /// FNV-1a over the name's UTF-16 units, as the mockup drew it.
    public static func hash(_ name: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for unit in name.utf16 { h ^= UInt32(unit); h = h &* 16_777_619 }
        return h
    }

    /// 64 colors, row by row from the top left.
    public static func pixels(_ name: String) -> [UInt32] {
        let h = hash(name)
        var grid = [UInt32](repeating: skins[Int(h % 5)], count: 64)
        func fill(_ x: Int, _ y: Int, _ w: Int, _ hgt: Int, _ c: UInt32) {
            for yy in y..<min(8, y + hgt) { for xx in x..<min(8, x + w) { grid[yy * 8 + xx] = c } }
        }
        let hair = hairs[Int((h >> 3) % 6)]
        fill(0, 0, 8, 2 + Int((h >> 6) & 1), hair)
        fill(0, 2, 1, 2 + Int((h >> 7) & 1), hair)
        fill(7, 2, 1, 2, hair)
        fill(1, 4, 2, 1, white); fill(5, 4, 2, 1, white)
        let eye = eyes[Int((h >> 9) % 4)]
        fill(2, 4, 1, 1, eye); fill(5, 4, 1, 1, eye)
        // A mouth: the skin a quarter darker.
        let skin = grid[6 * 8 + 3]
        let shade = UInt32((Double((skin >> 16) & 0xFF) * 0.75).rounded()) << 16 | UInt32((Double((skin >> 8) & 0xFF) * 0.75).rounded()) << 8 | UInt32((Double(skin & 0xFF) * 0.75).rounded())
        fill(3, 6, 2, 1, shade)
        return grid
    }

    /// One or two letters for a name, for VoiceOver-free places that can't draw: the first letter, and the next capital
    /// or digit if there is one ("MadeUpKid" is MU).
    public static func initials(_ name: String) -> String {
        guard let first = name.first else { return "?" }
        let rest = name.dropFirst().first { $0.isUppercase || $0.isNumber }
        return String(first).uppercased() + (rest.map(String.init) ?? "")
    }
}

/// The icon's lizard on its own 14 by 16 grid, for the top of the spine. Art colors only, never text.
public enum PixelLizard {
    public static let rows: [String] = [
        "....bbbbbb....",
        "....barbsb....",
        "...btbbsstb...",
        "...bbrrbbbb...",
        "bb...brrb...bb",
        ".bbbbaarrbbbb.",
        "....babbrb....",
        "....bbrrrb....",
        "....brrrbb....",
        "..bbrrbbrrbb..",
        ".bb.brrbbb.bb.",
        "bbb.brrbrb.bbb",
        "....brbbrb....",
        ".....bbabbb...",
        ".......bbssb..",
        ".........bbbb.",
    ]
    /// Basalt, amber, red-orange, salmon and turquoise from brand/kit/palette.md's icon art colors.
    public static let colors: [Character: UInt32] = ["b": 0x2A282C, "a": 0xF2A541, "r": 0xE4572E, "s": 0xF28B82, "t": 0x1C8C92]
    /// The cream tile it sits on in both appearances, because its outline is basalt.
    public static let tile: UInt32 = 0xF5EBDD
}

/// The bead band on top of the Allow prompt: one 48 by 12 tile of beads (brand.md, Direction 1), drawn at half size.
/// Decoration only. Each bead is (x, y, color) on the tile; the band's ground is basalt.
public enum BeadBand {
    public static let ground: UInt32 = 0x2A282C
    public static let beads: [(x: Double, y: Double, color: UInt32)] = {
        let red: [(Double, Double)] = [(3, 3), (9, 3), (15, 3), (45, 3), (6, 9), (12, 9), (30, 9)]
        let dim: [(Double, Double)] = [(21, 3), (33, 3), (39, 3), (0, 9), (18, 9), (36, 9), (42, 9), (48, 9)]
        return red.map { ($0.0, $0.1, UInt32(0xE4572E)) } + [(27, 3, 0xF28B82), (24, 9, 0xF2A541)] + dim.map { ($0.0, $0.1, UInt32(0x3A363D)) }
    }()
    public static let tileWidth: Double = 48
    public static let radius: Double = 2.5
}

/// The Players page's roster (K786): who's on now first, by name, then everyone seen before, most recent first.
public enum PlayerRoster {
    public static func split(_ known: [PlayerInfo], online: Set<String>) -> (onNow: [PlayerInfo], seenBefore: [PlayerInfo]) {
        let on = online
        let onNow = known.filter { on.contains($0.title) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let seen = known.filter { !on.contains($0.title) }.sorted {
            switch ($0.lastSeen, $1.lastSeen) {
            case let (a?, b?) where a != b: return a > b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        return (onNow, seen)
    }

    /// The order the roster lists everyone in, for ↑↓.
    public static func order(_ known: [PlayerInfo], online: Set<String>) -> [PlayerInfo] {
        let s = split(known, online: online)
        return s.onNow + s.seenBefore
    }
}
