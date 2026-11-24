import Foundation

/// The size of text in the console and the file editors, which people with low vision need to change without changing
/// the whole system's size. Command-plus and Command-minus step it; Command-0 isn't taken, so the button resets it.
public enum TextZoom {
    public static let key = "textZoomSize"
    public static let standard = 12.0
    public static let range = 9.0...32.0
    public static let step = 1.0

    public static func clamped(_ size: Double) -> Double { min(range.upperBound, max(range.lowerBound, size)) }
    public static func larger(_ size: Double) -> Double { clamped(size + step) }
    public static func smaller(_ size: Double) -> Double { clamped(size - step) }
}

extension ConsoleLine {
    /// Lines the owner typed or the app wrote start with words, so the difference doesn't rest on color. The app's own
    /// lines already begin with "[GilaMonster]". A typed command is stored with a leading "> ", which becomes a word.
    public var displayText: String {
        switch origin {
        case .command:
            let bare = text.hasPrefix(">\u{00A0}") ? String(text.dropFirst(2)) : text
            return "Command: " + bare
        case .wrapper:
            return text.hasPrefix("[GilaMonster]") ? text : "[GilaMonster] " + text
        case .server:
            return text
        }
    }
}
