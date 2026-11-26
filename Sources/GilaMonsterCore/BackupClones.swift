import Darwin
import Foundation

/// The folder a backup's APFS clone is made in, and the sweep that clears clones left behind (K799).
///
/// A backup clones the server's files into `<servers>/GilaMonster/backup-clones/<server folder>-<8 hex>` and removes
/// the clone when the archive is done. If GilaMonster is killed or the Mac loses power part-way, the clone stays, and
/// nothing came back for it. Now each launch removes what's left, with these limits:
/// - only when no backup is running, since a running backup's clone is in that folder;
/// - only folders named the way GilaMonster names them, a name, a hyphen and 8 hex digits;
/// - only real folders, directly inside a real `backup-clones` folder. A link is never followed and never removed,
///   and removing a clone removes any link inside it as a link, leaving what it points at alone;
/// - nothing else in that folder is touched.
public enum BackupClones {
    public static let folderName = "backup-clones"

    /// The clones folder for a server: beside the server's own folder, in GilaMonster's folder there.
    public static func folder(besideServer root: URL) -> URL {
        root.deletingLastPathComponent().appendingPathComponent(AppPaths.ownFolderName, isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
    }

    /// A new clone's name: the server's folder name, a hyphen, and 8 hex digits.
    public static func newName(forServer root: URL) -> String { "\(root.lastPathComponent)-\(UUID().uuidString.prefix(8))" }

    /// True for a name GilaMonster gives a clone: something, a hyphen, then exactly 8 hex digits at the end.
    public static func isCloneName(_ name: String) -> Bool {
        guard let dash = name.lastIndex(of: "-"), dash != name.startIndex else { return false }
        let tail = name[name.index(after: dash)...]
        return tail.count == 8 && tail.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    public struct Sweep: Equatable, Sendable {
        /// Names of the clone folders that were removed.
        public var removed: [String] = []
        /// Names that looked like clones and couldn't be removed.
        public var failed: [String] = []
        /// Why nothing was looked at, when that's so.
        public var skipped: String?

        /// One line for the log, or nil when there's nothing to say.
        public func line(_ folder: URL) -> String? {
            var parts: [String] = []
            if !removed.isEmpty { parts.append("Removed \(removed.count) leftover backup clone\(removed.count == 1 ? "" : "s") from \(folder.path): \(removed.joined(separator: ", "))") }
            if !failed.isEmpty { parts.append("Couldn't remove \(failed.joined(separator: ", ")) from \(folder.path)") }
            if let skipped, parts.isEmpty { return "Left \(folder.path) alone: \(skipped)" }
            return parts.isEmpty ? nil : parts.joined(separator: ". ") + "."
        }
    }

    /// What kind of thing is at a path, without following a link.
    private static func kind(_ url: URL) -> mode_t? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? info.st_mode & S_IFMT : nil
    }

    /// Removes leftover clones from one `backup-clones` folder. `backupRunning` must be the truth: when it's true, or
    /// the folder isn't a real folder named backup-clones, nothing is looked at.
    public static func sweep(_ folder: URL, backupRunning: Bool) -> Sweep {
        var out = Sweep()
        guard !backupRunning else { out.skipped = "a backup is running"; return out }
        guard folder.lastPathComponent == folderName else { out.skipped = "it isn't a backup-clones folder"; return out }
        guard let top = kind(folder) else { return out }   // Not there: nothing to do, nothing to say.
        guard top == S_IFDIR else { out.skipped = "it's a link or a file, where a folder was expected"; return out }
        // Its parent is GilaMonster's own folder. If that's a link, the clones folder isn't where it seems to be.
        guard kind(folder.deletingLastPathComponent()) == S_IFDIR else { out.skipped = "the folder it's in is a link"; return out }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        for name in names where isCloneName(name) {
            let item = folder.appendingPathComponent(name, isDirectory: true)
            // A real folder only. A link with a clone's name isn't one of ours, and is left as it is.
            guard kind(item) == S_IFDIR else { continue }
            do {
                try FileManager.default.removeItem(at: item)
                out.removed.append(name)
            } catch { out.failed.append(name) }
        }
        return out
    }

    /// The sweep for every place the given servers keep clones (servers can live in more than one parent folder), and
    /// for the servers folder itself, which may hold clones of a server that has since been taken off the list.
    public static func sweep(besideServers roots: [URL], serversFolder: URL? = nil, backupRunning: Bool) -> [(folder: URL, result: Sweep)] {
        var seen: Set<String> = []
        var out: [(URL, Sweep)] = []
        let folders = roots.map { folder(besideServer: $0) } + (serversFolder.map { [folder(besideServer: $0.appendingPathComponent("a-server"))] } ?? [])
        for folder in folders {
            guard seen.insert(folder.standardizedFileURL.path).inserted else { continue }
            out.append((folder, sweep(folder, backupRunning: backupRunning)))
        }
        return out
    }
}
