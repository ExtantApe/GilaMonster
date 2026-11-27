import Foundation

// The Overview's "Needs you" list (K672, from the 2026-11-16 mockup): what to do next, first. Pure, so the check
// harness can prove which situations show which items. Restart-needed, planned restarts, the allowlist note and
// upgrade banners keep their own callouts above it.

public struct NeedsYouItem: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case noBackup, autoBackupsOff, backupDrive, issues, connection, pluginUpdates, softwareUpdate }
    public enum Tone: Sendable { case warning, info }
    public enum Action: Equatable, Sendable { case backUpNow, turnOnAutoBackups, openBackups, openIssues, openPlugins, openSoftware }

    public var kind: Kind
    public var tone: Tone
    public var title: String
    public var detail: String
    /// nil when the details are already on the Overview (connections have their own card there).
    public var action: Action?
    public var actionTitle: String?
    public var id: String { kind.rawValue }
}

public struct NeedsYouFacts: Equatable, Sendable {
    /// GilaMonster has made at least one backup of this server. Other tools' backups aren't seen (K823).
    public var hasBackup = false
    public var autoBackups = false
    /// One sentence about a backup drive running low, when one is.
    public var driveWarning: String?
    /// Open issues of error severity or worse.
    public var seriousIssues = 0
    /// "Service: summary" for each connection that needs a look or isn't ready.
    public var connectionProblems: [String] = []
    /// Plugin names with an update that fits this server.
    public var pluginUpdates: [String] = []
    /// A newer build of the server software, as words ("build 254").
    public var softwareUpdate: String?
    /// The Lab is a throwaway test server: it has no backups or connections to look after.
    public var isLab = false
    public init() {}
}

public enum NeedsYou {
    /// Most urgent first: losing worlds, then broken things, then updates.
    public static func items(_ f: NeedsYouFacts) -> [NeedsYouItem] {
        var out: [NeedsYouItem] = []
        if !f.isLab {
            if !f.hasBackup {
                out.append(.init(kind: .noBackup, tone: .warning, title: "No GilaMonster backup yet",
                                 detail: "GilaMonster has made no backup of this server, so it has nothing to restore from. It can't see backups other tools make. A backup works while the server runs.",
                                 action: .backUpNow, actionTitle: "Back Up Now"))
            }
            if !f.autoBackups {
                out.append(.init(kind: .autoBackupsOff, tone: .warning, title: "Automatic backups are off",
                                 detail: "Turn them on and GilaMonster backs up after people play.",
                                 action: .turnOnAutoBackups, actionTitle: "Turn On"))
            }
            if let w = f.driveWarning {
                out.append(.init(kind: .backupDrive, tone: .warning, title: "A backup drive is running low", detail: w,
                                 action: .openBackups, actionTitle: "Open Backups"))
            }
        }
        if f.seriousIssues > 0 {
            out.append(.init(kind: .issues, tone: .warning, title: f.seriousIssues == 1 ? "1 issue needs attention" : "\(f.seriousIssues) issues need attention",
                             detail: "The server logged errors that may stop players or lose changes.",
                             action: .openIssues, actionTitle: "Review"))
        }
        if !f.isLab, !f.connectionProblems.isEmpty {
            out.append(.init(kind: .connection, tone: .warning, title: "Friends may not be able to connect",
                             detail: f.connectionProblems.prefix(2).joined(separator: " ") + (f.connectionProblems.count > 2 ? " And \(f.connectionProblems.count - 2) more." : "") + " Details are in Connections below.",
                             action: nil, actionTitle: nil))
        }
        if !f.pluginUpdates.isEmpty {
            let n = f.pluginUpdates.count
            let names = f.pluginUpdates.prefix(2).joined(separator: " and ") + (n > 2 ? " and \(n - 2) more" : "")
            out.append(.init(kind: .pluginUpdates, tone: .info, title: n == 1 ? "1 plugin update" : "\(n) plugin updates",
                             detail: "\(names) \(n == 1 ? "has an update that fits" : "have updates that fit") this Minecraft version.",
                             action: .openPlugins, actionTitle: "Review"))
        }
        if let s = f.softwareUpdate {
            out.append(.init(kind: .softwareUpdate, tone: .info, title: "Server software update",
                             detail: "A newer \(s) is available.", action: .openSoftware, actionTitle: "Open Software"))
        }
        return out
    }

    /// The one-line status under the server's name: state first, then what matters most.
    public static func statusLine(running: Bool, starting: Bool, since: Date?, players: Int, software: String,
                                  lastBackup: Date?, isLab: Bool, now: Date = Date()) -> String {
        var parts: [String] = []
        if starting {
            parts.append("Starting.")
        } else if running {
            if let since {
                let f = DateComponentsFormatter()
                f.unitsStyle = .full; f.maximumUnitCount = 1; f.allowedUnits = [.day, .hour, .minute]
                let span = max(60, now.timeIntervalSince(since))
                parts.append("Running for \(f.string(from: span) ?? "a while").")
            } else {
                parts.append("Running.")
            }
            parts.append(players == 0 ? "Nobody on." : players == 1 ? "1 player on." : "\(players) players on.")
        } else {
            parts.append("Stopped.")
            parts.append("\(software).")
        }
        if !isLab {
            if let lastBackup {
                let rel = RelativeDateTimeFormatter()
                rel.unitsStyle = .full
                parts.append("Last GilaMonster backup \(rel.localizedString(for: lastBackup, relativeTo: now)).")
            } else {
                parts.append("No GilaMonster backup yet.")
            }
        }
        return parts.joined(separator: " ")
    }

    /// The Overview's status sentence (K786), set large beside the state's glyph: "Riverside is up. 3 players online."
    public static func sentence(name: String, state: ServerState, players: Int) -> String {
        switch state {
        case .running: return "\(name) is up. " + (players == 0 ? "Nobody is online." : players == 1 ? "1 player online." : "\(players) players online.")
        case .starting: return "\(name) is starting."
        case .stopping: return "\(name) is stopping."
        case .stopped: return "\(name) is stopped."
        case .crashed: return "\(name) is down. It stopped unexpectedly."
        case .external: return "\(name) is running outside GilaMonster."
        }
    }

    /// The one muted line under the sentence: "Paper 26.2 · up for 2 hours · GilaMonster backup 25 minutes ago · nothing needs you".
    /// The backup age is GilaMonster's own newest backup, and says so: other tools' backups aren't seen (K823).
    public static func factLine(software: String, running: Bool, since: Date?, lastBackup: Date?, isLab: Bool,
                                needs: Int, openIssues: Int, now: Date = Date()) -> String {
        var parts = [software]
        if running, let since {
            let f = DateComponentsFormatter()
            f.unitsStyle = .full; f.maximumUnitCount = 1; f.allowedUnits = [.day, .hour, .minute]
            parts.append("up for \(f.string(from: max(60, now.timeIntervalSince(since))) ?? "a while")")
        }
        if !isLab {
            if let lastBackup {
                let rel = RelativeDateTimeFormatter()
                rel.unitsStyle = .full
                parts.append("GilaMonster backup \(rel.localizedString(for: lastBackup, relativeTo: now))")
            } else {
                parts.append("no GilaMonster backup yet")
            }
        }
        parts.append(needs == 0 ? "nothing needs you" : needs == 1 ? "1 thing needs you" : "\(needs) things need you")
        if openIssues > 0 { parts.append(openIssues == 1 ? "1 open issue" : "\(openIssues) open issues") }
        return parts.joined(separator: " · ")
    }
}
