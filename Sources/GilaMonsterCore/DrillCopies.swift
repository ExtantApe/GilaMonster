import Darwin
import Foundation

/// The throwaway copy a backup drill boots, and what makes sure it never outlives GilaMonster (K813).
///
/// A drill unpacks a backup into `<backups>/.test-copies/drill-<server folder>-<time>` (or into
/// `<servers>/GilaMonster/test-copies`), starts it on its own port, and removes it. On 2026-11-26 GilaMonster was
/// killed with SIGTERM during a drill and the drill's Java kept running with nobody to stop it, because only listed
/// servers were stopped on the way out. Now:
/// - every drill copy gets a mark beside it when it's made (`<name>.gilamonster-drill`), and is on a list while the
///   drill runs;
/// - on every way out (Quit, a shutdown, SIGTERM, SIGHUP, SIGINT) the drills on that list are stopped and removed;
/// - at the next launch a drill copy left behind (after a force quit, a crash or a power cut) is found by its mark,
///   its Java is stopped if it's still running, and the copy is removed.
///
/// macOS can't end a child with its parent (there's no such setting for a process here, and Java doesn't watch a
/// pipe), and a force quit can't be caught, so the launch sweep is what covers that case.
///
/// The limits, which every removal and every signal goes through:
/// - only a real folder with a drill's name, directly inside a real folder named `test-copies` or `.test-copies`,
///   with a real file as its mark. A link is never followed and never removed. A folder without a mark is left alone;
/// - a process is signalled only when the copy's own `server.pid` names it, it is running, its program is Java, and
///   its working folder is that drill copy. A number that now belongs to anything else is never signalled;
/// - a copy whose Java won't stop is left where it is, mark included, and reported.
public enum DrillCopies {
    public static let usualFolderName = "test-copies"
    public static let besideBackupsFolderName = ".test-copies"
    public static let markSuffix = ".gilamonster-drill"

    // MARK: Names and places

    /// Where drills unpack beside a backup, on the backup's own disk.
    public static func folder(besideBackups backups: URL) -> URL {
        backups.appendingPathComponent(besideBackupsFolderName, isDirectory: true)
    }

    /// Where drills unpack otherwise: beside the server's own folder, in GilaMonster's folder there.
    public static func folder(besideServer root: URL) -> URL {
        root.deletingLastPathComponent().appendingPathComponent(AppPaths.ownFolderName, isDirectory: true).appendingPathComponent(usualFolderName, isDirectory: true)
    }

    /// A new drill copy's name: `drill-`, the server's folder name, a hyphen and the time in whole seconds.
    public static func newName(forServer root: URL, date: Date = Date()) -> String {
        "drill-\(root.lastPathComponent)-\(Int(date.timeIntervalSince1970))"
    }

    /// True for a name GilaMonster gives a drill copy.
    public static func isDrillName(_ name: String) -> Bool {
        guard name.hasPrefix("drill-"), let dash = name.lastIndex(of: "-") else { return false }
        let tail = name[name.index(after: dash)...]
        let middle = name[name.index(name.startIndex, offsetBy: 5)..<dash]   // from the first hyphen to the last
        return !middle.isEmpty && middle != "-" && !tail.isEmpty && tail.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The mark's file: a plain file beside the copy, so it's never part of the server that boots.
    public static func markURL(_ copy: URL) -> URL {
        copy.deletingLastPathComponent().appendingPathComponent(copy.lastPathComponent + markSuffix)
    }

    static func unmark(_ copy: URL) {
        let mark = markURL(copy)
        if kind(mark) == S_IFREG { try? FileManager.default.removeItem(at: mark) }
    }

    /// What kind of thing is at a path, without following a link.
    static func kind(_ url: URL) -> mode_t? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? info.st_mode & S_IFMT : nil
    }

