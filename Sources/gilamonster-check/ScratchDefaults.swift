import Foundation

/// Every settings domain the checks make comes from here, so each is a throwaway that is removed at the end (D226).
/// `removePersistentDomain` empties a suite but leaves its (42 byte) plist in ~/Library/Preferences, so the file is
/// deleted too, by its exact name. Only names this run made are ever touched.
nonisolated(unsafe) private var madeSuites: [String] = []

func scratchDefaults(_ label: String) -> (defaults: UserDefaults, suite: String)? {
    let suite = "gilamonster-check-\(label)-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { return nil }
    madeSuites.append(suite)
    return (defaults, suite)
}

func suitePlist(_ suite: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
}

/// Removes the suite's contents and its file. Safe to call twice, and by atexit.
func removeScratchSuite(_ suite: String) {
    guard madeSuites.contains(suite) else { return }
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: suitePlist(suite))
}

func removeAllScratchSuites() { for suite in madeSuites { removeScratchSuite(suite) } }

/// The names of this run's domains whose plist is still on disk.
func leftoverScratchSuites() -> [String] {
    madeSuites.filter { FileManager.default.fileExists(atPath: suitePlist($0).path) }
}

/// macOS's preferences daemon writes a removed domain's empty file back a moment later, so the last pass waits for it.
func settleScratchSuites() {
    removeAllScratchSuites()
    Thread.sleep(forTimeInterval: 1.0)
    for suite in madeSuites { try? FileManager.default.removeItem(at: suitePlist(suite)) }
    Thread.sleep(forTimeInterval: 0.5)
}

@MainActor func scratchDefaultsChecks() {
    section("Settings domains the checks made are all removed")
    settleScratchSuites()
    check(!madeSuites.isEmpty, "this run made scratch settings domains (\(madeSuites.count))")
    let left = leftoverScratchSuites()
    check(left.isEmpty, "no gilamonster-check settings file from this run is left: \(left.joined(separator: ", "))")
}
