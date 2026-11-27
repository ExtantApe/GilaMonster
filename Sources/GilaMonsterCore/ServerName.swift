import Foundation

/// The name GilaMonster shows for a server (K824; owner, 2026-11-26: "MOTD, editable"): the owner's own name for it
/// when there is one, then the server message players see in their server list, then the folder's name.
public enum ServerName {
    /// A server message longer than this is a sentence, so the folder name is shown.
    public static let longest = 40
    /// What Minecraft and Paper write into a new server.properties. It names nothing.
    public static let defaultMessage = "A Minecraft Server"

    /// The server message as a name: its first line, without colour and format codes, or nil when that leaves
    /// nothing usable (empty, only codes, too long, or the default). `motd` is the value as Minecraft reads it,
    /// with the file's `\n` and `\u00A7` escapes already turned into characters.
    public static func fromMessage(_ motd: String) -> String? {
        let firstLine = motd.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var plain = withoutCodes(firstLine)
        // Messages are often padded with spaces to centre them in the server list.
        plain = plain.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty, plain.count <= longest, plain.caseInsensitiveCompare(defaultMessage) != .orderedSame else { return nil }
        return plain
    }

    /// Text without Minecraft's colour and format codes. A hex colour is §x followed by six §-digits. Then § and
    /// whatever one character follows it, and a § left alone at the end of a line. The & forms are the ones the
    /// Configs page has always treated as codes.
    public static func withoutCodes(_ text: String) -> String {
        var plain = text
        for pattern in ["§[xX](§[0-9a-fA-F]){6}", "§.", "§", "&[0-9a-fk-orA-FK-OR]"] {
            plain = plain.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return plain
    }

    /// The `motd` value from the text of a properties file, unescaped the way Minecraft does it, or nil when the
    /// key isn't there. Every other line is skipped unread: the file also holds passwords and secrets.
    public static func message(inProperties text: String) -> String? {
        var found: String?
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).makeIterator()
        while let line = lines.next() {
            let start = line.drop { $0 == " " || $0 == "\t" }
            guard start.hasPrefix("motd") else { continue }
            let rest = start.dropFirst(4).drop { $0 == " " || $0 == "\t" }
            guard let separator = rest.first, separator == "=" || separator == ":" else { continue }
            var raw = String(rest.dropFirst().drop { $0 == " " || $0 == "\t" })
            // A line ending in an odd number of backslashes carries on over the next line.
            while raw.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1, let next = lines.next() {
                raw = String(raw.dropLast()) + next.drop { $0 == " " || $0 == "\t" }
            }
            // The last one wins, as it does when Java loads the file.
            found = PropertiesDocument.unescape(raw)
        }
        return found
    }

    /// The usable name in a server's own server.properties, read from disk. Only the motd value is kept; the rest
    /// of the file is dropped as soon as it has been scanned, and nothing from it is logged.
    public static func fromServerMessage(properties: URL) -> String? {
        guard let text = try? String(contentsOf: properties, encoding: .utf8) else { return nil }
        return message(inProperties: text).flatMap(fromMessage)
    }

    /// The owner's name, then the server message, then the folder.
    public static func resolve(custom: String?, message: String?, folder: String) -> String {
        if let custom = custom?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty { return custom }
        if let message, !message.isEmpty { return message }
        return folder
    }

    /// The small line under the headline that keeps the folder findable. Nil when the headline already says it.
    public static func folderLine(display: String, folder: String) -> String? {
        display == folder ? nil : "Folder: \(folder)"
    }

    /// The same, for the window's subtitle beside the software.
    public static func subtitle(software: String, display: String, folder: String) -> String {
        display == folder ? software : "\(folder) · \(software)"
    }

    /// About how many letters fit on one line under the server's icon in the sidebar, at the body size.
    public static let sidebarLine = 10

    /// The name under the server's icon: at most two lines, broken between words. A name that fits is shown whole.
    /// One that doesn't keeps the whole words that fit and ends in an ellipsis, and a single word too long for a
    /// line is cut once, at its end. `reserve` is room kept on the last line for the menu arrow. The full name is
    /// in the tooltip and the VoiceOver label, see `switcherSpoken`.
    public static func sidebarLines(_ name: String, perLine: Int = sidebarLine, reserve: Int = 2) -> [String] {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return [] }
        let lastLine = perLine - reserve
        let whole = words.joined(separator: " ")
        if whole.count <= lastLine { return [whole] }
        // As many whole words as a line holds.
        func take(_ words: ArraySlice<String>, room: Int) -> (text: String, rest: ArraySlice<String>) {
            var text = "", rest = words
            while let word = rest.first, (text.isEmpty ? word.count : text.count + 1 + word.count) <= room {
                text = text.isEmpty ? word : text + " " + word
                rest = rest.dropFirst()
            }
            return (text, rest)
        }
        let top = take(words[...], room: perLine)
        // A first word too long for a line: cut it once, at its end.
        guard !top.text.isEmpty else { return [String(first.prefix(lastLine - 1)) + "…"] }
        let bottom = take(top.rest, room: lastLine)
        if bottom.rest.isEmpty { return bottom.text.isEmpty ? [top.text] : [top.text, bottom.text] }
        // Too long for two lines: the whole words that fit, with an ellipsis after the last of them.
        let shorter = take(top.rest, room: lastLine - 1)
        if !shorter.text.isEmpty { return [top.text, shorter.text + "…"] }
        let alone = take(words[...], room: lastLine - 1)
        return [alone.text.isEmpty ? String(first.prefix(lastLine - 1)) + "…" : alone.text + "…"]
    }

    /// One row of the server switcher as VoiceOver reads it: "Made-up Realms, folder survival, Running".
    public static func switcherSpoken(display: String, folder: String, state: String, lab: Bool = false) -> String {
        "\(display), folder \(folder)\(lab ? ", the Lab's server for this run" : ""), \(state)"
    }

    /// The switcher button itself, for its tooltip and VoiceOver: always the whole name, however the label is cut.
    public static func switcherButtonSpoken(display: String, folder: String, state: String) -> String {
        display == folder ? "Server: \(display), \(state). Switch server." : "Server: \(display), folder \(folder), \(state). Switch server."
    }
}

/// The line in the rename sheet that says where the name comes from. Shown, and read by VoiceOver.
public enum RenameWording {
    public static func status(following: Bool, automatic: String, messageUsable: Bool) -> String {
        guard following else { return "This is your own name for the server. Reset to Server Message goes back to \(automatic)." }
        return messageUsable
            ? "The name follows the server message, which reads \(automatic)."
            : "The server message is empty, a default or too long for a name, so the folder's name, \(automatic), is shown."
    }
}
