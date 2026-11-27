import Foundation
import GilaMonsterCore

/// Saved settings (K814). A copy run with GILAMONSTER_HOME shared the real app's settings: theme, appearance, chosen
/// server, Lab ticks and the rest. It now keeps them in a file inside that folder, and nothing changes without it.
@MainActor func appDefaultsChecks() {
    section("Saved settings: a redirected home keeps its own")
    // Without the variable: the app's own settings, as before.
    equal(AppDefaults.place([:]), .app, "with no GILAMONSTER_HOME the settings are the app's own")
    check(AppDefaults.store([:]) === UserDefaults.standard, "and the store is UserDefaults.standard itself, so existing preferences are still read")
    equal(AppDefaults.place(["GILAMONSTER_SERVERS": "/tmp/made-up-servers", "HOME": "/private/var/made-up-home"]), .app, "GILAMONSTER_SERVERS alone, or HOME, doesn't move them")

    // With it: a file inside that folder.
    let home = folder("defaults-home")
    let other = folder("defaults-other")
    let env = ["GILAMONSTER_HOME": home.path]
    equal(AppDefaults.place(env), .file(home.standardizedFileURL.path + "/preferences"), "with GILAMONSTER_HOME they are preferences.plist in that folder")
    let store = AppDefaults.store(env)
    check(store !== UserDefaults.standard, "the store isn't the app's own")
    check(AppDefaults.store(env) === store, "the same folder gives the same store each time")
    check(AppDefaults.store(["GILAMONSTER_HOME": other.path]) !== store, "another folder gives another")
    if case .file(let path) = AppDefaults.place(["GILAMONSTER_HOME": "made-up/relative"]) {
        check(path.hasPrefix("/") && path.hasSuffix("/made-up/relative/preferences"), "a relative folder becomes a full path, never a domain name: \(path)")
    } else { check(false, "a relative folder still moves the settings") }
    if case .file(let path) = AppDefaults.place(["GILAMONSTER_HOME": ""]) {
        check(path.hasPrefix("/") && path.hasSuffix("/preferences"), "an empty value still moves them: \(path)")
    } else { check(false, "an empty value still moves the settings") }

    // A value saved there lands in that file and nowhere the app's own settings can see.
    let key = "gilamonsterCheck-\(UUID().uuidString)"
    store.set("made-up", forKey: key)
    ThemeChoice.save(.quiet, store)
    CFPreferencesAppSynchronize(home.standardizedFileURL.path + "/preferences" as CFString)
    let file = home.appendingPathComponent("preferences.plist")
    let saved = (try? Data(contentsOf: file)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
    equal(saved?[key] as? String, "made-up", "a saved value is written to the folder's preferences.plist")
    equal(saved?[ThemeChoice.key] as? String, "quiet", "the theme too")
    check(UserDefaults.standard.object(forKey: key) == nil, "the app's own settings don't get it")
    check(AppDefaults.store(["GILAMONSTER_HOME": other.path]).object(forKey: key) == nil, "nor does another folder's store")
    UserDefaults.standard.register(defaults: [:])   // no write: the next line only reads
    check(store.object(forKey: "NSWindow Frame main") == nil && store.string(forKey: ThemeChoice.key) == "quiet", "and it reads only its own values")

    // This run has GILAMONSTER_HOME set, so everything with a default store uses the scratch folder.
    equal(AppDefaults.place(), .file(AppPaths.home.standardizedFileURL.path + "/preferences"), "this run's settings are inside its scratch home")
    check(AppDefaults.store !== UserDefaults.standard, "so the checks never write the settings of whatever runs them")

    check(ProcessInfo.processInfo.environment["GILAMONSTER_SERVERS"] != nil && !AppPaths.asksForServersFolder,
          "with GILAMONSTER_SERVERS naming the folder, a new home doesn't ask for one at first launch")

    // One place: nothing else names the app's own settings, and every @AppStorage is given the store.
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    var direct: [String] = []
    var bare: [String] = []
    var stored = 0
    var files = 0
    for target in ["GilaMonster", "GilaMonsterCore", "GilaMonsterAdvisor", "gilamonster-session", "gilamonster-mcp"] {
        let folder = sources.appendingPathComponent(target)
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "swift" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            files += 1
            if file.lastPathComponent == "AppDefaults.swift" { continue }
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//")[0]
                let place = "\(target)/\(file.lastPathComponent):\(index + 1)"
                if code.contains("UserDefaults.standard") || code.contains("UserDefaults = .standard") || code.contains("UserDefaults()") || code.contains("defaultAppStorage") { direct.append(place) }
                if code.contains("@AppStorage(") {
                    if code.contains("store: AppDefaults.store)") { stored += 1 } else { bare.append(place) }
                }
                if code.contains("@SceneStorage") || code.contains("setFrameAutosaveName") { direct.append(place) }
            }
        }
    }
    check(files > 40, "the app's source was read (\(files) files)")
    check(direct.isEmpty, "nothing outside AppDefaults names the app's own settings: \(direct.joined(separator: ", "))")
    check(bare.isEmpty, "every @AppStorage is given AppDefaults.store: \(bare.joined(separator: ", "))")
    check(stored >= 8, "and all eight or more are counted (\(stored))")
}
