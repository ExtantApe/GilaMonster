import Foundation

/// Tells a server that shut itself down cleanly from one that crashed, from its own log lines (K692).
///
/// A stop typed in the game or console, `stop` sent by another tool, or a SIGTERM from outside all make the server run
/// its own shutdown: it logs "Stopping server" and saves. A SIGTERM exits with code 143, which on its own reads as a
/// crash, and LeafJuice used to restart the server 10 seconds later. Now a shutdown the server ran itself, with no crash
/// in the log, counts as a stop made outside LeafJuice and isn't restarted. A crash or a freeze also ends in "Stopping
/// server", so any crash marker wins.
public enum ShutdownSignals {
    public enum Kind: Equatable, Sendable { case shutdown, crash }

    private static let crashMarkers = [
        "Encountered an unexpected exception",
        "Exception in server tick loop",
        "The server has stopped responding",
        "This crash report has been saved to",
        "Considering it to be crashed",
        "A single server tick took",
    ]

    /// What a non-chat log message says about how the server is ending, if anything.
    public static func kind(of message: String) -> Kind? {
        let m = message.trimmingCharacters(in: .whitespaces)
        if crashMarkers.contains(where: { m.contains($0) }) { return .crash }
        if m == "Stopping server" || m == "Stopping the server" { return .shutdown }
        return nil
    }

    /// True when the server ran its own shutdown and nothing in the log says it crashed.
    public static func stoppedItself(sawShutdown: Bool, sawCrash: Bool) -> Bool { sawShutdown && !sawCrash }
}
