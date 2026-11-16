import Foundation

// Backup caps (owner, 2026-11-15, D213): "Probably good for Leaf Juice to keep track of backup folder size so that it
// can dynamically compensate. We need to set an upper limit on the amount it can store because that drive is shared."
// Cap for WDSSD: "150 GB (Recommended)".
//
// The rules, each covered in leafjuice-check:
// - A cap belongs to a drive, not a server, and is set on the Backups page. Every server's LeafJuice backups on that
//   drive count towards it, and so does a backup still being written (its .partial) or copied (.part).
// - Before a backup that would go over, the server's own oldest backups on that drive go first, the ones its keeping
//   tiers (D186) would drop anyway before the rest. Never a pinned one, never the server's newest or very first
//   (the tiers keep that one too), never the newest on that drive, and never another server's.
// - If that can't make room, the backup goes to the next storage in order, or is skipped and the owner is told. It
//   never fills the drive past the cap.
// - At 85% of the cap the Backups page and an issue say so, before anything is removed.
// - While a backup is written, a watch stops it and removes the partial file if the drive's backups pass the cap.

/// One drive's cap. Kept per drive (by volume UUID), so every server writing to that drive shares it.
public struct DriveCap: Codable, Equatable, Sendable {
    public var name: String
    public var bytes: Int64
    public init(name: String, bytes: Int64) { self.name = name; self.bytes = bytes }
}

public enum BackupCaps {
    /// Warn once a drive's backups reach this share of its cap.
    public static let warnShare = 0.85
    /// Room left for a new backup beyond the last one's size, since worlds grow.
    public static let growth = 1.2

    // MARK: Which drive

