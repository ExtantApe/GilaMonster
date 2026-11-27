import Foundation
@testable import GilaMonsterCore

/// The row of banners above the page (K815). With a banner whose text could wrap, the column holding the row once came
/// out far taller than the window, and the page left the picture. These read the app's source, since its views can't
/// be loaded here. The measured half is in `--snapshot`, which draws the banners and reads where the page landed.
@MainActor func bannerRowChecks() {
    section("Banner row: no banner can push the page out of view")
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    let files = ((try? FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "swift" }
    var sources: [String: String] = [:]
    for file in files { sources[file.lastPathComponent] = (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
    let theme = sources["Theme.swift"] ?? "", rootView = sources["RootView.swift"] ?? ""
    check(files.count > 20 && !theme.isEmpty && !rootView.isEmpty, "the app's source was found (\(files.count) files)")

    // The column beside the spine never asks for more height than it's given, whatever is in it.
    let column = rootView.components(separatedBy: "struct ServerWindow: View").dropFirst().first?.components(separatedBy: ".navigationTitle(server.profile.name)").first ?? ""
    check(column.contains("                Trail(model: model, server: server)\n                banners.snapshotProbe { SnapshotProbe.banners = $0 }\n                pageView\n"),
          "the server window puts only the banners between the trail and the page")
    let held = column.range(of: ".frame(minHeight: Self.columnMinHeight, maxHeight: .infinity)"), inspector = column.range(of: ".inspector(isPresented:")
    check(held != nil && inspector != nil && held!.lowerBound < inspector!.lowerBound, "the column holding them takes the height it's given, set before the inspector measures it")
    check(column.components(separatedBy: ".inspector(").count == 2, "and there is one inspector, around that column")
    let minimum = rootView.components(separatedBy: "private static var columnMinHeight: CGFloat? {").dropFirst().first?.components(separatedBy: "\n    }").first ?? ""
    check(minimum == "\n        #if DEBUG\n        if ProcessInfo.processInfo.environment[\"GILAMONSTER_SNAPSHOT_FORCE_TALL_COLUMN\"] != nil { return nil }\n        #endif\n        return 0",
          "its smallest height is zero, and only a debug build can take that away, for the snapshot's own proof")

    // No callout needs an option for the row any more, so none can forget it.
    let optional = sources.filter { $0.value.contains("inBannerRow") }.keys.sorted()
    check(optional.isEmpty, "no callout has a layout of its own for the banner row. \(optional.joined(separator: ", "))")
    equal(theme.components(separatedBy: ".fixedSize(horizontal: false, vertical: true)").count - 1 >= 2, true, "a callout keeps its title and second line at full height everywhere, so neither is cut short")

    // Every banner the server window shows is in that one row.
    let row = rootView.components(separatedBy: "@ViewBuilder private var banners: some View {\n").dropFirst().first?.components(separatedBy: "\n    private var isExternal").first ?? ""
    check(row.hasPrefix("        VStack(spacing: 8) {\n            KeychainBanner()\n"), "the row starts with the Keychain banner")
    equal(row.components(separatedBy: "Callout(").count - 1, 4, "then its four callouts: disk space, a notice, a server running outside GilaMonster and an app update")
    check(row.contains("TrialBanner(server: server)"), "and the test copy's banner")
    func uses(_ call: String) -> Int { sources.values.reduce(0) { $0 + $1.components(separatedBy: call).count - 1 } }
    equal(uses("KeychainBanner()"), 2, "the Keychain banner is shown in two places: that row and the welcome screen, which has no inspector")
    equal(uses("TrialBanner("), 1, "the test copy's banner is shown only in that row")

    section("Banner row: the made-up banners the snapshot can draw")
    let script = (try? String(contentsOf: app.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/snapshot-fixtures.sh"), encoding: .utf8)) ?? ""
    let names = ServerController.previewBannerNames + ["update", "all"]
    check(script.contains("case \"$b\" in " + names.joined(separator: "|") + ") ;;"), "the script takes exactly the names the app knows")
    let home = folder("banner-preview")
    let server = ServerController(root: home.appendingPathComponent("made-up"), profile: ServerProfile())
    server.previewBanners(["all"])
    check(server.diskWarning != nil && server.notice != nil && server.state == .external(pid: 4321) && server.trialPhase == .finished && server.trialReport?.passed == false,
          "all puts up one of each: disk space, a notice, a server running outside GilaMonster and a failed test copy")
    for text in [server.diskWarning, server.notice] {
        check(Overflow.callout(title: text ?? "", detail: nil).detail != nil, "with a second line")
    }
    let open = ServerController(root: home.appendingPathComponent("made-up-2"), profile: ServerProfile())
    open.previewBanners(["trial-open"])
    let long = ServerController(root: home.appendingPathComponent("made-up-3"), profile: ServerProfile())
    long.previewBanners(["long-title"])
    let cut = Overflow.callout(title: long.notice ?? "", detail: nil)
    check(cut.detail == nil && cut.title.count > 100, "long-title is a notice whose one line is as long as a title gets (\(cut.title.count) characters)")
    check(open.trialPhase == .open && open.diskWarning == nil && open.notice == nil && open.state == .stopped, "one name puts up only that banner")
}
