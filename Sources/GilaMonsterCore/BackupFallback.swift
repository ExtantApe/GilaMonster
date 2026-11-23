import Foundation

/// Backups that go to one drive only. While that drive is missing, each backup is skipped and reported, and nothing is
/// written anywhere else. The owner, 2026-11-21 (D250, replacing the 2026-11-16 rule that fell back to the Mac's disk
/// after 24 hours): every Minecraft backup goes to MCBackups, "and not WDSSD or the internal Mac drive". If the drive
/// is missing or full, the backup fails closed and says so.
public struct BackupFallback: Codable, Equatable, Sendable {
    /// Where the earlier rule put backups while the drive was missing. Nothing new is written here. It's kept so backups
    /// made under that rule stay listed until they're moved to the drive or deleted.
    public var path: String
    public init(path: String) { self.path = path }

    public enum Decision: Equatable, Sendable {
        /// The drive is there: back up to it, as usual.
        case drive
        /// Skip this backup and say why. Nothing is written anywhere.
        case skip(String)
    }

    /// What to do about a backup now: the drive if it's connected, otherwise skip.
    public func decide(connected: Bool, missingSince: Date?, now: Date, driveName: String) -> Decision {
        if connected { return .drive }
        let since = missingSince ?? now
        return .skip("\(driveName) isn't connected (missing since \(Self.when(since))). Nothing was written to any other drive or to the Mac's own disk. Plug it in and the next backup goes to it.")
    }

    static func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

/// Is an external drive plugged in? A path under `/Volumes/<name>` is on that drive only while it's mounted there.
/// Anything else is on the Mac's own disk and counts as connected.
public enum DriveCheck {
    /// For checks: stands in for "is the drive holding this path mounted?". Never set by the app.
    nonisolated(unsafe) public static var standIn: ((URL) -> Bool)?

    /// `/Volumes/<name>` for a path on an external drive, or nil for a path on the Mac's own disk.
    public static func volumeRoot(_ url: URL) -> URL? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[0] == "/", parts[1] == "Volumes" else { return nil }
        let root = URL(fileURLWithPath: "/Volumes/" + parts[2], isDirectory: true)
        // The Mac's own disk is linked in /Volumes too. A link is never a drive's mount point.
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: root.path)) != nil { return nil }
        return root
    }

    public static func isConnected(_ url: URL) -> Bool {
        if let standIn { return standIn(url) }
        guard let root = volumeRoot(url) else { return true }
        var info = statfs()
        guard statfs(root.path, &info) == 0 else { return false }
        let mountedOn = withUnsafeBytes(of: &info.f_mntonname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        // A folder left in /Volumes after a drive was pulled sits on the Mac's own disk, mounted on "/".
        return mountedOn == root.path
    }

    /// The drive's name as the person sees it, for messages.
    public static func name(_ url: URL) -> String {
        volumeRoot(url)?.lastPathComponent ?? "The Mac's own disk"
    }
}
