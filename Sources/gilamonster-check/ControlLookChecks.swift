import Foundation
import GilaMonsterCore

/// The switch GilaMonster draws itself and the disabled button (K801): each part held to WCAG in both themes, all four
/// appearances and every color vision, what VoiceOver reads, and that the Lab's rows and Run Checks use them.
@MainActor func controlLookChecks() {
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    func source(_ name: String) -> String { (try? String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    func held(_ fg: String, on bg: String, _ use: Palette.Use, _ what: String, line: Int = #line) {
        guard let low = Palette.lowest(fg, on: bg, use: use) else { check(false, "\(what): \(fg) and \(bg) are palette colors", line: line); return }
        check(low.passes, "\(what): \(fg) on \(bg) is \(String(format: "%.2f", low.ratio)):1 at its lowest", line: line)
    }

    section("Switch: the knob is at one end, in colors that hold up")
    let on = ControlLook.switchParts(on: true, enabled: true), off = ControlLook.switchParts(on: false, enabled: true)
    let lockedOn = ControlLook.switchParts(on: true, enabled: false), lockedOff = ControlLook.switchParts(on: false, enabled: false)
    check(on.knobTrailing && lockedOn.knobTrailing, "on puts the knob at the trailing end, locked or not")
    check(!off.knobTrailing && !lockedOff.knobTrailing, "off puts it at the leading end, locked or not")
    check(on.lock == nil && off.lock == nil, "a switch that can be changed shows no lock")
    check(lockedOn.lock != nil && lockedOff.lock != nil, "a locked switch shows a lock, on or off")
    check(on.track != off.track && lockedOn.track != lockedOff.track, "on and off have different tracks as well as different knob ends")
    check(lockedOn.track != on.track, "locked on is drawn differently from on")
    for (name, look) in [("on", on), ("off", off), ("locked on", lockedOn), ("locked off", lockedOff)] {
        held(look.knob, on: look.track, .ui, "\(name): the knob on its track")
        if let lock = look.lock { held(lock, on: look.track, .ui, "\(name): the lock on its track") }
        // The track is seen against the page by its outline, which is its fill when the track is filled.
        for ground in ControlLook.grounds where ground != look.edge { held(look.edge, on: ground, .ui, "\(name): the track's edge") }
    }
    check(Palette.lowest("made-up", on: "surface", use: .ui) == nil, "a color name the palette doesn't have isn't passed by default")
    check(Palette.lowest("border", on: "surface", use: .ui) == nil, "the faint card border isn't a color a control may use")

    section("Switch: what VoiceOver reads")
    equal(ControlLook.switchValue(on: true, enabled: true), "On", "on")
    equal(ControlLook.switchValue(on: false, enabled: true), "Off", "off")
    equal(ControlLook.switchValue(on: true, enabled: false, lockedBecause: "locked while a run is going"), "On, locked while a run is going", "on and locked, with why")
    equal(ControlLook.switchValue(on: false, enabled: false), "Off, locked", "off and locked")

    section("Lab: its switches and Run Checks")
    let lab = source("LabViews.swift"), theme = source("Theme.swift")
    check(lab.contains(".toggleStyle(.themedSwitch(lockedBecause: \"locked while a run is going\")).disabled(lab.isBusy)"), "each check's switch is GilaMonster's own, locked while a run is going")
    check(!lab.contains(".toggleStyle(.switch)"), "the Lab has no system switch left")
    check(lab.contains(".accessibilityLabel(\"Include \\(station.title) in the next run\")"), "and is named for its check")
    check(theme.contains("ControlLook.switchParts(on: isOn, enabled: enabled)") && theme.contains(".accessibilityAddTraits(.isToggle)")
          && theme.contains(".accessibilityValue(ControlLook.switchValue(on: isOn, enabled: enabled, lockedBecause: lockedBecause))"), "the switch is drawn from those parts and read as a switch with its value")
    check(theme.contains("Button { configuration.isOn.toggle() } label: { configuration.label }"), "it is a button underneath, so Space and a click both flip it")
    check(theme.contains("Circle().fill(Theme.named(look.knob)).frame(width: 16, height: 16).padding(3)"), "the knob has its own size, so it sits at its end and not in the middle")
    check(theme.contains("if !enabled && isOn { Capsule().strokeBorder(Theme.named(look.knob), style: StrokeStyle(lineWidth: 1, dash: [3, 2])).padding(2) }"), "locked on shows dashes inside its gray track, in the knob's color")
    check(theme.contains("if focused { Capsule().strokeBorder(Theme.accent, lineWidth: 2).padding(-3) }"), "with a focus ring")
    check(lab.contains("Button(\"Run Checks\") { runChecks() }\n                            .buttonStyle(.themedPrimary)\n                            .disabled(lab.isBusy || included.isEmpty)"), "Run Checks is the themed main button, disabled during a run or with nothing ticked")

    section("Disabled buttons: their own colors, at 4.5:1 or better")
    let look = ControlLook.disabledButton
    held(look.label, on: look.fill, .text, "the label")
    for flavor in Palette.Flavor.allCases {
        for mode in [Palette.Mode.light, .dark] {
            let ratio = Palette.contrast(Palette.named[look.label]!.hex(mode, flavor), Palette.named[look.fill]!.hex(mode, flavor))
            check(ratio >= 4.5, "\(flavor.rawValue) \(mode.rawValue): a disabled button's label is \(String(format: "%.2f", ratio)):1 on its fill")
        }
    }
    for ground in ControlLook.grounds { held(look.edge, on: ground, .ui, "the dashed outline") }
    // What it replaced: the main button at half strength over a card.
    func blend(_ a: UInt32, _ b: UInt32) -> UInt32 {
        var out: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] { out |= (((a >> shift) & 0xFF) + ((b >> shift) & 0xFF)) / 2 << shift }
        return out
    }
    let before = Palette.contrast(blend(Palette.onPop.hex(.light), Palette.surface.hex(.light)), blend(Palette.pop.hex(.light), Palette.surface.hex(.light)))
    check(before < 4.5, "the old half-strength main button was \(String(format: "%.2f", before)):1 in Bold light, under 4.5:1")
    check(theme.contains("guard enabled else { return Theme.named(ControlLook.disabledButton.label) }") && theme.contains("guard enabled else { return Theme.named(ControlLook.disabledButton.fill) }")
          && theme.contains("guard enabled else { return Theme.named(ControlLook.disabledButton.edge) }"), "a disabled themed button uses those colors")
    check(theme.contains(".opacity(enabled && configuration.isPressed ? 0.8 : 1)") && !theme.contains(".opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)"), "and is no longer faded to half strength")
    check(theme.contains("dash: enabled ? [] : [4, 3]"), "its outline is dashed, so it isn't told apart by color alone")
}
