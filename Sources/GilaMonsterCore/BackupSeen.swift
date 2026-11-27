import Foundation

/// What GilaMonster can say about backups (K823). It counts the backups it made: the archives with its own record
/// beside them, in this server's folder and in each storage folder the owner added. A backup made by another tool is
/// never listed or counted, wherever it sits, so every age shown is labelled as GilaMonster's own.
public enum BackupSeen {
    /// The label beside the newest backup's age on the Overview's Backups card.
    public static let latestLabel = "GilaMonster's latest"
    /// The note under the Overview's Backups card.
    public static let cardNote = "Backups made by other tools aren't counted."
    /// The note under the Backups page's list.
    public static let listNote = "This list and every backup age in GilaMonster count only the backups GilaMonster made. Backups made by other tools aren't shown or counted, wherever they're kept."

    /// The newest backup's date in each folder, keyed by the folder's path, from a listing (`Backups.listAll`).
    public static func newestByFolder(_ records: [BackupRecord]) -> [String: Date] {
        var out: [String: Date] = [:]
        for r in records {
            guard let place = r.location else { continue }
            if let have = out[place], have >= r.date { continue }
            out[place] = r.date
        }
        return out
    }

    /// One line for a storage folder's row on the Backups page. Nil while the folder can't be read (an unplugged
    /// drive), because what's on it is unknown until it's back.
    public static func storageLine(newest: Date?, readable: Bool, now: Date = Date()) -> String? {
        guard readable else { return nil }
        guard let newest else { return "No GilaMonster backup here yet." }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        return "Newest GilaMonster backup here: \(rel.localizedString(for: newest, relativeTo: now))."
    }
}
