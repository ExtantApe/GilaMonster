import Foundation

// Allow for today (owner, 2026-11-23: "Same action, same server (Recommended)", then "It should work for all
// servers", K721).
//
// Next to Allow, a session's ask offers Allow for today. One click lets that kind of action go ahead on every server
// without asking again until local midnight. A stop allowed once covers starts, stops and restarts on every server
// today, and no other kind of action. Removals (a pack address taken away), naming a player, and anything that
// deletes, restores or resets a world are never covered: an action has to be listed in `todayFamily` to be covered,
// so one added later asks every time until someone decides otherwise.
//
// Each action that goes ahead this way still shows a notice, goes in the record, and first checks that nobody is
// online. With someone online it asks as usual; when LeafJuice can't tell, it refuses.
//
// Grants live only in the running app's memory. Nothing writes them to disk, no session call makes or extends one,
// and only the owner's click on a waiting ask adds one. Quitting LeafJuice clears them, and the menu bar item
// revokes them all at once.

/// Actions one Allow for today covers together.
public enum GrantFamily: String, Sendable, CaseIterable {
    case power, serving, publish, handoff, address

    /// For the notice and the menu: "starting, stopping and restarting servers".
    public var words: String {
        switch self {
        case .power: "starting, stopping and restarting servers"
        case .serving: "starting and stopping pack serving"
        case .publish: "publishing pack builds"
        case .handoff: "marking Packmule updated"
        case .address: "giving pack addresses"
        }
    }
}

extension SessionAction {
    /// The family an Allow for today covers, or nil when it never does. Listed one by one on purpose.
    public var todayFamily: GrantFamily? {
        switch self {
        case .start, .stop, .restart: .power
        case .hostingStart, .hostingStop: .serving
        case .publish: .publish
        case .handoff: .handoff
        case .hostingAdd: .address
        default: nil
        }
    }
}

/// Today's grants, in memory only.
public struct TodayGrants: Sendable, Equatable {
    public struct Grant: Sendable, Equatable {
        public let family: GrantFamily
        public let granted: Date
        public let until: Date
    }

    public private(set) var grants: [GrantFamily: Grant] = [:]
    public init() {}

    /// The next local midnight after `now`.
    public static func midnight(after now: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Adds or renews a grant. It always ends at the midnight after `now`, so a second click the same day ends at the
    /// same moment and never later.
    mutating func add(_ family: GrantFamily, now: Date, calendar: Calendar) -> Grant {
        let g = Grant(family: family, granted: grants[family]?.granted ?? now, until: Self.midnight(after: now, calendar: calendar))
        grants[family] = g
        return g
    }

    public func covers(_ family: GrantFamily, now: Date) -> Bool {
        guard let g = grants[family] else { return false }
        return now < g.until
    }

    public func active(now: Date) -> [Grant] {
        grants.values.filter { now < $0.until }.sorted { $0.family.rawValue < $1.family.rawValue }
    }

    public mutating func revokeAll() { grants.removeAll() }
}

/// Whether anyone is on a server, for an action allowed for today.
public enum Online: Equatable, Sendable {
    case nobody
    case someone(Int)
    case unsure(String)

    /// The rule. A server that isn't running has nobody on it. A running one is read from the management server when
    /// it's connected (no answer means unsure) or from the console, which sees every join while LeafJuice runs it.
    /// Starting, stopping and a server run outside LeafJuice can't be told.
    public static func decide(state: ServerState, management: Bool, managementPlayers: Int?, consolePlayers: Int) -> Online {
        switch state {
        case .stopped, .crashed: return .nobody
        case .running:
            if management {
                guard let n = managementPlayers else { return .unsure("the management server didn't answer") }
                return n == 0 ? .nobody : .someone(n)
            }
            return consolePlayers == 0 ? .nobody : .someone(consolePlayers)
        case .starting: return .unsure("it's starting")
        case .stopping: return .unsure("it's stopping")
        case .external: return .unsure("it's running outside LeafJuice")
        }
    }
}

extension ServerController {
    /// Asks the management server when it's connected, so the answer is from now and not from the last event.
    public func whoIsOnline() async -> Online {
        let state = state
        let link = management
        var count: Int?
        if state == .running, let link {
            count = ManagementText.players(await link.call("minecraft:players", timeout: .seconds(3)))?.count
        }
        return Online.decide(state: self.state == state ? state : .starting, management: link != nil, managementPlayers: count, consolePlayers: players.count)
    }
}
