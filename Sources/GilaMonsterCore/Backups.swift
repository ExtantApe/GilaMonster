import Foundation

public struct BackupRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String { fileName }
    public var fileName: String
    public var date: Date
    public var size: Int64
    public var scope: BackupScope
    public var trigger: String
    public var software: String
    public var mcVersion: String
    public var serverName: String
    public var pinned = false
    public var warning: String?
    /// What was running, so a whole-folder restore can start straight away as it was.
    public var softwareState: SoftwareState?
    public var launch: LaunchConfig?
    /// The folder it was found in. Set when listing, so a backup on another drive is opened, pinned or deleted there.
    public var location: String?
}

public enum Backups {
    public static func destination(_ profile: ServerProfile) -> URL {
        if let chosen = profile.backup.destination { return URL(fileURLWithPath: chosen, isDirectory: true) }
        return defaultDestination(for: profile)
    }

    /// `<servers folder>/GilaMonster/backups/<server name>`, or a numbered name if another server has that one.
    public static func defaultDestination(for profile: ServerProfile) -> URL {
        let base = ServerFolders.folderName(for: profile.name) ?? profile.id.uuidString
        var candidate = AppPaths.backups.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while let owner = owner(of: candidate), owner != profile.id {
            candidate = AppPaths.backups.appendingPathComponent("\(base) \(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    /// This server's own folder inside a storage target, such as `/Volumes/Drive/GilaMonster backups/<server>`. Several
    /// servers can share a target; each gets a folder of its own, claimed like the default one.
    public static func targetFolder(_ target: String, for profile: ServerProfile) -> URL {
        let root = URL(fileURLWithPath: (target as NSString).expandingTildeInPath, isDirectory: true)
        let base = ServerFolders.folderName(for: profile.name) ?? profile.id.uuidString
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while let owner = owner(of: candidate), owner != profile.id {
            candidate = root.appendingPathComponent("\(base) \(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    /// Is this one of the automatic folders, as opposed to one somebody chose?
    public static func isDefaultLocation(_ folder: URL) -> Bool {
        let parent = folder.deletingLastPathComponent().pathComponents.suffix(2)
        return Array(parent) == [AppPaths.ownFolderName, "backups"]
    }

    private static func ownerFile(_ folder: URL) -> URL { folder.appendingPathComponent(".gilamonster-server") }

    static func owner(of folder: URL) -> UUID? {
        guard let text = try? String(contentsOf: ownerFile(folder), encoding: .utf8) else { return nil }
        return UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Claims a folder for a server, so another server with the same name gets its own.
    public static func claim(_ folder: URL, for id: UUID) throws {
        try FileOps.ensureDir(folder)
        try FileOps.writeAtomic(id.uuidString, to: ownerFile(folder))
    }

    /// Top-level items to leave out because the backup is being written inside them.
    static func withoutDestination(_ items: [String], root: URL, destination: URL) -> [String] {
        let rootParts = root.resolvingSymlinksInPath().pathComponents
        let destParts = destination.resolvingSymlinksInPath().pathComponents
        guard destParts.count > rootParts.count, Array(destParts.prefix(rootParts.count)) == rootParts else { return items }
        return items.filter { $0 != destParts[rootParts.count] }
    }

    /// Worlds are any top-level folder containing `level.dat`, so extra world plugins are covered too.
    public static func worldFolders(_ root: URL) -> [String] {
        // Folia has no level.dat until it stops, so the region folder counts too.
        FileOps.children(root).filter {
            FileOps.exists($0.appendingPathComponent("level.dat")) || FileOps.isDirectory($0.appendingPathComponent("region"))
        }.map(\.lastPathComponent).sorted()
    }

    /// A whole-folder backup is everything needed to run as it was, offline if need be: jars, libraries and
    /// caches included. Only GilaMonster's own bookkeeping stays out, because a restore shouldn't rewind that.
    static let skippedTopLevel: Set<String> = [".gilamonster", ".DS_Store"]

    public static func items(_ root: URL, scope: BackupScope) -> [String] {
        let worlds = worldFolders(root)
        switch scope {
        case .worlds:
            return worlds
        case .standard:
            let settings = FileOps.children(root).map(\.lastPathComponent).filter {
                let ext = ($0 as NSString).pathExtension.lowercased()
                return ["properties", "yml", "yaml", "json", "txt", "toml"].contains(ext)
            }
            return (worlds + settings + ["config", "plugins"].filter { FileOps.exists(root.appendingPathComponent($0)) }).sorted()
        case .everything:
            return FileOps.children(root).map(\.lastPathComponent).filter { !skippedTopLevel.contains($0) }.sorted()
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: date)
    }

    /// Holds shelved upgrades. Being a subfolder keeps them out of listings and retention entirely.
    public static func shelf(_ profile: ServerProfile) -> URL {
        destination(profile).appendingPathComponent("Shelf", isDirectory: true)
    }

    /// Proves an archive can actually bring these worlds back: it exists, every byte decompresses
    /// (gzip checks its own CRC), and each world's `level.dat` is listed inside.
    public static func verify(_ record: BackupRecord, in folder: URL, expectingWorlds worlds: [String]) async throws {
        let archive = folder.appendingPathComponent(record.fileName)
        guard FileOps.exists(archive), FileOps.size(archive) > 0 else {
            throw AppError("The backup \(record.fileName) is missing from \(folder.path).")
        }
        let listing = try await Tool.run("/usr/bin/tar", ["-tzf", archive.path])
        guard listing.ok else { throw AppError("The backup \(record.fileName) is damaged and can't be read.") }
        let entries = Set(listing.out.split(whereSeparator: \.isNewline).map(String.init))
        for world in worlds where !entries.contains("\(world)/level.dat") && !entries.contains("\(world)/region/") {
            throw AppError("The backup \(record.fileName) doesn't contain the world \(world).")
        }
    }

    // MARK: Backups being written

    /// Each tar writing a backup now, and its partial file, so Quit can stop it and leave nothing behind (D213).
    public struct Job: Sendable {
        var process: Process?
        public var partial: URL
        public var server: String = ""
        public var started: Date = Date()
        /// About how big the finished backup will be, for progress. Zero when there's nothing to go by.
        public var expected: Int64 = 0
    }
    final class InFlight: @unchecked Sendable {
        let lock = NSLock()
        var jobs: [UUID: Job] = [:]
        func with<T>(_ body: (inout [UUID: Job]) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(&jobs) }
    }

    /// The backups being written now, with how far each has got, for the quit question (D215).
    public static func running() -> [BackupProgress] {
        inFlight.with { Array($0.values) }.map {
            BackupProgress(server: $0.server, written: FileOps.size($0.partial), expected: $0.expected, started: $0.started)
        }.sorted { $0.started < $1.started }
    }
    static let inFlight = InFlight()

    /// Whether any backup is being written now.
    public static var writing: Bool { inFlight.with { !$0.isEmpty } }

    /// Stops every backup being written and removes its partial file. For Quit: a backup cut short can't be resumed,
    /// and a partial left behind takes space (one was 47 GB, 2026-11-15). Waits up to `wait` seconds for tar to stop.
    @discardableResult
    public static func cancelInFlight(wait: TimeInterval = 5) -> [URL] {
        let jobs = inFlight.with { j -> [Job] in let all = Array(j.values); j = [:]; return all }
        for job in jobs { job.process?.terminate() }
        let deadline = Date().addingTimeInterval(wait)
        for job in jobs {
            while job.process?.isRunning == true, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if job.process?.isRunning == true { kill(job.process!.processIdentifier, SIGKILL); job.process?.waitUntilExit() }
            try? FileManager.default.removeItem(at: job.partial)
        }
        return jobs.map(\.partial)
    }

    public static func create(_ profile: ServerProfile, root: URL, trigger: String, scope: BackupScope? = nil, into folder: URL? = nil,
                              alsoStopIf: (@Sendable () -> String?)? = nil, expected: Int64 = 0) async throws -> BackupRecord {
        let scope = scope ?? profile.backup.scope
        let dest = folder ?? destination(profile)
        let items = withoutDestination(items(root, scope: scope), root: root, destination: dest)
        guard !items.isEmpty else {
            throw AppError(scope == .worlds ? "There's no world to back up yet. Start the server once first." : "There's nothing to back up yet.")
        }
        // A drive that isn't plugged in has no folder to write to. Making one would fill the Mac's own disk instead.
        guard DriveCheck.isConnected(dest) else {
            throw AppError("The backup wasn't started: \(DriveCheck.name(dest)) isn't connected, and nothing was written to the Mac's own disk instead.")
        }
        do { try FileOps.ensureDir(dest) } catch {
            throw AppError("Can't write to the backup folder \(dest.path). If it's on an external drive, check it's connected.")
        }
        // A compressed backup can't exceed the source by much; require the full size to be safe.
        let needed = items.reduce(Int64(0)) { $0 + FileOps.directorySize(root.appendingPathComponent($1).resolvingSymlinksInPath()) }
        // Fails closed, before anything is written: the disk keeps its floor free afterwards (2026-11-14).
        let room = (DiskGuard.standIn ?? DiskGuard.space)(dest)
        if let why = DiskGuard.refusal(free: room.free, capacity: room.capacity, needed: needed) {
            throw AppError("The backup wasn't started. \(why)")
        }

        let date = Date()
        // Two backups in the same second must never share a name: the second would replace the first.
        var base = "\(stamp(date))_\(trigger)"
        var attempt = 2
        while FileOps.exists(dest.appendingPathComponent(base + ".tar.gz")) {
            base = "\(stamp(date))_\(trigger)-\(attempt)"
            attempt += 1
        }
        let archive = dest.appendingPathComponent(base + ".tar.gz")
        let partial = dest.appendingPathComponent(base + ".partial")
        let job = UUID()
        inFlight.with { $0[job] = Job(process: nil, partial: partial, server: profile.name, started: Date(), expected: expected) }
        defer {
            inFlight.with { $0[job] = nil }
            try? FileManager.default.removeItem(at: partial)
        }

        // -H: a linked world folder goes in as its contents, not as a link to somewhere that might be gone later.
        var args = ["-czHf", partial.path, "--exclude", "session.lock", "--exclude", ".DS_Store"]
        args += ["-C", root.path] + items
        // And while it runs: if the disk drops under the in-flight floor anyway, tar stops and the partial file goes.
        // And the drive's backup cap, counting this partial file as it grows (D213).
        let diskWatch = DiskGuard.watch(dest)
        let stopIf: @Sendable () -> String? = { diskWatch() ?? alsoStopIf?() }
        let result = try await Tool.run("/usr/bin/tar", args, stopIf: stopIf, onStart: { process in
            inFlight.with { $0[job]?.process = process }
        })
        if let stopped = result.stoppedBecause { throw AppError("The backup was stopped part way and its partial file removed. \(stopped)") }
        var warning: String?
        // tar stores a link as a link, so what it points at isn't in the backup. Better said than found out later.
        let linked = items.filter { (try? FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent($0).path)) != nil }
        if !linked.isEmpty { warning = "\(linked.joined(separator: ", ")) \(linked.count == 1 ? "is a link" : "are links") to a folder elsewhere. The contents are in this backup, and restoring puts them inside the server folder, leaving the original location alone." }
        if !result.ok {
            // Files changing mid-read make tar complain. If the archive reads back whole, it's usable.
            let verify = try await Tool.run("/usr/bin/tar", ["-tzf", partial.path])
            guard verify.ok else { throw AppError("The backup failed: \(result.err.prefix(300))") }
            warning = [warning, "Some files changed while being copied."].compactMap { $0 }.joined(separator: " ")
        }
        try FileOps.move(partial, to: archive)
        let record = BackupRecord(
            fileName: archive.lastPathComponent, date: date, size: FileOps.size(archive), scope: scope, trigger: trigger,
            software: profile.software.label, mcVersion: profile.software.mcVersion, serverName: profile.name, warning: warning,
            softwareState: profile.software, launch: profile.launch)
        try JSONStore.save(record, to: sidecar(for: archive))
        return record
    }

    static func sidecar(for archive: URL) -> URL {
        archive.deletingPathExtension().deletingPathExtension().appendingPathExtension("json")
    }

    public static func list(_ profile: ServerProfile, in folder: URL? = nil) -> [BackupRecord] {
        let dest = folder ?? destination(profile)
        let decoder = JSONStore.decoder
        return FileOps.children(dest).filter { $0.lastPathComponent.hasSuffix(".tar.gz") }.compactMap { archive in
            guard let data = try? Data(contentsOf: sidecar(for: archive)), var record = try? decoder.decode(BackupRecord.self, from: data) else { return nil }
            record.location = dest.path
            return record
        }.sorted { $0.date > $1.date }
    }

    /// Every backup this server has, in its own folder and in each storage target that's connected now.
    /// One found in two places is listed once, from the first.
    public static func listAll(_ profile: ServerProfile) -> [BackupRecord] {
        var seen = Set<String>()
        var out: [BackupRecord] = []
        for folder in [destination(profile)] + profile.backup.smart.targets.map({ targetFolder($0, for: profile) }) + fallbackFolders(profile) {
            // Only a folder this server claimed: another server's backups are never shown or touched here.
            if folder != destination(profile), owner(of: folder) != profile.id { continue }
            for r in list(profile, in: folder) where seen.insert(r.fileName).inserted { out.append(r) }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// This server's folder for fallback backups, when it has the drive-only rule.
    public static func fallbackFolders(_ profile: ServerProfile) -> [URL] {
        profile.backup.fallback.map { [targetFolder($0.path, for: profile)] } ?? []
    }

    /// Where a record's archive is: the folder it was listed from, or the server's own folder.
    public static func folder(of record: BackupRecord, profile: ServerProfile) -> URL {
        record.location.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? destination(profile)
    }

    public static func setPinned(_ record: BackupRecord, pinned: Bool, profile: ServerProfile, in folder: URL? = nil) throws {
        var updated = record
        updated.pinned = pinned
        updated.location = nil
        try JSONStore.save(updated, to: sidecar(for: (folder ?? Self.folder(of: record, profile: profile)).appendingPathComponent(record.fileName)))
    }

    public static func delete(_ record: BackupRecord, profile: ServerProfile, in folder: URL? = nil) throws {
        let archive = (folder ?? Self.folder(of: record, profile: profile)).appendingPathComponent(record.fileName)
        try FileManager.default.removeItem(at: archive)
        try? FileManager.default.removeItem(at: sidecar(for: archive))
    }

    // MARK: A second location

    /// Copies a finished backup to a second place, then checks the copy reads as the same file.
    /// Anything that goes wrong here leaves the original alone: it's an extra copy, never the only one.
    public static func mirror(_ record: BackupRecord, profile: ServerProfile, to folder: URL) async throws {
        let source = destination(profile).appendingPathComponent(record.fileName)
        guard FileOps.exists(source) else { throw AppError("That backup isn't where it should be.") }
        let target = folder.appendingPathComponent(record.fileName)
        // Names can come round again within a second, so the same name and size don't prove it's the same backup.
        if FileOps.exists(target), FileOps.size(target) == record.size {
            let same = try await Task.detached(priority: .utility) { try Hashing.digests(of: source).sha1 == Hashing.digests(of: target).sha1 }.value
            if same { return }
        }
        do { try FileOps.ensureDir(folder) } catch {
            throw AppError("Can't write to \(folder.path). If it's on another drive, check it's connected.")
        }
        let room = (DiskGuard.standIn ?? DiskGuard.space)(folder)
        if let why = DiskGuard.refusal(free: room.free, capacity: room.capacity, needed: record.size) {
            throw AppError("Not copied to \(folder.path). \(why)")
        }
        let part = folder.appendingPathComponent(record.fileName + ".part")
        try? FileManager.default.removeItem(at: part)
        defer { try? FileManager.default.removeItem(at: part) }
        // Off the main thread, because a big backup over a slow drive takes a while.
        try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: source, to: part) }.value
        let (original, copy) = try await Task.detached(priority: .utility) { (try Hashing.digests(of: source).sha1, try Hashing.digests(of: part).sha1) }.value
        guard original == copy else { throw AppError("The copy at \(folder.path) didn't match, so it was discarded.") }
        try FileOps.move(part, to: target)
        try JSONStore.save(record, to: sidecar(for: target))
    }

    /// The same retention as the main folder, so a second location doesn't grow forever.
    @discardableResult
    public static func pruneMirror(_ profile: ServerProfile, folder: URL, protecting: String? = nil) -> [BackupRecord] {
        let doomed = prunable(list(profile, in: folder), keepLast: max(1, profile.backup.keepLast), keepDays: profile.backup.keepDays, protecting: protecting)
        for record in doomed { try? delete(record, profile: profile, in: folder) }
        return doomed
    }

    /// Backups only the second location still has, such as after the main drive failed.
    public static func onlyInMirror(_ profile: ServerProfile, folder: URL) -> [BackupRecord] {
        let here = Set(list(profile).map(\.fileName))
        return list(profile, in: folder).filter { !here.contains($0.fileName) }
    }

    public static func copyBack(_ record: BackupRecord, profile: ServerProfile, from folder: URL) async throws {
        let dest = destination(profile)
        try FileOps.ensureDir(dest)
        let source = folder.appendingPathComponent(record.fileName)
        let part = dest.appendingPathComponent(record.fileName + ".part")
        try? FileManager.default.removeItem(at: part)
        defer { try? FileManager.default.removeItem(at: part) }
        try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: source, to: part) }.value
        let listing = try await Tool.run("/usr/bin/tar", ["-tzf", part.path])
        guard listing.ok else { throw AppError("That copy can't be read, so it wasn't brought back.") }
        try FileOps.move(part, to: dest.appendingPathComponent(record.fileName))
        try JSONStore.save(record, to: sidecar(for: dest.appendingPathComponent(record.fileName)))
    }

    /// Safety copies from before a restore are pinned so they outlast retention, but they're whole backups,
    /// so repeated restores could fill a disk. Only the most recent few stay pinned, and the rest go back to normal retention.
    public static func trimSafetyCopies(_ profile: ServerProfile, keep: Int = 3) {
        let safety = list(profile).filter { $0.trigger == "before-restore" && $0.pinned }.sorted { $0.date > $1.date }
        for old in safety.dropFirst(keep) { try? setPinned(old, pinned: false, profile: profile) }
    }

    /// Which backups the retention policy would remove. Pinned ones never are, and don't use up the "keep the latest" count.
    public static func prunable(_ records: [BackupRecord], keepLast: Int, keepDays: Int, now: Date = Date(), protecting: String? = nil) -> [BackupRecord] {
        // Dates are stored to the second, so the name settles a tie: same-second backups get a higher suffix.
        func attempt(_ name: String) -> Int {
            let base = name.replacingOccurrences(of: ".tar.gz", with: "")
            return base.split(separator: "-").last.flatMap { Int($0) } ?? 1
        }
        let sorted = records.sorted { $0.date == $1.date ? attempt($0.fileName) > attempt($1.fileName) : $0.date > $1.date }
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        var kept = 0
        return sorted.compactMap { record in
            if record.pinned { return nil }
            kept += 1
            if record.fileName == protecting { return nil }
            if kept <= keepLast { return nil }
            if keepDays > 0, record.date >= cutoff { return nil }
            return record
        }
    }

    /// `protecting` is a backup that's just been made, which must never be what gets removed.
    @discardableResult
    public static func prune(_ profile: ServerProfile, protecting: String? = nil) -> [BackupRecord] {
        let doomed = prunable(list(profile), keepLast: max(1, profile.backup.keepLast), keepDays: profile.backup.keepDays, protecting: protecting)
        for record in doomed { try? delete(record, profile: profile) }
        return doomed
    }

    /// Replaces the items in a backup with their saved copies. The server must be stopped.
    public static func restore(_ record: BackupRecord, profile: ServerProfile, root: URL, from folder: URL? = nil) async throws {
        let archive = (folder ?? Self.folder(of: record, profile: profile)).appendingPathComponent(record.fileName)
        let meta = ServerPaths(root: root).meta
        let work = meta.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        let extracted = work.appendingPathComponent("new", isDirectory: true)
        let replaced = work.appendingPathComponent("old", isDirectory: true)
        try FileOps.ensureDir(extracted)
        try FileOps.ensureDir(replaced)
        defer { try? FileManager.default.removeItem(at: work) }

        let result = try await Tool.run("/usr/bin/tar", ["-xzf", archive.path, "-C", extracted.path])
        guard result.ok else { throw AppError("Couldn't read that backup, so nothing was changed. \(result.err.prefix(200))") }

        var moved: [(new: URL, target: URL, saved: URL?)] = []
        do {
            // A whole-folder restore puts things back exactly as they were, so whatever was added since has to go.
            // Never the backup's own location, if it happens to be inside the server folder.
            if record.scope == .everything {
                let restored = Set(FileOps.children(extracted).map(\.lastPathComponent))
                let kept = Set(FileOps.children(root).map(\.lastPathComponent).filter { !withoutDestination([$0], root: root, destination: folder ?? destination(profile)).isEmpty })
                for name in kept where !restored.contains(name) && !skippedTopLevel.contains(name) {
                    let target = root.appendingPathComponent(name)
                    let saved = replaced.appendingPathComponent(name)
                    try FileOps.move(target, to: saved)
                    moved.append((target, target, saved))
                }
            }
            for item in FileOps.children(extracted) {
                let target = root.appendingPathComponent(item.lastPathComponent)
                var saved: URL?
                if FileOps.exists(target) {
                    saved = replaced.appendingPathComponent(item.lastPathComponent)
                    try FileOps.move(target, to: saved!)
                }
                moved.append((item, target, saved))
                try FileOps.move(item, to: target)
            }
        } catch {
            // Put back whatever already moved, so a failed restore changes nothing.
            for step in moved.reversed() {
                if let saved = step.saved {
                    try? FileOps.move(saved, to: step.target)
                } else {
                    try? FileManager.default.removeItem(at: step.target)
                }
            }
            throw AppError("The restore failed and was undone. \(error.localizedDescription)")
        }
    }
}