    /// A drive's identity: its volume UUID when macOS gives one, otherwise the volume's mount path.
    public static func driveID(for url: URL) -> (id: String, name: String)? {
        var probe = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        guard let v = try? probe.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey, .volumeURLKey]) else { return nil }
        let name = v.volumeName ?? probe.lastPathComponent
        if let uuid = v.volumeUUIDString { return (uuid, name) }
        if let root = v.volume { return ("path:" + root.path, name) }
        return nil
    }

    // MARK: Settings

    static var file: URL { AppPaths.home.appendingPathComponent("backup-caps.json") }

    public static func all() -> [String: DriveCap] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONStore.decoder.decode([String: DriveCap].self, from: data)) ?? [:]
    }

    public static func cap(for url: URL) -> DriveCap? {
        guard let drive = driveID(for: url) else { return nil }
        return all()[drive.id]
    }

    /// Sets or clears (nil) the cap for the drive holding `url`.
    public static func set(_ bytes: Int64?, for url: URL) throws {
        guard let drive = driveID(for: url) else { throw LeafError("LeafJuice can't tell which drive \(url.path) is on.") }
        var caps = all()
        if let bytes, bytes > 0 { caps[drive.id] = DriveCap(name: drive.name, bytes: bytes) } else { caps[drive.id] = nil }
        try FileOps.ensureDir(AppPaths.home)
        try JSONStore.save(caps, to: file)
    }

    // MARK: How much is stored

    /// Is this a file LeafJuice's backups put there? A finished backup counts only beside its record, so a stray
    /// archive somebody else left isn't counted (or removed). Partial files always count: they're taking space now.
    static func isBackupFile(_ name: String, siblings: Set<String>) -> Bool {
        if name.hasPrefix("._") { return false }  // macOS's own metadata files on drives like exFAT
        if name.hasSuffix(".partial") || name.hasSuffix(".tar.gz.part") { return true }
        if name.hasSuffix(".tar.gz") { return siblings.contains(String(name.dropLast(".tar.gz".count)) + ".json") }
        if name.hasSuffix(".json") { return siblings.contains(String(name.dropLast(".json".count)) + ".tar.gz") }
        return false
    }

    /// The backup folders whose files count towards a drive's cap: the given folders, and every other server's
    /// folder beside them (a target, or the backups folder, holds one folder per server).
    public static func countedFolders(_ folders: [URL]) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        func add(_ u: URL) { if seen.insert(u.standardizedFileURL.path).inserted { out.append(u) } }
        for folder in folders {
            add(folder)
            for sibling in FileOps.children(folder.deletingLastPathComponent()) where FileOps.isDirectory(sibling) {
                let names = Set(FileOps.children(sibling).map(\.lastPathComponent))
                if names.contains(".leafjuice-server") || names.contains(where: { isBackupFile($0, siblings: names) }) { add(sibling) }
            }
        }
        return out
    }

    /// Bytes of LeafJuice backups, finished and partial, in these folders.
    public static func used(_ folders: [URL]) -> Int64 {
        countedFolders(folders).reduce(Int64(0)) { total, folder in
            let entries = FileOps.children(folder)
            let names = Set(entries.map(\.lastPathComponent))
            return total + entries.filter { isBackupFile($0.lastPathComponent, siblings: names) }.reduce(Int64(0)) { $0 + FileOps.size($1) }
        }
    }

    // MARK: Making room

    public struct Plan: Equatable, Sendable {
        /// Oldest first; removed before the backup starts.
        public var remove: [BackupRecord]
        public var fits: Bool
        /// What the drive's backups would come to after the removals and the new backup.
        public var after: Int64
        public var reason: String
    }

    /// What to remove so a backup of about `estimate` bytes fits under the cap.
    /// `onDrive` is this server's backups on the capped drive; `all` is every backup it has, wherever it is.
    public static func plan(used: Int64, cap: DriveCap, estimate: Int64, onDrive: [BackupRecord], all: [BackupRecord],
                            tierDrops: Set<String>) -> Plan {
        if used + estimate <= cap.bytes {
            return Plan(remove: [], fits: true, after: used + estimate, reason: "Fits under the \(Format.bytes(cap.bytes)) cap on \(cap.name).")
        }
        let newest = all.max(by: older)?.fileName
        let newestHere = onDrive.max(by: older)?.fileName
        let first = all.min(by: older)?.fileName  // D186's tiers keep a server's very first backup, and so does a cap
        let removable = onDrive
            .filter { !$0.pinned && $0.fileName != newest && $0.fileName != newestHere && $0.fileName != first }
            .sorted { a, b in
                let ta = tierDrops.contains(a.fileName), tb = tierDrops.contains(b.fileName)
                return ta != tb ? ta : older(a, b)
            }
        var total = used + estimate
        var remove: [BackupRecord] = []
        for r in removable where total > cap.bytes {
            remove.append(r)
            total -= r.size
        }
        guard total <= cap.bytes else {
            let short = Format.bytes(total - cap.bytes)
            return Plan(remove: [], fits: false, after: used + estimate,
                        reason: "The backups on \(cap.name) would pass its \(Format.bytes(cap.bytes)) cap by \(short), even after removing every older backup this server may remove. Pinned backups, the newest ones, the server's first backup and other servers' backups are kept.")
        }
        return Plan(remove: remove, fits: true, after: total,
                    reason: "To stay under the \(Format.bytes(cap.bytes)) cap on \(cap.name), \(remove.count) older backup\(remove.count == 1 ? "" : "s") (\(Format.bytes(remove.reduce(0) { $0 + $1.size }))) \(remove.count == 1 ? "is" : "are") removed first.")
    }

    /// Dates are kept to the second, so two backups in one second are told apart by the name's -2, -3 suffix.
    static func older(_ a: BackupRecord, _ b: BackupRecord) -> Bool {
        func attempt(_ name: String) -> Int { name.replacingOccurrences(of: ".tar.gz", with: "").split(separator: "-").last.flatMap { Int($0) } ?? 1 }
        return a.date == b.date ? attempt(a.fileName) < attempt(b.fileName) : a.date < b.date
    }

    /// How big the next backup will probably be: the newest one of the same kind with room to grow, or the files'
    /// full size when there's none to go by.
    public static func estimate(records: [BackupRecord], scope: BackupScope, sourceBytes: Int64) -> Int64 {
        guard let last = records.filter({ $0.scope == scope }).max(by: older), last.size > 0 else { return sourceBytes }
        return Int64(Double(last.size) * growth)
    }

    /// Said on the Backups page and as an issue once a drive's backups are at 85% of its cap or more.
    public static func warning(used: Int64, cap: DriveCap) -> String? {
        guard cap.bytes > 0, Double(used) >= Double(cap.bytes) * warnShare else { return nil }
        let share = Int((Double(used) / Double(cap.bytes) * 100).rounded())
        return "Backups on \(cap.name) use \(Format.bytes(used)) of their \(Format.bytes(cap.bytes)) cap (\(share)%). Older backups are removed to make room when needed. To keep more, raise the cap or pin the ones that matter."
    }

    /// For `Tool.run(stopIf:)`: stops a backup once the drive's backups, counting its partial file, pass the cap.
    public static func watch(_ folders: [URL], cap: DriveCap) -> @Sendable () -> String? {
        let paths = folders.map(\.path)
        return {
            let now = used(paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
            return now > cap.bytes ? "The backups on \(cap.name) reached their \(Format.bytes(cap.bytes)) cap." : nil
        }
    }

    // MARK: Leftovers

    /// Removes partial files a backup or copy left behind when LeafJuice was quit or crashed part way. Only call it
    /// when no backup or copy is running for these folders. Returns what was removed.
    @discardableResult
    public static func sweepPartials(_ folders: [URL]) -> [(name: String, bytes: Int64)] {
        var removed: [(String, Int64)] = []
        for folder in folders {
            for f in FileOps.children(folder) where f.lastPathComponent.hasSuffix(".partial") || f.lastPathComponent.hasSuffix(".tar.gz.part") {
                let bytes = FileOps.size(f)
                if (try? FileManager.default.removeItem(at: f)) != nil { removed.append((f.lastPathComponent, bytes)) }
            }
        }
        return removed
    }
}
