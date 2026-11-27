import CoreText
import Foundation

/// The rules for GilaMonster's pixel type (K820, owner 2026-11-26: "Gila monster should have more pixelated but readable
/// text. It should feel like an old video game console."). Pixelify Sans 700 draws the one screen title, Departure Mono
/// draws headings, labels, buttons, badges, tabs and numbers, and the system font keeps anything that wraps.
///
/// Everything here is plain arithmetic, so `gilamonster-check` holds it: which face each kind of text gets, the size
/// it snaps to, what Bold Text and a 1x screen change, and what the setting starts as. The app only turns the answer
/// into a font (`TypeToken` in the app target).
public enum PixelType {
    /// The words under the Pixel font switch. Off sends headings, labels, buttons and numbers to the system font. The
    /// status sentence, a player's name and the Allow prompt's sentence go back to the display face they had before,
    /// so the hint says "for them" and promises nothing about the rest. Its last sentence is `firstLaunchDefault`
    /// in words.
    public static let settingHint = "Headings, labels, buttons and numbers use a pixel typeface. Turn this off to use the system font for them. It starts off when text is larger than the default, Bold Text is on, or the Mac has no Retina screen."
    /// The Pixel font setting's key.
    public static let key = "pixelFont"
    /// Both pixel faces are drawn on an 11-pixel em, so text is sharp only when one font pixel is a whole number of
    /// screen pixels.
    public static let em = 11.0
    /// The system's body size when Text Size is at its default.
    public static let defaultBody = 13.0

    public static let departureName = "DepartureMono-Regular"
    public static let pixelifyName = "PixelifySans-Regular"

    public enum Weight: Sendable { case regular, medium, semibold, bold }
    public enum Face: Equatable, Sendable {
        case system
        /// The system's fixed-width face, for logs, commands and ids.
        case systemMono
        case departure
        /// Pixelify Sans at weight 700.
        case pixelify
        /// Lilita One, the display face from before the pixel type. Only drawn with the setting off.
        case lilita
    }

    /// What the text is for.
    public enum Role: Equatable, Sendable {
        /// The one title of a screen. `points` is its system size: 26 for a page, 28 for Overview's status sentence.
        case screenTitle(Double)
        /// A status sentence or a name that was set in the display face before: the screen title when it is large.
        case display(Double)
        /// The Allow prompt's sentence. It wraps, so with pixel type on it is the system font.
        case promptSentence
        /// A sheet's or a section's title, by its system size (15 or 17).
        case title(Double)
        /// Card and group headings: small capitals with one font pixel of extra spacing.
        case heading
        /// Labels, buttons, badges, tabs and row titles.
        case label(Weight)
        /// Counts, sizes, clocks and addresses.
        case number
        /// Anything that wraps: help text, explanations, errors, sub-lines.
        case body
        /// Logs, commands and ids.
        case mono
    }

    /// What the Mac and the setting say right now.
    public struct Conditions: Equatable, Sendable {
        /// The Pixel font setting.
        public var on: Bool
        /// Whether each face was registered. A face that didn't load is never asked for.
        public var departureLoaded: Bool
        public var pixelifyLoaded: Bool
        /// The system's resolved body size in points (13 at the default Text Size).
        public var bodySize: Double
        /// Bold Text in Accessibility.
        public var boldText: Bool
        /// Screen pixels per point where the text is drawn.
        public var scale: Double

        public init(on: Bool = true, departureLoaded: Bool = true, pixelifyLoaded: Bool = true, bodySize: Double = PixelType.defaultBody, boldText: Bool = false, scale: Double = 2) {
            self.on = on; self.departureLoaded = departureLoaded; self.pixelifyLoaded = pixelifyLoaded
            self.bodySize = bodySize; self.boldText = boldText; self.scale = scale
        }