    static func resolved(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    /// True when this is a drill copy GilaMonster made and marked: the only folders that are ever removed here.
    public static func isMarkedCopy(_ copy: URL) -> Bool {
        let parent = copy.deletingLastPathComponent()
        return isDrillName(copy.lastPathComponent)
            && [usualFolderName, besideBackupsFolderName].contains(parent.lastPathComponent)
            && kind(parent) == S_IFDIR && kind(copy) == S_IFDIR && kind(markURL(copy)) == S_IFREG
    }

    // MARK: The drills this GilaMonster is running

    private final class Running: @unchecked Sendable {
        private let lock = NSLock()
        private var copies: [String: URL] = [:]
        private var unpackers: [String: Process] = [:]
        private var closing = false
        func with<T>(_ body: (inout [String: URL], inout [String: Process], inout Bool) -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body(&copies, &unpackers, &closing)
        }
    }
    private static let running = Running()

    /// True once GilaMonster has started quitting. No drill starts after that, and no throwaway copy is booted.
    public static var isClosing: Bool { running.with { _, _, closing in closing } }

    /// The drill copies this GilaMonster is running now.
    public static var live: [URL] { running.with { copies, _, _ in Array(copies.values) } }

    /// For the checks: a fresh start, as when the app opens.
    static func reopen() { running.with { copies, unpackers, closing in copies = [:]; unpackers = [:]; closing = false } }

    /// Makes a new drill copy's folder with its mark, and lists it. False when GilaMonster is quitting or the mark
    /// can't be written, and then nothing is left behind.
    public static func begin(_ copy: URL) -> Bool {
        let listed = running.with { copies, _, closing -> Bool in
            guard !closing, copies[copy.path] == nil else { return false }
            copies[copy.path] = copy
            return true
        }
        guard listed else { return false }
        let made: Bool = {
            guard isDrillName(copy.lastPathComponent), (try? FileOps.ensureDir(copy.deletingLastPathComponent())) != nil else { return false }
            guard kind(copy) == nil, kind(markURL(copy)) == nil else { return false }   // never over something already there
            guard FileManager.default.createFile(atPath: markURL(copy).path, contents: Data("Made by GilaMonster for one backup drill. Removed with the copy.\n".utf8)) else { return false }
            guard (try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: false)) != nil else { unmark(copy); return false }
            return true
        }()
        if !made { running.with { copies, _, _ in copies[copy.path] = nil } }
        return made
    }

    /// The tar that's unpacking into a copy, so quitting can stop it.
    public static func unpacking(_ copy: URL, with process: Process?) {
        running.with { _, unpackers, _ in unpackers[copy.path] = process }
    }

    /// The drill is over: removes the copy and its mark, and takes it off the list.
    public static func finish(_ copy: URL) {
        if isMarkedCopy(copy) { try? FileManager.default.removeItem(at: copy) }
        if kind(copy) == nil { unmark(copy) }
        running.with { copies, unpackers, _ in copies[copy.path] = nil; unpackers[copy.path] = nil }
    }

    /// Removes the folder drills unpack into beside a backup, only when it's empty.
    public static func removeIfEmpty(_ folder: URL) {
        guard folder.lastPathComponent == besideBackupsFolderName, kind(folder) == S_IFDIR else { return }
        rmdir(folder.path)
    }

    /// GilaMonster is quitting: no new drill, and any unpacking stops. Doesn't wait.
    public static func close() {
        let unpackers = running.with { _, unpackers, closing -> [Process] in closing = true; return Array(unpackers.values) }
        for process in unpackers where process.isRunning { process.terminate() }
    }

    /// The last thing on every way out of the app: stops each running drill's Java and removes its copy. Waits for
    /// each Java to go, up to `patience` seconds before it's forced. Safe to call more than once.
    @discardableResult
    public static func endAll(patience: TimeInterval = 5) -> [(copy: URL, result: Removal)] {
        close()
        var out: [(URL, Removal)] = []
        for copy in live.sorted(by: { $0.path < $1.path }) {
            let result = stopAndRemove(copy, patience: patience)
            if result != .stillRunning { running.with { copies, unpackers, _ in copies[copy.path] = nil; unpackers[copy.path] = nil } }
            out.append((copy, result))
        }
        return out
    }

