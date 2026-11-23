import Foundation

/// Pausing and resuming the server's own saving around a backup or a copy (K691).
///
/// Saving is paused only for the moment it takes to take an APFS clone of the files, then turned back on and confirmed,
/// and the archive is made from the clone. Turning saving back on is confirmed by the server's own reply, retried once,
/// and raised as an issue if it still can't be confirmed: a server left unsaved for hours is the failure this guards.
extension ServerController {
    static let savingOffIssue = "wrapper:saving-off"

    /// Pauses saving and flushes the world to disk. Returns false if the save wasn't confirmed in time.
    func pauseSaving() async -> Bool {
        guard let process else { return false }
        process.send("save-off")
        let saved = Task { await waitForLine(containing: "saved the game", timeout: .seconds(120)) }
        await Task.yield()
        process.send("save-all flush")
        return await saved.value
    }

    /// Turns saving back on and waits for the server to say so. Tries twice, then reports an issue that stays until a
    /// later resume is confirmed. A stopped server needs nothing: saving is on again at its next start.
    @discardableResult
    func resumeSaving(after what: String) async -> Bool {
        for attempt in 1...2 {
            guard let process, state == .running else { dropIssue(Self.savingOffIssue); return true }
            let confirmed = Task { await waitForLine(containingAny: ["automatic saving is now enabled", "saving is already turned on"], timeout: .seconds(20)) }
            await Task.yield()
            process.send("save-on")
            if await confirmed.value != nil {
                dropIssue(Self.savingOffIssue)
                return true
            }
            if attempt == 1 { appendWrapper("The server didn't confirm saving was back on after \(what). Asking again.", level: .warn) }
        }
        let now = Date()
        let detail = "After \(what), \(profile.name) didn't confirm that automatic saving is back on, so the world may not be saving."
        reportIssue(IssueRecord(
            id: Self.savingOffIssue, ruleID: "wrapper-saving-off", title: "Saving may still be off", severity: .error, category: "Backups",
            explanation: detail,
            steps: ["Type save-on in the Console and check it says \"Automatic saving is now enabled\".", "If the server doesn't answer, stop and start it."],
            action: IssueAction(page: "console", label: "Open Console"), sample: detail, firstSeen: now, lastSeen: now))
        recordEvent(.backup, "Saving may still be off", detail: detail)
        return false
    }

    /// APFS clones of the backup's files, in a folder of GilaMonster's own on the same disk, so the archive can be made
    /// while the server saves again. Nil when a clone isn't possible (another file system, a world linked from another
    /// drive): then the caller archives the live files with saving paused, as before. Never falls back to a full copy,
    /// which could fill the Mac's disk.
    func cloneForBackup(scope: BackupScope) async -> URL? {
        let items = Backups.items(paths.root, scope: scope)
        guard !items.isEmpty else { return nil }
        let folder = paths.root.deletingLastPathComponent()
            .appendingPathComponent(AppPaths.ownFolderName, isDirectory: true)
            .appendingPathComponent("backup-clones", isDirectory: true)
            .appendingPathComponent("\(paths.root.lastPathComponent)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do { try FileOps.ensureDir(folder) } catch { return nil }
        for item in items {
            let source = paths.root.appendingPathComponent(item)
            // -c only: a clone or nothing. No -L, so a linked world isn't followed onto another drive.
            let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: source.path)) != nil
            let result = isLink ? nil : try? await Tool.run("/bin/cp", ["-cR", source.path, folder.appendingPathComponent(item).path])
            guard result?.ok == true else {
                Self.removeClone(folder)
                return nil
            }
        }
        return folder
    }

    /// Removes a clone folder this controller made, and nothing else: only a path inside backup-clones.
    static func removeClone(_ folder: URL) {
        guard folder.deletingLastPathComponent().lastPathComponent == "backup-clones" else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
