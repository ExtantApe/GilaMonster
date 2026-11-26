import Foundation

/// Who or what asked a server to stop (K798). Every way GilaMonster stops a server names itself with one of these, so
/// a stop in the night can be traced afterwards. On 2026-11-26 a server stopped at 00:02 and nothing said what asked.
public enum StopSource: Equatable, Sendable {
    /// A Stop or Restart button in a window, with where it is: "Overview", "toolbar", "Changes".
    case button(String)
    /// The Server menu, picked with the pointer.
    case menu
    /// The GilaMonster item in the menu bar.
    case menuBar
    /// The Server menu's keyboard shortcut.
    case keyboardShortcut
    /// An assistant session, by the name it gave itself.
    case session(caller: String)
    /// The owner quit GilaMonster and chose to stop the servers.
    case quit
    /// The Mac is shutting down or restarting, or the owner is logging out.
    case mac(QuitReason)
    /// A signal told GilaMonster to quit.
    case signal(String)
    case lab
    /// "stop" typed in GilaMonster's console.
    case console
    case forceStop
    /// GilaMonster itself, with what for: "to restore a backup".
    case app(String)
    /// GilaMonster didn't ask.
    case outside

    /// The Server menu's Stop and Restart have shortcuts, and both arrive the same way. A key press was the shortcut.
    public static func menu(keyPress: Bool) -> StopSource { keyPress ? .keyboardShortcut : .menu }

    /// A short fixed name for the file, the same whatever the wording becomes.
    public var key: String {
        switch self {
        case .button: "button"
        case .menu: "menu"
        case .menuBar: "menu-bar"
        case .keyboardShortcut: "keyboard-shortcut"
        case .session: "session"
        case .quit: "quit"
        case .mac(let reason):
            switch reason {
            case .shutdown: "mac-shutdown"
            case .restart: "mac-restart"
            case .logout: "logout"
            case .user: "quit"
            }
        case .signal: "quit-signal"
        case .lab: "lab"
        case .console: "console"
        case .forceStop: "force-stop"
        case .app: "gilamonster"
        case .outside: "outside"
        }
    }

    /// In words, to follow "from": "the Stop button (Overview)", "a session (helper)".
    public func words(restart: Bool = false) -> String {
        let verb = restart ? "Restart" : "Stop"
        switch self {
        case .button(let place): return "the \(verb) button (\(StopLog.clip(place)))"
        case .menu: return "\(verb) in the Server menu"
        case .menuBar: return "\(verb) in the menu bar"
        case .keyboardShortcut: return "the \(verb) keyboard shortcut"
        case .session(let caller): return "a session (\(StopLog.clip(caller)))"
        case .quit: return "quitting GilaMonster"
        case .mac(let reason):
            switch reason {
            case .shutdown: return "the Mac shutting down"
            case .restart: return "the Mac restarting"
            case .logout: return "logging out of the Mac"
            case .user: return "quitting GilaMonster"
            }
        case .signal(let name): return "a quit signal sent to GilaMonster (\(StopLog.clip(name)))"
        case .lab: return "the Lab"
        case .console: return "stop typed in the console"
        case .forceStop: return "Force Stop"
        case .app(let what): return "GilaMonster, \(StopLog.clip(what))"
        case .outside: return StopLog.outsideWords
        }
    }

    /// The session's own name, when a session asked.
    public var caller: String? { if case .session(let caller) = self { StopLog.clip(caller) } else { nil } }
}

/// One line of a server's stop file: a stop being asked for, or the server's exit.
public struct StopRecord: Codable, Equatable, Sendable {
    public enum Event: String, Codable, Sendable { case asked, exited }
    public enum Outcome: String, Codable, Sendable {
        case stopped, crashed
        /// The server quit before it finished starting.
        case gaveUp = "gave-up-starting"
        /// A server GilaMonster didn't start was asked to stop, and is no longer running. Its exit code can't be read.
        case gone
        /// A server GilaMonster didn't start was asked to stop, and was still running a minute later.
        case stillRunning = "still-running"
    }
    public var date: Date
    public var event: Event
    /// StopSource.key.
    public var source: String
    /// StopSource.words: what asked, in words.
    public var by: String
    /// The session's own name, when a session asked.
    public var caller: String?
    /// True when the stop was the first half of a restart.
    public var restart: Bool
    /// When the stop this exit answers was asked for. Nil when GilaMonster didn't ask.
    public var asked: Date?
    /// The Java process's exit code. Nil for an ask, and for a server GilaMonster didn't start.
    public var code: Int32?
    public var outcome: Outcome?
    /// The server logged its own shutdown ("Stopping server") before it exited.
    public var ownShutdown: Bool?
    /// The server's log had a crash in it.
    public var crashInLog: Bool?
    /// Anything more: "Java was asked to shut down after 2 minutes".
    public var note: String?

