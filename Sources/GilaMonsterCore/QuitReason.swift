import Foundation

/// Why the app is being asked to quit (K650, 2026-11-14). At a shutdown, restart or log out nobody is there to answer
/// a question, so GilaMonster stops its servers with a save and lets the Mac carry on instead of asking.
public enum QuitReason: Equatable, Sendable {
    case user, shutdown, restart, logout

    /// From the reason macOS puts on its quit request: 'shut', 'rest', 'rlgo' or 'logo'. Anything else is a person.
    public init(code: UInt32?) {
        switch code {
        case Self.code("shut"): self = .shutdown
        case Self.code("rest"): self = .restart
        case Self.code("rlgo"), Self.code("logo"): self = .logout
        default: self = .user
        }
    }

    public static func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    /// True when the Mac itself is quitting the app, so there's nobody to answer a question.
    public var unattended: Bool { self != .user }

    public var words: String {
        switch self {
        case .user: "GilaMonster was asked to quit"
        case .shutdown: "The Mac is shutting down"
        case .restart: "The Mac is restarting"
        case .logout: "You're logging out"
        }
    }
}