    // MARK: Stopping a drill's Java

    /// The Java running in a drill copy, from the copy's own pid file, and only if it really is that: running, a Java
    /// program, and working in that folder. After a restart the number in the file can belong to anything, and a
    /// copy unpacked from a backup can even carry the real server's number.
    public static func javaPID(in copy: URL) -> Int32? {
        guard let data = try? Data(contentsOf: ServerPaths(root: copy).pid), data.count < 64,
              let pid = try? JSONStore.decoder.decode(Int32.self, from: data), isDrillJava(pid: pid, copy: copy) else { return nil }
        return pid
    }

    public static func isDrillJava(pid: Int32, copy: URL) -> Bool {
        guard pid > 1, pid != getpid(), SystemInfo.isAlive(pid: pid) else { return false }
        guard let program = SystemInfo.executablePath(pid: pid), URL(fileURLWithPath: program).lastPathComponent.lowercased().contains("java") else { return false }
        guard let folder = SystemInfo.workingDirectory(pid: pid) else { return false }
        return resolved(folder) == resolved(copy)
    }

    public enum Removal: Equatable, Sendable {
        /// The copy and its mark are gone. `stopped` is the Java that was stopped first, if one was running.
        case removed(stopped: Int32?)
        /// Not a marked drill copy, so nothing was touched.
        case notOurs
        /// Its Java didn't stop, so the copy was left as it is.
        case stillRunning
        /// The folder couldn't be removed.
        case failed
    }

    /// Stops a marked drill copy's Java, if it's running, and removes the copy and its mark. The copy is a throwaway,
    /// so Java gets `patience` seconds to go after a SIGTERM and is then forced.
    public static func stopAndRemove(_ copy: URL, patience: TimeInterval = 10) -> Removal {
        guard isMarkedCopy(copy) else { return .notOurs }
        var stopped: Int32?
        if let pid = javaPID(in: copy) {
            stopped = pid
            kill(pid, SIGTERM)
            if !waitUntilGone(pid, copy, patience) {
                // Checked again, so a number that changed hands while waiting is never forced.
                if isDrillJava(pid: pid, copy: copy) { kill(pid, SIGKILL) }
                guard waitUntilGone(pid, copy, 5) else { return .stillRunning }
            }
        }
        do { try FileManager.default.removeItem(at: copy) } catch { return .failed }
        unmark(copy)
        return .removed(stopped: stopped)
    }

