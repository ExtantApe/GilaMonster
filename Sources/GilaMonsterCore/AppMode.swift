import Foundation

/// The kind of run this is, read in one place (K829).
///
/// With `GILAMONSTER_SNAPSHOT=<folder>` set, a debug build draws its pages off screen and quits. A snapshot run starts
/// nothing by itself: no ticker, so no scheduled backup, restart, update check or backup drill; no server, test copy,
/// drill or Lab run; no web page or pack host; and no launch-time look for a new GilaMonster. Anything that runs on a
/// timer, on a schedule or at launch asks `AppMode.isSnapshot` first, and `gilamonster-check` reads the source to make
/// sure a new timer can't forget to.
public enum AppMode {
    public static let snapshotVariable = "GILAMONSTER_SNAPSHOT"
    /// Where a snapshot run puts its pictures, or nil in an ordinary run.
    public static var snapshotFolder: String? { ProcessInfo.processInfo.environment[snapshotVariable] }
    public static var isSnapshot: Bool { snapshotFolder != nil }
    /// What a refused start says, for a log line or an error.
    public static let snapshotRefusal = "This is a snapshot run, which only draws pages, so nothing was started."
}
