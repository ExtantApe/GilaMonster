import Foundation

/// Backups that go to one drive only, with the Mac's own disk as a late fallback. The owner, 2026-11-16: "only do
/// minecraft backups to that ssd unless its unavailable for a period of time, like 24h, then try to backup to machine
/// if above 75gb", then "75 GB left after the backup".
public struct BackupFallback: Codable, Equatable, Sendable {
    /// The folder fallback backups go in. Each server gets a folder of its own inside it, claimed like a storage target.
    public var path: String
    /// How long the drive must have been missing, without a break, before the fallback is used.
    public var afterHours = 24
    /// What must still be free on the fallback disk after the backup.
    public var keepFreeGB = 75
    public init(path: String) { self.path = path }

    public enum Decision: Equatable, Sendable {
        /// The drive is there: back up to it, as usual.
        case drive
        /// Skip this backup and say why. Nothing is written anywhere.
        case skip(String)
        /// Back up to the fallback folder.
        case fallback
    }

    /// What to do about a backup now. `needed` is the next backup's likely size (the last one of its kind and a margin).
    /// Unknown free space is a skip: a fallback runs only when it's known to leave enough.
    public func decide(connected: Bool, missingSince: Date?, now: Date, free: Int64?, needed: Int64, driveName: String) -> Decision {
        if connected { return .drive }
        let since = missingSince ?? now
        let away = now.timeIntervalSince(since)
        let wait = TimeInterval(max(afterHours, 1)) * 3600
        if away < wait {
            let left = Self.span(wait - away)
            return .skip("\(driveName) isn't connected (missing since \(Self.when(since))). Nothing was written to the Mac's own disk. If it's still missing in \(left), backups go to the Mac's disk instead, while \(keepFreeGB) GB stays free.")
        }
        let keep = Int64(keepFreeGB) << 30
        guard let free else {
            return .skip("\(driveName) has been missing since \(Self.when(since)), and LeafJuice couldn't tell how much room the Mac's disk has, so nothing was written.")
        }
        if free - needed < keep {
            return .skip("\(driveName) has been missing since \(Self.when(since)). The Mac's disk has \(Format.bytes(free)) free, and this backup may need \(Format.bytes(needed)), which would leave less than \(keepFreeGB) GB. Nothing was written.")
        }
        return .fallback
    }

    /// "about 5 hours", "40 minutes": rounded up, so the fallback is never sooner than said.
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let hours = Int((seconds / 3600).rounded(.up))
        return hours == 1 ? "about 1 hour" : "about \(hours) hours"
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