    public static func asked(_ source: StopSource, restart: Bool, note: String? = nil, date: Date = Date()) -> StopRecord {
        StopRecord(date: date, event: .asked, source: source.key, by: source.words(restart: restart), caller: source.caller, restart: restart,
                   note: note.map { StopLog.clip($0) })
    }

    /// The exit, carrying what asked for it. `ask` is nil when GilaMonster didn't ask.
    public static func exited(code: Int32?, outcome: Outcome, ask: StopRecord?, ownShutdown: Bool? = nil, crashInLog: Bool? = nil, note: String? = nil, date: Date = Date()) -> StopRecord {
        StopRecord(date: date, event: .exited, source: ask?.source ?? StopSource.outside.key, by: ask?.by ?? StopSource.outside.words(), caller: ask?.caller,
                   restart: ask?.restart ?? false, asked: ask?.date, code: code, outcome: outcome, ownShutdown: ownShutdown, crashInLog: crashInLog,
                   note: note.map { StopLog.clip($0) })
    }
}

/// A lasting record of each server's stops, in `.gilamonster/stops.jsonl` inside the server's folder: one line when a
/// stop is asked for, and one when the server exits. It holds times, what asked and the exit code. It never holds a
/// player's name, chat or an address: a stop typed in the game by a player is recorded only as coming from outside.
public enum StopLog {
    public static let fileName = "stops.jsonl"
    /// The file is cut back to its newest `keep` lines once it passes `maxBytes`.
    public static let maxBytes = 256 * 1024
    public static let keep = 400
    /// The longest a name or note may be in a line, so one line can't fill the file.
    public static let maxField = 120
    public static let outsideWords = "the server stopped on its own or from outside"

    public static func file(_ paths: ServerPaths) -> URL { paths.meta.appendingPathComponent(fileName) }

    static func clip(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > maxField ? String(flat.prefix(maxField - 1)) + "…" : flat
    }

    /// Adds a line, and trims the file when it has grown past its cap. Returns false if nothing could be written.
    @discardableResult
    public static func append(_ record: StopRecord, to url: URL) -> Bool {
        guard var row = try? JSONStore.compactEncoder.encode(record) else { return false }
        row.append(0x0A)
        do {
            try FileOps.ensureDir(url.deletingLastPathComponent())
            if !FileOps.exists(url) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: row)
        } catch { return false }
        trim(url)
        return true
    }

    /// Cuts the file back to its newest lines when it's over the cap. A line too long to be one of ours is dropped.
    static func trim(_ url: URL) {
        guard FileOps.size(url) > Int64(maxBytes), let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(whereSeparator: \.isNewline).filter { $0.utf8.count <= 4096 }.suffix(keep)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    public static func read(_ url: URL) -> [StopRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONStore.decoder
        return text.split(whereSeparator: \.isNewline).compactMap { try? decoder.decode(StopRecord.self, from: Data($0.utf8)) }
    }

    /// The last stop: the newest line. That's an exit, or an ask whose exit GilaMonster never saw (it quit first).
    public static func last(_ records: [StopRecord]) -> StopRecord? { records.last }

    /// The last stop in a sentence or two, for the Overview.
    public static func sentence(_ record: StopRecord, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = timeZone
        format.dateStyle = .medium
        format.timeStyle = .short
        let when = format.string(from: record.date)
        let verb = record.restart ? "Last restart" : "Last stop"
        guard record.event == .exited else {
            return "\(verb): asked for on \(when), from \(record.by). GilaMonster didn't see the server exit."
        }
        let asked = record.source != StopSource.outside.key
        var exit: String
        switch record.outcome {
        case .crashed: exit = "The server crashed" + (record.code.map { ", exit code \($0)." } ?? ".")
        case .gaveUp: exit = "The server gave up while starting" + (record.code.map { ", exit code \($0)." } ?? ".")
        case .gone: exit = "It was a server GilaMonster hadn't started, so there's no exit code."
        case .stillRunning: exit = "It was a server GilaMonster hadn't started, and it was still running a minute later."
        case .stopped, nil: exit = record.code.map { "Exit code \($0)" + (record.ownShutdown == true && !asked ? ", after the server's own shutdown." : ".") } ?? ""
        }
        if let note = record.note { exit += exit.isEmpty ? "\(note)." : " \(note)." }
        if asked { return "\(verb): \(when), from \(record.by). \(exit)".trimmingCharacters(in: .whitespaces) }
        // "The server stopped on its own or from outside" covers a crash as well, and the exit says which it was.
        let first = outsideWords.prefix(1).uppercased() + outsideWords.dropFirst()
        return "\(verb): \(when). \(first). GilaMonster didn't ask. \(exit)".trimmingCharacters(in: .whitespaces)
    }
}
