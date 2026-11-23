import Foundation

/// GilaMonster's colors, as plain numbers, so the checks can hold every pair to WCAG without the app.
/// The app's Theme builds its colors from these. Change a value here and `gilamonster-check` (run by CI) fails
/// if any pair below drops under its minimum, in any appearance or under any of the color-vision simulations.
public enum Palette {
    public struct Swatch: Sendable, Equatable {
        public let light: UInt32, dark: UInt32, contrastLight: UInt32, contrastDark: UInt32
        init(_ light: UInt32, _ dark: UInt32, contrast: (UInt32, UInt32)? = nil) {
            self.light = light; self.dark = dark
            contrastLight = contrast?.0 ?? light; contrastDark = contrast?.1 ?? dark
        }
        public func hex(_ mode: Mode) -> UInt32 {
            switch mode {
            case .light: light
            case .dark: dark
            case .contrastLight: contrastLight
            case .contrastDark: contrastDark
            }
        }
    }

    /// The four appearances macOS can ask for: light, dark, and each with Increase Contrast on.
    public enum Mode: String, CaseIterable, Sendable { case light, dark, contrastLight = "light, increased contrast", contrastDark = "dark, increased contrast" }

    // GilaMonster (D272, D277): from Brand's tokens in brand/kit/palette.md. Light is cream and white, dark is deep and
    // basalt. Swap these numbers for a new palette; gilamonster-check holds every pair below in every appearance.
    public static let background = Swatch(0xF5EBDD, 0x1E1C20)
    public static let surface = Swatch(0xFFFFFF, 0x2A282C)
    public static let raised = Swatch(0xFAF3EA, 0x252327)
    /// Outlines of cards and dividers. Decoration only: anything a person clicks or types in uses controlBorder.
    public static let border = Swatch(0xE2D4C0, 0x403C44, contrast: (0x5A5560, 0xB0ABB6))
    /// Outlines of buttons and fields: 3:1 against every surface, so a control can be found without its fill.
    public static let controlBorder = Swatch(0x857D88, 0x8F8A95, contrast: (0x5A5560, 0xB0ABB6))
    public static let ink = Swatch(0x2A282C, 0xF5EBDD, contrast: (0x000000, 0xFFFFFF))
    public static let muted = Swatch(0x4B474F, 0xB9B5BE)
    /// Turquoise: structure, links and focus.
    public static let accent = Swatch(0x166F74, 0x21A4AB, contrast: (0x105155, 0x2BCED6))
    public static let accentWash = Swatch(0xD8EEEF, 0x1D3E40)
    /// Red-orange, the brand color: the one bold pop, for the main action.
    public static let pop = Swatch(0xB13917, 0xEA8060, contrast: (0x822A11, 0xF1AC97))
    public static let onPop = Swatch(0xFFFFFF, 0x1E1C20)
    public static let popText = Swatch(0xB13917, 0xEA8060, contrast: (0x822A11, 0xF1AC97))
    public static let warning = Swatch(0x95580B, 0xF2A541, contrast: (0x6D4008, 0xF4B058))
    public static let warningWash = Swatch(0xFBEBD2, 0x45351C)
    public static let danger = Swatch(0xB0183C, 0xFF7D93, contrast: (0x8B132F, 0xFFA5B4))
    public static let dangerWash = Swatch(0xFBE1E6, 0x4A2129)
    public static let info = Swatch(0x166F74, 0x21A4AB, contrast: (0x105155, 0x2BCED6))
    public static let infoWash = Swatch(0xDCEFF0, 0x1F3B3D)

    /// Plugin source badges (owner, 2026-11-15): a tint per source behind ink text, and an accent for its icon.
    /// The text is always ink, so the tint only has to keep ink readable; the accent needs 3:1 on the tint.
    public static let sources: [(name: String, wash: Swatch, accent: Swatch)] = [
        ("modrinth", Swatch(0xD9F2DF, 0x23493A), Swatch(0x1B6B3A, 0x8FE0A8)),
        ("hangar", Swatch(0xDDE7FA, 0x2A3A5C), Swatch(0x2450A8, 0xA9C3FF)),
        ("spigot", Swatch(0xFBE5D3, 0x553522), Swatch(0x9A4A10, 0xFFC08A)),
        ("github", Swatch(0xE6E3F2, 0x3A3550), Swatch(0x4B3F8C, 0xC9BEFF)),
        ("jenkins", Swatch(0xF6DEDB, 0x4F2F2C), Swatch(0x8E3A2E, 0xF5B3A8)),
        ("web", Swatch(0xFAF3EA, 0x252327), Swatch(0x4B474F, 0xB9B5BE)),
    ]

    // MARK: Pairs and their minimums

    public enum Use: String, Sendable {
        /// WCAG 1.4.3: body text needs 4.5:1. All text is held to this, large or not.
        case text = "text"
        /// WCAG 1.4.11: icons, outlines and focus rings a person needs to see need 3:1.
        case ui = "control or icon"
        public var minimum: Double { self == .text ? 4.5 : 3 }
    }

    public struct Pair: Sendable {
        public let foreground: String, background: String, use: Use
        let fg: Swatch, bg: Swatch
    }

