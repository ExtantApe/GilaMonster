import CryptoKit
import Foundation
import GilaMonsterCore

/// Pixel type (K820): the size snap, Bold Text, the setting's first-launch default, the off state, the glyphs each
/// face has, font files that don't load, what the app bundles, and that controls grow with the text.
@MainActor func pixelTypeChecks() {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = repo.appendingPathComponent("Sources/GilaMonster")
    func source(_ name: String) -> String { (try? String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    typealias C = PixelType.Conditions
    let roles: [(String, PixelType.Role)] = [
        ("screen title", .screenTitle(26)), ("status sentence", .display(28)), ("prompt sentence", .promptSentence), ("sheet title", .title(17)),
        ("heading", .heading), ("label", .label(.regular)), ("button", .label(.semibold)), ("number", .number), ("body", .body), ("log", .mono),
    ]
    // The body sizes macOS offers in Text Size, and one in between.
    let bodies: [Double] = [9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 23, 24, 29, 35, 42]

    section("Pixel type: sizes snap up to the next sharp size")
    equal(PixelType.snap(11, body: 13, scale: 2), 11, "labels are 11 pt at the default text size on Retina")
    equal(PixelType.snap(11, body: 13, scale: 1), 11, "and on a 1x screen")
    equal(PixelType.snap(11, body: 14, scale: 2), 16.5, "one step larger (target 11.8) goes up to 16.5, never back to 11")
    equal(PixelType.snap(11, body: 16, scale: 2), 16.5, "body 16 (target 13.5) is 16.5")
    equal(PixelType.snap(11, body: 20, scale: 2), 22, "body 20 (target 16.9) is 22")
    equal(PixelType.snap(11, body: 23, scale: 2), 22, "body 23 (target 19.5) is 22")
    equal(PixelType.snap(11, body: 29, scale: 2), 27.5, "body 29 (target 24.5) is 27.5")
    equal(PixelType.snap(11, body: 26, scale: 2), 22, "a target that is exactly sharp (22) stays")
    equal(PixelType.snap(11, body: 16, scale: 1), 22, "on 1x the next sharp size after 11 is 22")
    equal(PixelType.snap(11, body: 29, scale: 1), 33, "then 33")
    equal(PixelType.snap(11, body: 9, scale: 2), 11, "smaller system text never takes labels under 11")
    var down: [String] = [], blurry: [String] = [], tooBig: [String] = []
    for scale in [1.0, 2.0] { for body in bodies {
        let size = PixelType.snap(11, body: body, scale: scale), target = 11 * max(1, body / 13)
        if size < target - 0.001 { down.append("\(body)@\(scale)x") }
        let pixels = size * scale / 11
        if abs(pixels - pixels.rounded()) > 0.0001 || pixels < scale { blurry.append("\(body)@\(scale)x") }
        if size - 11 / scale >= target - 0.001 && size > 11 { tooBig.append("\(body)@\(scale)x") }
    } }
    check(down.isEmpty, "no text size rounds a label down: \(down.joined(separator: ", "))")
    check(blurry.isEmpty, "every size is a whole number of screen pixels per font pixel: \(blurry.joined(separator: ", "))")
    check(tooBig.isEmpty, "and is the next sharp size, not one beyond it: \(tooBig.joined(separator: ", "))")
    check(C(bodySize: 16, scale: 2).labelSize != C(bodySize: 16, scale: 1).labelSize, "a different screen scale snaps again")
    equal(PixelType.resolve(.screenTitle(26), C()).size, 27.5, "the screen title is 27.5 pt on Retina")
    equal(PixelType.resolve(.screenTitle(26), C(scale: 1)).size, 22, "and 22 pt on 1x")
    equal(PixelType.resolve(.screenTitle(26), C(bodySize: 16)).size, 33, "at body 16 (target 32) it is 33")
    equal(C().grow, 1, "controls are their usual size at the default text size")
    equal(C(bodySize: 16).grow, 1.5, "and grow by as much as the labels: 1.5 at 16.5 pt")
    equal(C(bodySize: 23).grow, 2, "2 at 22 pt")
    equal(C(on: false, bodySize: 16).grow, 16.0 / 13, "with the system font they grow with the body size")
    equal(C(on: false, bodySize: 11).grow, 1, "and never shrink under their usual size")

    section("Pixel type: which face each kind of text gets")
    let normal = C()
    equal(PixelType.resolve(.screenTitle(26), normal).face, .pixelify, "the screen title is Pixelify Sans")
    equal(PixelType.resolve(.screenTitle(26), normal).weight, .bold, "at weight 700")
    equal(PixelType.resolve(.display(28), normal).face, .pixelify, "Overview's status sentence is its screen title")
    for (name, role) in roles where ["sheet title", "heading", "label", "button", "number"].contains(name) {
        equal(PixelType.resolve(role, normal).face, .departure, "\(name): Departure Mono")
    }
    equal(PixelType.resolve(.body, normal).face, .system, "anything that wraps is the system font")
    equal(PixelType.resolve(.promptSentence, normal).face, .system, "the Allow prompt's sentence wraps, so it is the system font")
    equal(PixelType.resolve(.mono, normal).face, .systemMono, "logs and ids keep the system's fixed-width face")
    let heading = PixelType.resolve(.heading, normal)
    check(heading.caps && heading.tracking == 1, "card headings are capitals with one font pixel (1 pt at 11 pt) of extra spacing")
    equal(PixelType.resolve(.heading, C(bodySize: 16)).tracking, 1.5, "the spacing stays one font pixel at 16.5 pt")
    for (name, role) in roles where name != "heading" {
        for conditions in [normal, C(bodySize: 23), C(boldText: true), C(scale: 1), C(on: false)] {
            let drawn = PixelType.resolve(role, conditions)
            check(drawn.tracking == 0 && !drawn.caps, "\(name): no extra spacing and no capitals")
        }
    }

    section("Pixel type: Bold Text")
    let bold = C(boldText: true)
    // macOS makes every system font bolder itself under Bold Text. So the app asks for the weight each label had,
    // and nothing is thickened twice.
    let asked: [(String, PixelType.Role, PixelType.Weight)] = [("sheet title", .title(17), .semibold), ("heading", .heading, .bold), ("label", .label(.regular), .regular),
                                                               ("tab", .label(.medium), .medium), ("button", .label(.semibold), .semibold), ("number", .number, .regular)]
    for (name, role, weight) in asked {
        let drawn = PixelType.resolve(role, bold)
        equal(drawn.face, .system, "\(name): the system font, which macOS bolds")
        equal(drawn.weight, weight, "\(name): at the weight it had, so it isn't bolded twice")
        equal(drawn.weight, PixelType.resolve(role, C(on: false)).weight, "\(name): the same weight as with pixel type off")
    }
    equal(PixelType.resolve(.promptSentence, bold).weight, .semibold, "the Allow prompt's sentence keeps its weight too")
    check(PixelType.resolve(.number, bold).tabularDigits, "numbers keep digits of equal width")
    check(!PixelType.resolve(.heading, bold).caps, "a system-font heading isn't set in capitals")
    let boldTitle = PixelType.resolve(.screenTitle(26), bold)
    check(boldTitle.face == .pixelify && boldTitle.weight == .bold, "the title uses Pixelify Sans 700")
    equal(PixelType.resolve(.body, bold).weight, .regular, "wrapping text is left to the system, which bolds it itself")
    equal(bold.grow, 1, "controls keep their size")

    section("Pixel type: a 1x screen")
    equal(PixelType.resolve(.label(.regular), C(scale: 1)).face, .departure, "at the default text size labels are Departure Mono, one font pixel to a screen pixel")
    let oneLarge = C(bodySize: 16, scale: 1)
    for (name, role) in roles where ["sheet title", "heading", "label", "number"].contains(name) {
        equal(PixelType.resolve(role, oneLarge).face, .system, "\(name): the system font above the default size")
    }
    equal(PixelType.resolve(.label(.medium), oneLarge).weight, .medium, "at the weight it had")
    equal(PixelType.resolve(.label(.regular), oneLarge).size, 16, "at the system's size")
    equal(PixelType.resolve(.screenTitle(26), oneLarge).face, .pixelify, "the title keeps Pixelify Sans")
    equal(oneLarge.grow, 16.0 / 13, "controls grow with the system's text")

    section("Pixel type: the setting's default on a first launch")
    check(PixelType.firstLaunchDefault(bodySize: 13, boldText: false, screenScales: [2]), "on for a Retina Mac at the default text size")
    check(PixelType.firstLaunchDefault(bodySize: 13, boldText: false, screenScales: [1, 2]), "on when one of two screens is Retina")
    check(PixelType.firstLaunchDefault(bodySize: 11, boldText: false, screenScales: [2]), "on when text is smaller than the default")
    check(!PixelType.firstLaunchDefault(bodySize: 14, boldText: false, screenScales: [2]), "off when text is above the default")
    check(!PixelType.firstLaunchDefault(bodySize: 13, boldText: true, screenScales: [2]), "off with Bold Text")
    check(!PixelType.firstLaunchDefault(bodySize: 13, boldText: false, screenScales: [1, 1]), "off when every screen is 1x")
    check(!PixelType.firstLaunchDefault(bodySize: 13, boldText: false, screenScales: []), "off when no screen is known")
    if let (defaults, suite) = scratchDefaults("pixel") {
        defer { removeScratchSuite(suite) }
        check(PixelType.saved(defaults) == nil, "nothing is saved before the first launch")
        check(PixelType.load(defaults, bodySize: 13, boldText: false, screenScales: [2], remember: false), "a look without remembering says on")
        check(PixelType.saved(defaults) == nil, "and saves nothing")
        check(!PixelType.load(defaults, bodySize: 13, boldText: true, screenScales: [2]), "a first launch with Bold Text starts off")
        equal(defaults.object(forKey: PixelType.key) as? Bool, false, "and that is saved under the documented key")
        check(!PixelType.load(defaults, bodySize: 13, boldText: false, screenScales: [2]), "Bold Text turned off later doesn't flip the setting")
        PixelType.save(true, defaults)
        check(PixelType.load(defaults, bodySize: 20, boldText: true, screenScales: [1]), "the owner's own choice wins over every default rule")
    } else { check(false, "a scratch settings domain") }
    if let (defaults, suite) = scratchDefaults("pixel-on") {
        defer { removeScratchSuite(suite) }
        check(PixelType.load(defaults, bodySize: 13, boldText: false, screenScales: [2]), "a first launch on a Retina Mac starts on")
        check(PixelType.load(defaults, bodySize: 13, boldText: false, screenScales: [1]), "and a 1x monitor plugged in later doesn't turn it off")
    } else { check(false, "a scratch settings domain") }

    section("Pixel type: off uses no pixel face anywhere")
    var pixelWhenOff: [String] = [], changed: [String] = []
    for (name, role) in roles { for body in bodies { for scale in [1.0, 2.0] { for boldText in [false, true] {
        let drawn = PixelType.resolve(role, C(on: false, bodySize: body, boldText: boldText, scale: scale))
        if drawn.isPixel || drawn.caps || drawn.tracking != 0 { pixelWhenOff.append("\(name) at \(body)") }
    } } } }
    check(pixelWhenOff.isEmpty, "every kind of text, at every text size, on both screens, with and without Bold Text: \(pixelWhenOff.joined(separator: ", "))")
    let off = C(on: false)
    // Off is the look from before the pixel type: the system's text styles, and the display face where it was.
    let before: [(String, PixelType.Role, PixelType.Face, Double, PixelType.Weight)] = [
        ("screen title", .screenTitle(26), .system, 26, .semibold), ("status sentence", .display(28), .lilita, 28, .regular),
        ("prompt sentence", .promptSentence, .lilita, 19, .regular), ("sheet title", .title(17), .system, 17, .semibold),
        ("heading", .heading, .system, 13, .bold), ("label", .label(.regular), .system, 13, .regular), ("button", .label(.semibold), .system, 13, .semibold),
        ("number", .number, .system, 13, .regular), ("body", .body, .system, 13, .regular), ("log", .mono, .systemMono, 13, .regular),
    ]
    for (name, role, face, size, weight) in before {
        let drawn = PixelType.resolve(role, off)
        if drawn.face != face || drawn.size != size || drawn.weight != weight { changed.append(name) }
    }
    check(changed.isEmpty, "off is the look from before: the system's styles, and Lilita One on the two sentences. Changed: \(changed.joined(separator: ", "))")
    equal(PixelType.resolve(.label(.regular), C(on: false, boldText: true)).weight, .regular, "off leaves Bold Text to the system, as before")
    let type = source("Type.swift"), settings = source("AppModel.swift")
    check(settings.contains("Toggle(\"Pixel font\", isOn: Binding(get: { TypeState.shared.on }") && settings.contains("PixelType.save(on)"), "Settings has the Pixel font switch, and it is saved")
    // The hint is held to what off does: the system font for the four things it names, and no promise about the rest.
    equal(PixelType.settingHint, "Headings, labels, buttons and numbers use a pixel typeface. Turn this off to use the system font for them. It starts off when text is larger than the default, Bold Text is on, or the Mac has no Retina screen.", "the hint's words, with its last sentence about the first-launch default")
    check(settings.contains("Hint(PixelType.settingHint)") && !settings.contains("system font everywhere"), "Settings shows that hint, and nowhere says the system font is used everywhere")
    for (name, role) in roles where ["heading", "label", "button", "number"].contains(name) {
        check(PixelType.resolve(role, normal).isPixel && PixelType.resolve(role, off).face == .system, "\(name): a pixel typeface when on and the system font when off, as the hint says")
    }
    check(PixelType.resolve(.display(28), off).face == .lilita && PixelType.resolve(.promptSentence, off).face == .lilita, "off keeps Lilita One on the status sentence, a player's name and the Allow sentence, which is why the hint doesn't say everywhere")
    check(type.contains("PixelType.load(bodySize: bodySize, boldText: boldText, screenScales: Self.screenScales, remember: true)"), "the first window settles the first-launch default, once it knows about Bold Text")
    check(type.contains(".onChange(of: displayScale) { report() }") && type.contains(".onChange(of: legibilityWeight) { report() }"), "a change of screen scale or Bold Text is reported, so sizes snap again")
    check(settings.contains("if !AppModel.isSnapshot { PixelType.save(on) }") && type.contains("guard !fixed else { return }"), "a snapshot saves nothing")

    section("Pixel type: font files that don't load")
    let departureFile = repo.appendingPathComponent("brand/fonts/departuremono/DepartureMono-Regular.otf")
    let pixelifyFile = repo.appendingPathComponent("brand/fonts/pixelifysans/PixelifySans[wght].ttf")
    let scratchFonts = folder("pixel-fonts")
    let broken = scratchFonts.appendingPathComponent("Broken.otf")
    write("this is not a font\n", broken)
    check(!FontFiles.isAvailable("MadeUpFace-Regular"), "a face that isn't there is reported as not there")
    check(!FontFiles.register([scratchFonts.appendingPathComponent("Missing.otf")], postScriptName: "MadeUpFace-Regular"), "a missing file is a plain no")
    check(!FontFiles.register([broken], postScriptName: "MadeUpFace-Regular"), "so is a file that isn't a font")
    check(FontFiles.coverage(of: broken) == nil, "and it has no characters")
    check(FontFiles.register([broken, departureFile], postScriptName: PixelType.departureName), "a broken first candidate is skipped and the next one loads")
    check(FontFiles.register([pixelifyFile], postScriptName: PixelType.pixelifyName), "Pixelify Sans loads from brand/fonts")
    check(FontFiles.isAvailable(PixelType.departureName) && FontFiles.isAvailable(PixelType.pixelifyName), "both faces answer to the names the app asks for")
    var lost: [String] = []
    for (name, role) in roles { for body in [13.0, 16, 23] {
        let drawn = PixelType.resolve(role, C(departureLoaded: false, pixelifyLoaded: false, bodySize: body))
        if drawn.isPixel || drawn.caps || drawn.size < 11 { lost.append(name) }
    } }
    check(lost.isEmpty, "with neither face loaded every kind of text is the system font at a readable size: \(lost.joined(separator: ", "))")
    equal(PixelType.resolve(.label(.regular), C(departureLoaded: false)).face, .system, "without Departure Mono, labels are the system font")
    equal(PixelType.resolve(.screenTitle(26), C(departureLoaded: false)).face, .pixelify, "and the title still has its face")
    equal(PixelType.resolve(.screenTitle(26), C(pixelifyLoaded: false)).face, .system, "without Pixelify Sans, the title is the system font")
    check(type.contains("BrandFonts.pixel(PixelType.departureName, size: size, weight: nil) ?? system()") && type.contains("BrandFonts.pixel(PixelType.pixelifyName, size: size, weight: 700) ?? system()"),
          "a face that can't be made at draw time falls back to the system font")
    check(type.contains(".cascadeList: [NSFont.systemFont(ofSize: size).fontDescriptor]"), "and each pixel font names the system font for any character it lacks")
    let desert = source("DesertViews.swift")
    check(desert.contains("FontFiles.register(candidates, postScriptName: name)") && settings.contains("BrandFonts.register()\n        TypeState.shared.start()"), "the fonts are registered once at launch, before anything is drawn")

    section("Pixel type: every label's characters are in its face")
    guard let departure = FontFiles.coverage(of: departureFile), let pixelify = FontFiles.coverage(of: pixelifyFile) else { check(false, "the two font files can be read"); return }
    func has(_ set: CharacterSet) -> (Unicode.Scalar) -> Bool { { set.contains($0) } }
    equal(PixelType.missing(in: "Open Software 0123456789 (1) … · × ?", covered: has(departure)), [], "Departure Mono has letters, digits and the punctuation labels use")
    equal(PixelType.missing(in: "⇧ ⌃ ✓ ▾", covered: has(departure)), ["⇧", "⌃", "✓", "▾"], "it lacks ⇧ ⌃ ✓ and ▾, read from its character map")
    for sign in ["⇧", "⌃", "✓", "▾", "→", "←", "↑", "↓", "⌘", "⌥"] { check(PixelType.symbols.contains(Character(sign)), "\(sign) is always set in the system font") }
    let runs = PixelType.runs("Made-up Server ▾")
    check(runs.count == 2 && runs[0].text == "Made-up Server " && !runs[0].symbol && runs[1].text == "▾" && runs[1].symbol, "the helper cuts a label into its words and its signs")
    equal(PixelType.runs("⇧⌘R restarts").map(\.symbol), [true, false], "signs side by side are one run")
    check(type.contains("PixelType.runs(text).reduce(Text(\"\"))") && type.contains("run.symbol ? .system(size: token.size) : token.font"), "SymbolText draws the signs in the system font")
    // The names the app shows as labels straight from its models.
    var titles: [String] = Sections.all.map(\.title) + LabStation.allCases.map(\.title) + AppModule.allCases.map(\.title)
    titles += [ServerState.running, .starting, .stopping, .stopped, .crashed(code: 1), .external(pid: 1)].map(\.title)
    let badTitles = titles.filter { !PixelType.missing(in: $0, covered: has(departure)).isEmpty || $0.contains(where: PixelType.symbols.contains) }
    check(titles.count > 15 && badTitles.isEmpty, "section, check, feature and state names: \(badTitles.joined(separator: ", "))")
    // Every string written on a line that sets a pixel face, in the app's own source.
    let scan = PixelLabelScan(departure: departure, pixelify: pixelify)
    var problems: [String] = [], lines = 0, files = 0
    for file in (try? FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "swift" {
        files += 1
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let result = scan.read(String(line))
            if result.isLabel { lines += 1 }
            if !result.missing.isEmpty { problems.append("\(file.lastPathComponent):\(n + 1) \(String(result.missing))") }
        }
    }
    check(files > 20 && lines > 150, "read the app's label strings (\(lines) lines in \(files) files)")
    check(problems.isEmpty, "no label in a pixel face has a character the face lacks, or a sign outside SymbolText: \(problems.joined(separator: "; "))")
    equal(String(scan.read(#"Text("Restart ⇧⌘R").type(.label())"#).missing), "⇧⌘", "the rule catches signs in a plain label")
    equal(String(scan.read(#"Button("Done ✓") { close() }.buttonStyle(.themed)"#).missing), "✓", "and a tick on a button")
    equal(String(scan.read(#"Page(title: "Résumé ☃") {"#).missing), "☃", "and a character Pixelify Sans lacks in a screen title")
    check(scan.read(#"SymbolText("\(name) ▾", .label())"#).missing.isEmpty, "the same sign through SymbolText passes")
    check(scan.read(#".helped("Restart the server (⇧⌘R)")"#).missing.isEmpty && !scan.read(#"Hint("Players → Add")"#).isLabel, "tooltips and wrapping text are the system font, so they aren't labels")
    check(desert.contains("SymbolText(ServerName.sidebarLines(server.displayName).joined(separator: \"\\n\") + \" ▾\", .label())"), "the server switcher's triangle goes through SymbolText")
    // The names K824 added follow the same rules: a label under the icon, the headline as the screen's title, the
    // one-line folder name as a label, and the switcher's rows in the system font, as the system's menu is.
    check(desert.contains(".lineLimit(2).truncationMode(.tail).frame(maxWidth: 70 * Theme.grow)"), "the name under the icon keeps its two lines, in a column that grows with the text")
    check(ServerName.sidebarLine * 7 <= 70, "a line of that name fits its column in Departure Mono (7 pt a letter at 11 pt)")
    check(source("OverviewPage.swift").contains("Text(server.headline)\n                    .type(.display(28))"), "the headline with the server's name is the screen's title")
    check(source("OverviewPage.swift").contains("Text(folder).type(.label()).foregroundStyle(Theme.muted).lineLimit(1)"), "the Folder line is a one-line label")
    check(desert.contains("Text(SwitcherRow.title(server)).type(.body)") && desert.contains("Text(server.folderName).type(.body)"), "the switcher's rows are the system font, as its menu is")

    section("Pixel type: headings read as written, and the server's name stays whole")
    let theme = source("Theme.swift"), prompts = source("SessionPrompts.swift")
    check(type.contains("Text(text).type(fact ? TypeToken.factHeading : TypeToken.headline).accessibilityLabel(text)") && theme.contains("HeadingText(title)") && theme.contains("HeadingText(text).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)")
          && desert.contains("HeadingText(title, fact: true)"), "card, group and fact headings give VoiceOver the title as written, not its capitals")
    // Every heading in capitals goes through HeadingText: no other view asks for the headline or fact-heading style.
    var strays: [String] = []
    let appSources = repo.appendingPathComponent("Sources/GilaMonster")
    for file in (try? FileManager.default.contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "swift" && file.lastPathComponent != "Type.swift" {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if text.contains(".type(.headline)") || text.contains(".type(.factHeading)") { strays.append(file.lastPathComponent) }
    }
    check(strays.isEmpty, "no heading is set in capitals outside HeadingText: \(strays.joined(separator: ", "))")
    // The owner's own data is never put in capitals: case matters in a world, a pack, a config section or a service.
    check(theme.contains("var titleIsData = false") && source("ResourcePacksPage.swift").contains("Card(title: pack.title, systemImage: \"eye\", titleIsData: true)"), "a pack's name as a card title is shown as written")
    check(source("WorldsPage.swift").contains("Text(world.title).type(.dataHeading)") && source("ConfigsPage.swift").contains("Text(section.name).type(.dataHeading)") && source("ConnectionsCard.swift").contains(".type(.dataHeading)"), "world, config section and service names are shown as written")
    check(type.contains("static var dataHeading: TypeToken { label(.bold) }") && !PixelType.resolve(.label(.bold), C(on: true)).caps, "the data heading style is never in capitals, pixel type on or off")
    let quit = source("QuitDuringBackup.swift")
    check(quit.contains("Text(state.reason.backupHeading).type(.title(15, .title3))") && !quit.contains("Text(state.reason.backupHeading).type(.headline)"), "the quit-during-backup sentence is a sentence, set as written and not in capitals")
    check(theme.contains(".accessibilityValue(configuration.isExpanded ? \"Expanded\" : \"Collapsed\")") && source("LabViews.swift").contains("open ? \"Expanded\" : \"Collapsed\""), "disclosure rows say Expanded or Collapsed")
    check(!theme.contains(".frame(minHeight: 20 * Theme.grow)") && theme.contains(".frame(minHeight: 24 * Theme.grow)") && source("LabViews.swift").contains(".frame(width: 24 * Theme.grow, height: 24 * Theme.grow).contentShape(Rectangle())"), "disclosure rows and the Lab's arrow are at least 24 pt to press")
    check(source("LabViews.swift").contains("@FocusState private var focused: Bool") && source("LabViews.swift").contains(".focused($focused)\n            .overlay { if focused { RoundedRectangle(cornerRadius: Theme.controlRadius + 2).strokeBorder(Theme.accent, lineWidth: 2)"), "the Upgrade field shows a focus ring")
    check(source("LabViews.swift").contains("Text(\"Restart log, \\(lines.count) \\(lines.count == 1 ? \"line\" : \"lines\")\").type(.label())"), "the Restart log's short label is in the label face")
    check(type.contains("configuration.textFieldStyle(.roundedBorder)") && !type.contains("configuration.textFieldStyle(.growing)"), "the growing field is the system's rounded field at the default size and never itself (it recursed to a crash)")
    var fixedWidths: [String] = []
    for file in (try? FileManager.default.contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "swift" {
        for (n, line) in ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains(".frame(width: 4") || line.contains(".frame(width: 5") || line.contains(".frame(width: 3") {
            if !line.contains("Theme.sheet(") && !line.contains("grow") && !line.contains("Theme.grow") && (line.contains("width: 480)") || line.contains("width: 520)") || line.contains("width: 440)") || line.contains("width: 420)") || line.contains("width: 460)") || line.contains("width: 500)") || line.contains("width: 380)") || line.contains("width: 360)") || line.contains("width: 400)")) { fixedWidths.append("\(file.lastPathComponent):\(n + 1)") }
        }
    }
    check(fixedWidths.isEmpty, "no sheet has a fixed width that larger text can't grow: \(fixedWidths.joined(separator: ", "))")
    check(type.contains("font(token.font).tracking(CGFloat(token.resolved.tracking)).textCase(.uppercase)") && type.components(separatedBy: ".tracking(").count == 2, "extra spacing is applied in one place, for headings only")
    let cut = PixelType.split("helper wants to stop A Long Made-up Name", around: "A Long Made-up Name")
    check(cut?.before == "helper wants to stop" && cut?.after == "", "a long name is cut out whole, for a line to itself")
    check(PixelType.split("helper wants to stop it", around: "Made-up Server") == nil, "a sentence without the name isn't cut")
    check(prompts.contains("Text(server).type(.prompt).fixedSize(horizontal: false, vertical: true)") && !prompts.contains(".truncationMode(.middle)") && !prompts.contains(".lineLimit(1).truncationMode")
          && prompts.contains(".accessibilityLabel(sentence)") && prompts.contains("AskSentence(sentence: ask.sentence, server: ask.server)"), "the prompt wraps the name, never cuts it, and VoiceOver gets the plain sentence")
    check(prompts.contains("AskRow {") && prompts.contains("maxWidth: widest ?? AskPanelSize.shared.widest") && prompts.contains("SessionAskPlacement.contentWidth(ideal: ideal.width, visible: visible)"), "the window is never wider than the screen, and the buttons move under the words when it is narrow")
    equal(SessionAskPlacement.contentWidth(ideal: 900, visible: 700), 700, "the window's content is capped to the usable screen")
    equal(SessionAskPlacement.contentWidth(ideal: 580, visible: 1400), 580, "and keeps its own width when the screen has room")
    check(SessionAskPlacement.sideBySide(width: 600, wordsAtLeast: 200, buttons: 150, gap: 12) && !SessionAskPlacement.sideBySide(width: 300, wordsAtLeast: 200, buttons: 150, gap: 12), "buttons sit beside the words only when both fit")
    let split1 = PixelType.split("helper wants to stop A Very Long Made-up Realm Name Here", around: "A Very Long Made-up Realm Name Here")
    check(split1?.after == "" && split1?.before == "helper wants to stop", "the name is cut out whole, for lines of its own")
    check(!PixelType.settingHint.isEmpty && PixelType.settingHint.hasSuffix("or the Mac has no Retina screen."), "the hint keeps its last sentence, about when it starts off")

    section("Pixel type: controls grow with the text")
    let lab = source("LabViews.swift"), overview = source("OverviewPage.swift")
    check(theme.contains("static var controlHeight: CGFloat { 32 * grow }") && theme.contains(".padding(.horizontal, 12 * Theme.grow)"), "buttons: height and padding")
    check(theme.contains(".frame(width: 40 * grow, height: 22 * grow)") && theme.contains(".frame(width: 16 * grow, height: 16 * grow).padding(3 * grow)") && theme.contains(".frame(width: 9 * grow, height: 10 * grow)"), "the switch: track, knob and lock")
    check(lab.contains("UpgradePicker(chosen: $chosen, versions: versions).frame(maxWidth: 200 * Theme.grow)") && lab.contains("Text(chosen.isEmpty ? \"Choose…\" : chosen).font(Theme.symbol())") && lab.contains(".accessibilityLabel(\"Version to upgrade to\")"), "the Upgrade picker: its field, words and arrows, still named for VoiceOver")
    check(type.contains(".disclosureGroupStyle(ThemedDisclosureStyle())") && theme.contains("Image(systemName: \"chevron.right\").font(Theme.symbol(weight: .semibold)).imageScale(.small)") && theme.contains(".accessibilityValue(configuration.isExpanded ? \"Expanded\" : \"Collapsed\")") && theme.contains(".rotationEffect(.degrees(open ? 90 : 0))"), "disclosure arrows, in every window, and VoiceOver hears expanded or collapsed")
    check(lab.contains("Image(systemName: icon).font(Theme.symbol())") && lab.contains("Image(systemName: \"chevron.right\").font(Theme.symbol())") && theme.contains("Image(systemName: symbol).font(Theme.symbol(weight: .semibold))"), "status symbols and chevrons")
    check(desert.contains(".frame(width: size * Theme.grow, height: size * Theme.grow)") && desert.contains(".frame(width: 76 * Theme.grow)"), "status glyphs and the sidebar")
    check(overview.contains("WrapRow {\n                Button(\"Open Software\")") && type.contains("Overflow.flowRows(") && type.contains("struct WrapRow: Layout"),
          "Open Software and Open Plugins sit side by side when they fit and stack only when they don't")
    check(settings.contains("!overflowing.contains(where: { $0.hasPrefix(\"OVERFLOW \\(page.rawValue):\") })"), "the overflow report names a page once, though Players is drawn twice")
    var raw: [String] = []
    for name in (try? FileManager.default.contentsOfDirectory(atPath: app.path)) ?? [] where name.hasSuffix(".swift") && name != "InviteTicketView.swift" && name != "Type.swift" {
        for (n, line) in source(name).split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where line.contains(".font(.") && !line.contains("type-exempt") { raw.append("\(name):\(n + 1)") }
    }
    check(raw.isEmpty, "no view sets a system text style of its own, so every text follows the setting and the text size: \(raw.joined(separator: ", "))")

    section("Pixel type: the fonts and their licences are in brand/ and in the app")
    let fonts = repo.appendingPathComponent("brand/fonts")
    let licence = (try? String(contentsOf: fonts.appendingPathComponent("departuremono/OFL.txt"), encoding: .utf8)) ?? ""
    check(licence.contains("SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007") && licence.contains("Copyright 2022–2024 Helena Zhang"), "Departure Mono's licence is the SIL Open Font License 1.1, with its copyright line")
    let lilita = (try? String(contentsOf: fonts.appendingPathComponent("lilitaone/OFL.txt"), encoding: .utf8)) ?? ""
    func terms(_ text: String) -> String { (text.range(of: "PREAMBLE").map { String(text[$0.lowerBound...]) } ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    check(!terms(licence).isEmpty && terms(licence) == terms(lilita), "its terms are word for word the OFL already in brand/fonts")
    let digest = (try? Data(contentsOf: departureFile)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
    equal(digest, "4d53f663155cf8bf7ffc8e688776e719625f7bbb80a8d90073438b249261a2e0", "the font file is Departure Mono 1.500 as downloaded")
    check((try? String(contentsOf: fonts.appendingPathComponent("pixelifysans/OFL.txt"), encoding: .utf8))?.contains("SIL Open Font License, Version 1.1") == true, "Pixelify Sans has its OFL beside it")
    let build = (try? String(contentsOf: repo.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)) ?? ""
    for copied in ["cp brand/fonts/departuremono/DepartureMono-Regular.otf \"$app/Contents/Resources/Fonts/\"", "cp brand/fonts/departuremono/OFL.txt \"$app/Contents/Resources/Fonts/DepartureMono-OFL.txt\"",
                   "cp \"brand/fonts/pixelifysans/PixelifySans[wght].ttf\" \"$app/Contents/Resources/Fonts/\"", "cp brand/fonts/pixelifysans/OFL.txt \"$app/Contents/Resources/Fonts/PixelifySans-OFL.txt\"",
                   "cp brand/fonts/lilitaone/OFL.txt \"$app/Contents/Resources/Fonts/LilitaOne-OFL.txt\""] {
        check(build.contains(copied), "build-app.sh: \(copied.split(separator: " ")[1])")
    }
}

/// Reads one line of the app's source: whether it sets text in a pixel face, and which of its characters that face
/// can't draw. A sign from `PixelType.symbols` counts as missing too, unless the line draws it with SymbolText.
struct PixelLabelScan {
    let departure: CharacterSet
    let pixelify: CharacterSet
    /// What marks a line as a label in Departure Mono, and as a screen title in Pixelify Sans.
    static let labelMarks = [".type(.label", ".type(.headline", ".type(.factHeading", ".type(.number", ".type(.value", ".type(.title(1", "Button(\"", "Badge(text: \"", "Fact(label: \"",
                             "Card(title: \"", "FactCard(title: \"", "GroupHeading(\"", "SheetTitle(\"", "Toggle(\"", "Label(\"", "case ."]
    static let titleMarks = [".type(.title(2", ".type(.display(", "Page(title: \"", "PageHeading(title: \""]
    private static let literal = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)

    func read(_ line: String) -> (isLabel: Bool, missing: [Character]) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//") else { return (false, []) }
        let title = Self.titleMarks.contains { line.contains($0) }
        // `case .x: "Words"` is how page and state names are written in the app.
        let label = Self.labelMarks.contains { $0 == "case ." ? trimmed.hasPrefix("case .") && trimmed.contains(": \"") : line.contains($0) }
        guard title || label else { return (false, []) }
        guard !line.contains("SymbolText(") else { return (true, []) }
        var text = ""
        for match in Self.literal.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let range = Range(match.range(at: 1), in: line) else { continue }
            // Tooltips, hints and VoiceOver words on the same line are the system's, not the label's.
            let lead = line[..<range.lowerBound]
            if [".help(", ".helped(", ".accessibilityLabel(", ".accessibilityHint(", ".accessibilityValue(", "Announcer.say(", "Hint(", "systemImage: ", "systemName: "].contains(where: { lead.hasSuffix($0) }) { continue }
            text += line[range]
        }
        let face = title && !label ? pixelify : departure
        var missing = PixelType.missing(in: text.replacingOccurrences(of: "\\u{00A0}", with: " "), covered: { face.contains($0) })
        for sign in text where PixelType.symbols.contains(sign) && !missing.contains(sign) { missing.append(sign) }
        return (true, missing)
    }
}