        /// How much larger than the default the system's text is.
        public var factor: Double { bodySize > 0 ? bodySize / PixelType.defaultBody : 1 }
        /// Labels, buttons and numbers are in Departure Mono. It has one weight, so Bold Text sends them to the system
        /// font, which macOS bolds itself. On a 1x screen above the default size the next sharp size is double, so
        /// they go to the system font there too.
        public var pixelLabels: Bool { on && departureLoaded && !boldText && !(scale < 2 && factor > 1.0001) }
        public var pixelTitle: Bool { on && pixelifyLoaded }
        /// The label size in points.
        public var labelSize: Double { pixelLabels ? PixelType.snap(PixelType.em, body: bodySize, scale: scale) : PixelType.defaultBody * factor }
        /// How much control heights, paddings, column widths, the sidebar, switches and symbols grow with the text.
        public var grow: Double { pixelLabels ? labelSize / PixelType.em : max(1, factor) }
    }

    /// How one kind of text is drawn.
    public struct Resolved: Equatable, Sendable {
        public var face: Face
        public var size: Double
        public var weight: Weight
        /// Drawn in capitals. The words themselves are unchanged, and the view gives VoiceOver the title as written.
        public var caps = false
        /// Extra space between letters, in points.
        public var tracking = 0.0
        /// Digits of equal width (Departure Mono's always are).
        public var tabularDigits = false
        public var isPixel: Bool { face == .departure || face == .pixelify }
    }

    // MARK: Sizes

    /// Screen pixels per font pixel for text whose system size is `points`. At the default Text Size it is the nearest
    /// sharp size. Above it, the target is `points` times body over 13, moved UP to the next sharp size, never down.
    public static func multiple(_ points: Double, body: Double, scale: Double) -> Int {
        let pixels = max(1, scale)
        let smallest = Int(pixels.rounded(.up))   // a font pixel is never under one point
        let atDefault = max(smallest, Int((points * pixels / em).rounded()))
        let factor = body > 0 ? body / defaultBody : 1
        guard factor > 1 else { return atDefault }
        return max(atDefault, Int((points * factor * pixels / em - 0.0001).rounded(.up)))
    }

    /// The sharp size in points: 11, 16.5, 22 or 27.5 for labels on a Retina screen, and 11, 22 or 33 at 1x.
    public static func snap(_ points: Double, body: Double, scale: Double) -> Double {
        em * Double(multiple(points, body: body, scale: scale)) / max(1, scale)
    }

    // MARK: Faces

    public static func resolve(_ role: Role, _ c: Conditions) -> Resolved {
        let f = c.factor
        func system(_ points: Double, _ weight: Weight) -> Resolved { Resolved(face: .system, size: points * f, weight: weight) }
        func departure(_ points: Double) -> Resolved { Resolved(face: .departure, size: snap(points, body: c.bodySize, scale: c.scale), weight: .regular, tabularDigits: true) }
        /// Labels in the system font, at the weight they were asked for. Under Bold Text macOS makes every system
        /// font bolder itself, so asking for bold as well would thicken them twice.
        func systemLabel(_ points: Double, _ weight: Weight) -> Resolved { system(points, weight) }

        switch role {
        case .screenTitle(let points):
            guard c.pixelTitle else { return system(points, .semibold) }
            return Resolved(face: .pixelify, size: snap(points, body: c.bodySize, scale: c.scale), weight: .bold)
        case .display(let points):
            // Off is the look from before: the display face.
            guard c.on else { return Resolved(face: .lilita, size: points * f, weight: .regular) }
            return resolve(.screenTitle(points), c)
        case .promptSentence:
            guard c.on else { return Resolved(face: .lilita, size: 19 * f, weight: .regular) }
            return system(15, .semibold)
        case .title(let points):
            return c.pixelLabels ? departure(points) : systemLabel(points, .semibold)
        case .heading:
            guard c.pixelLabels else { return systemLabel(defaultBody, .bold) }
            var out = departure(em)
            out.caps = true
            out.tracking = out.size / em   // one font pixel
            return out
        case .label(let weight):
            return c.pixelLabels ? departure(em) : systemLabel(defaultBody, weight)
        case .number:
            guard c.pixelLabels else { var out = systemLabel(defaultBody, .regular); out.tabularDigits = true; return out }
            return departure(em)
        case .body:
            return system(defaultBody, .regular)
        case .mono:
            return Resolved(face: .systemMono, size: defaultBody * f, weight: .regular)
        }
    }