    static let surfaces: [(String, Swatch)] = [("background", background), ("surface", surface), ("raised", raised)]

    /// Every way the app puts one color on another.
    public static let pairs: [Pair] = {
        var list: [Pair] = []
        func add(_ f: String, _ fg: Swatch, _ b: String, _ bg: Swatch, _ use: Use) { list.append(Pair(foreground: f, background: b, use: use, fg: fg, bg: bg)) }
        for (name, swatch) in [("ink", ink), ("muted", muted), ("accent", accent), ("popText", popText), ("warning", warning), ("danger", danger), ("info", info)] {
            for (s, bg) in surfaces { add(name, swatch, s, bg, .text) }
        }
        for (w, wash) in [("accentWash", accentWash), ("warningWash", warningWash), ("dangerWash", dangerWash), ("infoWash", infoWash)] {
            add("ink", ink, w, wash, .text)
            add("muted", muted, w, wash, .text)
        }
        for s in sources {
            add("ink", ink, "\(s.name) badge", s.wash, .text)
            add("\(s.name) icon", s.accent, "\(s.name) badge", s.wash, .ui)
        }
        add("onPop", onPop, "pop", pop, .text)
        add("danger", danger, "dangerWash", dangerWash, .text)
        for (t, tone, w, wash) in [("accent", accent, "accentWash", accentWash), ("warning", warning, "warningWash", warningWash), ("danger", danger, "dangerWash", dangerWash), ("info", info, "infoWash", infoWash)] {
            add(t, tone, w, wash, .ui)
        }
        for (s, bg) in surfaces {
            add("controlBorder", controlBorder, s, bg, .ui)
            add("popText", popText, s, bg, .ui)  // the main button's outline
            add("danger", danger, s, bg, .ui)                  // the danger button's outline
            add("accent", accent, s, bg, .ui)                      // focus rings, toggles, icons
        }
        return list
    }()

    // MARK: Contrast

    static func linear(_ c: UInt32) -> Double {
        let v = Double(c) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    static func rgb(_ hex: UInt32) -> (Double, Double, Double) { (linear(hex >> 16 & 0xFF), linear(hex >> 8 & 0xFF), linear(hex & 0xFF)) }

    public static func luminance(_ hex: UInt32) -> Double {
        let (r, g, b) = rgb(hex)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// WCAG's contrast ratio, from 1 to 21.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    // MARK: Color vision

    /// The common kinds of color blindness, simulated with Machado, Oliveira and Fernandes (2009) at full strength,
    /// and achromatopsia as luminance only.
    public enum Vision: String, CaseIterable, Sendable {
        case typical, protanopia, deuteranopia, tritanopia, achromatopsia
    }

    static let matrices: [Vision: [[Double]]] = [
        .protanopia: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
        .deuteranopia: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
        .tritanopia: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
    ]

    static func encode(_ v: Double) -> UInt32 {
        let c = min(max(v, 0), 1)
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt32((s * 255).rounded())
    }

    /// How a color looks with that kind of color vision.
    public static func simulate(_ hex: UInt32, _ vision: Vision) -> UInt32 {
        let (r, g, b) = rgb(hex)
        let out: (Double, Double, Double)
        switch vision {
        case .typical: return hex
        case .achromatopsia:
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            out = (y, y, y)
        default:
            let m = matrices[vision]!
            out = (m[0][0] * r + m[0][1] * g + m[0][2] * b, m[1][0] * r + m[1][1] * g + m[1][2] * b, m[2][0] * r + m[2][1] * g + m[2][2] * b)
        }
        return encode(out.0) << 16 | encode(out.1) << 8 | encode(out.2)
    }

    // MARK: The audit

    public struct Finding: Sendable {
        public let pair: Pair, mode: Mode, vision: Vision, ratio: Double
        public var line: String {
            "\(pair.foreground) on \(pair.background) (\(pair.use.rawValue)), \(mode.rawValue)\(vision == .typical ? "" : ", \(vision.rawValue)"): \(String(format: "%.2f", ratio)):1, needs \(pair.use.minimum):1"
        }
    }

    /// Every pair, in every appearance and with every kind of color vision, that falls under its minimum. Empty means it all passes.
    public static func failures() -> [Finding] {
        var out: [Finding] = []
        for pair in pairs {
            for mode in Mode.allCases {
                for vision in Vision.allCases {
                    let r = contrast(simulate(pair.fg.hex(mode), vision), simulate(pair.bg.hex(mode), vision))
                    if r < pair.use.minimum { out.append(Finding(pair: pair, mode: mode, vision: vision, ratio: r)) }
                }
            }
        }
        return out
    }

    /// The lowest ratio for each pair across everything, for the written audit.
    public static func lowest() -> [(Pair, Double, Mode, Vision)] {
        pairs.map { pair in
            var low = (Double.infinity, Mode.light, Vision.typical)
            for mode in Mode.allCases {
                for vision in Vision.allCases {
                    let r = contrast(simulate(pair.fg.hex(mode), vision), simulate(pair.bg.hex(mode), vision))
                    if r < low.0 { low = (r, mode, vision) }
                }
            }
            return (pair, low.0, low.1, low.2)
        }
    }
}