    private static func waitUntilGone(_ pid: Int32, _ copy: URL, _ seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while isDrillJava(pid: pid, copy: copy) {
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    // MARK: The sweep at launch

    public struct Sweep: Equatable, Sendable {
        /// Names of the drill copies that were removed.
        public var removed: [String] = []
        /// Of those, the ones whose Java was still running and was stopped first.
        public var stopped: [String] = []
        /// Names that look like drill copies but carry no mark, so they were left alone.
        public var unmarked: [String] = []
        /// Copies whose Java wouldn't stop, or that couldn't be removed. Left as they are.
        public var failed: [String] = []
        /// Why nothing was looked at, when that's so.
        public var skipped: String?

        /// One line for the log, or nil when there's nothing to say.
        public func line(_ folder: URL) -> String? {
            var parts: [String] = []
            if !removed.isEmpty {
                parts.append("Removed \(removed.count) leftover backup drill cop\(removed.count == 1 ? "y" : "ies") from \(folder.path): \(removed.joined(separator: ", "))")
            }
            if !stopped.isEmpty { parts.append("Stopped the Java still running in \(stopped.joined(separator: ", ")) first") }
            if !failed.isEmpty { parts.append("Couldn't stop or remove \(failed.joined(separator: ", ")) in \(folder.path)") }
            if let skipped, parts.isEmpty { return "Left \(folder.path) alone: \(skipped)" }
            return parts.isEmpty ? nil : parts.joined(separator: ". ") + "."
        }
    }

    /// Stops and removes drill copies left in one folder by a GilaMonster that went away during a drill.
    /// `otherCopyRunning` must be the truth: another GilaMonster's drill is in the same place, so nothing is looked at.
    public static func sweep(_ folder: URL, otherCopyRunning: Bool, patience: TimeInterval = 10) -> Sweep {
        var out = Sweep()
        guard !otherCopyRunning else { out.skipped = "another GilaMonster is running"; return out }
        guard [usualFolderName, besideBackupsFolderName].contains(folder.lastPathComponent) else { out.skipped = "it isn't a test-copies folder"; return out }
        guard let top = kind(folder) else { return out }   // Not there: nothing to do, nothing to say.
        guard top == S_IFDIR else { out.skipped = "it's a link or a file, where a folder was expected"; return out }
        // The usual folder's parent is GilaMonster's own folder. If that's a link, this isn't where it seems to be.
        if folder.lastPathComponent == usualFolderName, kind(folder.deletingLastPathComponent()) != S_IFDIR { out.skipped = "the folder it's in is a link"; return out }
        let mine = Set(live.map(\.path))
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        for name in names where isDrillName(name) {
            let copy = folder.appendingPathComponent(name, isDirectory: true)
            // A real folder only, and never a drill this GilaMonster is running now.
            guard kind(copy) == S_IFDIR, !mine.contains(copy.path) else { continue }
            guard kind(markURL(copy)) == S_IFREG else { out.unmarked.append(name); continue }
            switch stopAndRemove(copy, patience: patience) {
            case .removed(let pid):
                out.removed.append(name)
                if pid != nil { out.stopped.append(name) }
            case .stillRunning, .failed: out.failed.append(name)
            case .notOurs: out.unmarked.append(name)
            }
        }
        // A mark whose copy is gone (the app went away between the two removals) goes too.
        for name in names where name.hasSuffix(markSuffix) {
            let copyName = String(name.dropLast(markSuffix.count))
            let copy = folder.appendingPathComponent(copyName, isDirectory: true)
            if isDrillName(copyName), kind(copy) == nil, !mine.contains(copy.path) { unmark(copy) }
        }
        removeIfEmpty(folder)
        return out
    }

    /// The sweep for every place drills unpack: beside each server (servers can live in more than one parent folder),
    /// in the servers folder itself, and beside each folder backups are kept in.
    public static func sweep(besideServers roots: [URL], serversFolder: URL? = nil, backupFolders: [URL], otherCopyRunning: Bool,
                             patience: TimeInterval = 10) -> [(folder: URL, result: Sweep)] {
        var seen: Set<String> = []
        let folders = roots.map { folder(besideServer: $0) }
            + (serversFolder.map { [folder(besideServer: $0.appendingPathComponent("a-server"))] } ?? [])
            + backupFolders.map { folder(besideBackups: $0) }
        // Settled before anything is removed: a path can read differently once its folder is gone.
        let once = folders.filter { seen.insert($0.standardizedFileURL.path).inserted }
        return once.map { ($0, sweep($0, otherCopyRunning: otherCopyRunning, patience: patience)) }
    }
}

/// The signals that ask GilaMonster to quit (K692): each is taken off its default, which ends the app at once and
/// leaves its servers running, and handed to `handler` on the main queue instead.
public enum QuitSignals {
    public static let all: [Int32] = [SIGTERM, SIGHUP, SIGINT]

    public static func name(_ sig: Int32) -> String { sig == SIGTERM ? "SIGTERM" : sig == SIGHUP ? "SIGHUP" : "SIGINT" }

    /// Keep what this returns for as long as the signals should be watched.
    public static func watch(_ handler: @escaping @Sendable (Int32) -> Void) -> [DispatchSourceSignal] {
        all.map { sig in
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { handler(sig) }
            source.resume()
            return source
        }
    }
}