    // MARK: The setting

    /// What the setting starts as: on, unless text is larger than the default, Bold Text is on, or every screen is 1x.
    public static func firstLaunchDefault(bodySize: Double, boldText: Bool, screenScales: [Double]) -> Bool {
        bodySize <= defaultBody + 0.0001 && !boldText && (screenScales.max() ?? 1) >= 2
    }

    /// The saved choice, or nil when none has been made yet.
    public static func saved(_ defaults: UserDefaults = .standard) -> Bool? { defaults.object(forKey: key) as? Bool }

    /// The saved choice. On a first launch it works out the default from this Mac and, with `remember`, saves it, so a
    /// monitor plugged in later doesn't change what the owner has been looking at.
    public static func load(_ defaults: UserDefaults = .standard, bodySize: Double, boldText: Bool, screenScales: [Double], remember: Bool = true) -> Bool {
        if let saved = saved(defaults) { return saved }
        let start = firstLaunchDefault(bodySize: bodySize, boldText: boldText, screenScales: screenScales)
        if remember { defaults.set(start, forKey: key) }
        return start
    }

    public static func save(_ on: Bool, _ defaults: UserDefaults = .standard) { defaults.set(on, forKey: key) }

    // MARK: Signs and arrows

    /// Shortcut signs, arrows, ticks and the small triangles. They are always set in the system font, whether or not a
    /// pixel face has them, so none depends on font fallback (Departure Mono lacks ⇧ ⌃ ✓ and ▾).
    public static let symbols: Set<Character> = ["⌘", "⌥", "⇧", "⌃", "→", "←", "↑", "↓", "✓", "▾", "▸"]

    /// The text cut into runs: `symbol` runs go in the system font, the rest in the label's face.
    public static func runs(_ text: String) -> [(text: String, symbol: Bool)] {
        var out: [(text: String, symbol: Bool)] = []
        for character in text {
            let symbol = symbols.contains(character)
            if let last = out.last, last.symbol == symbol { out[out.count - 1].text.append(character) } else { out.append((String(character), symbol)) }
        }
        return out
    }

    /// The characters of `text` a face can't draw, given what it covers. Spaces and line ends need no glyph.
    public static func missing(in text: String, covered: (Unicode.Scalar) -> Bool) -> [Character] {
        var out: [Character] = []
        for character in text where !character.isWhitespace && !character.unicodeScalars.allSatisfy(covered) && !out.contains(character) { out.append(character) }
        return out
    }

    // MARK: A server's name in the Allow prompt

    /// The sentence cut around the server's name, so the name gets lines of its own. It is a security prompt: the
    /// name is always shown whole on screen, wrapped at its spaces when it is long, and never cut short. Nil when the
    /// name isn't in the sentence. The words before and after lose the space next to the name.
    public static func split(_ sentence: String, around name: String) -> (before: String, after: String)? {
        guard !name.isEmpty, let range = sentence.range(of: name) else { return nil }
        return (sentence[..<range.lowerBound].trimmingCharacters(in: .whitespaces), sentence[range.upperBound...].trimmingCharacters(in: .whitespaces))
    }
}

/// Font files: registering one for this process, and reading what a face can draw from its character map.
public enum FontFiles {
    /// Registers the first candidate that exists and loads, and says whether the face can now be used. A missing or
    /// broken file is a plain no: the caller draws the system font, and no text is lost.
    @discardableResult
    public static func register(_ candidates: [URL], postScriptName: String) -> Bool {
        if isAvailable(postScriptName) { return true }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if isAvailable(postScriptName) { return true }
        }
        return false
    }

    /// True only when asking for the name gives that very face. CoreText answers an unknown name with a stand-in.
    public static func isAvailable(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }

    /// The characters a font file has glyphs for, read from its character map (cmap). Nil when the file isn't a font.
    public static func coverage(of file: URL) -> CharacterSet? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor], let first = descriptors.first else { return nil }
        return CTFontCopyCharacterSet(CTFontCreateWithFontDescriptor(first, 12, nil)) as CharacterSet
    }
}
