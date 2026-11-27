import Foundation

/// Where GilaMonster's saved settings live: the theme, appearance, chosen server, servers folder, Lab ticks, text size
/// and the Advisor's yeses. Everything that reads or writes a setting goes through `AppDefaults.store` (K814).
///
/// Normally that is the app's own settings, `UserDefaults.standard`, exactly as before. With `GILAMONSTER_HOME` set,
/// for a test copy, a demo or the checks, it is `preferences.plist` inside that folder, so nothing a test copy saves
/// reaches the real app's settings and nothing the owner chose leaks into the test. The file goes when the folder does.
public enum AppDefaults {
    /// The settings file inside a redirected home, without its `.plist` ending.
    public static let fileName = "preferences"

    public enum Place: Equatable, Sendable {
        /// The app's own settings.
        case app
        /// A settings file of its own. The full path, without `.plist`.
        case file(String)
    }

    /// Decided by `GILAMONSTER_HOME` alone, the same variable that moves `AppPaths.home`.
    public static func place(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Place {
        guard let home = environment["GILAMONSTER_HOME"] else { return .app }
        // Always a full path. A bare name would be read as a settings domain in ~/Library/Preferences.
        return .file(URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.appendingPathComponent(fileName).path)
    }

    public static func store(_ environment: [String: String]) -> UserDefaults {
        switch place(environment) {
        case .app: return .standard
        case .file(let path): return fileStore(path)
        }
    }

    /// The store for this process. Use this everywhere, and pass it to every `@AppStorage` as `store:`.
    public static var store: UserDefaults { store(ProcessInfo.processInfo.environment) }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var opened: [String: UserDefaults] = [:]

    /// One object per file, so SwiftUI's `@AppStorage` and plain reads see each other's changes.
    private static func fileStore(_ path: String) -> UserDefaults {
        lock.lock()
        defer { lock.unlock() }
        if let known = opened[path] { return known }
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        // macOS treats a full path as a settings file of its own. If it ever refuses, stop: a test copy must not fall
        // back to the real app's settings.
        guard path.hasPrefix("/"), let made = UserDefaults(suiteName: path) else {
            preconditionFailure("GilaMonster couldn't open the settings file for GILAMONSTER_HOME at \(path).plist")
        }
        opened[path] = made
        return made
    }
}
