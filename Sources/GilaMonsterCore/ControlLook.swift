import Foundation

/// Which palette colors a switch and a disabled button are drawn in, as names, so `gilamonster-check` can hold each
/// pair to WCAG without the app (K801). The app's Theme turns the names into colors.
///
/// The Lab's check switches used the system switch, which the owner saw drawn half on: a teal track with the knob in
/// the middle. GilaMonster now draws the switch itself, so the knob is always at one end, and a switch that can't be
/// changed keeps its end and wears a lock.
public enum ControlLook {
    public struct Switch: Equatable, Sendable {
        /// The track's fill.
        public let track: String
        /// The track's outline. Dashed when the switch is locked.
        public let edge: String
        public let knob: String
        /// The lock drawn in the track's empty half when the switch is locked. Nil when it can be changed.
        public let lock: String?
        /// True when the knob sits at the trailing end.
        public let knobTrailing: Bool
    }

    /// The four looks. On is a filled track with the knob at the trailing end; off is an outlined track with the knob
    /// at the leading end. Locked keeps the knob where it is, swaps the accent for the muted text color, dashes the
    /// outline and adds the lock, so it reads as on or off and as unavailable without relying on color.
    public static func switchParts(on: Bool, enabled: Bool) -> Switch {
        switch (on, enabled) {
        case (true, true): Switch(track: "accent", edge: "accent", knob: "surface", lock: nil, knobTrailing: true)
        case (false, true): Switch(track: "surface", edge: "controlBorder", knob: "controlBorder", lock: nil, knobTrailing: false)
        case (true, false): Switch(track: "muted", edge: "muted", knob: "surface", lock: "surface", knobTrailing: true)
        case (false, false): Switch(track: "raised", edge: "controlBorder", knob: "controlBorder", lock: "muted", knobTrailing: false)
        }
    }

    /// What VoiceOver reads as the switch's value: "On", "Off", or with why it can't be changed, "On, locked while a
    /// run is going".
    public static func switchValue(on: Bool, enabled: Bool, lockedBecause: String = "locked") -> String {
        let state = on ? "On" : "Off"
        return enabled ? state : "\(state), \(lockedBecause)"
    }

    /// A disabled button: muted words on the raised fill with a dashed control outline. It used to be the enabled
    /// button at half strength, which left the main button's label near 2:1.
    public static let disabledButton = (label: "muted", fill: "raised", edge: "controlBorder")

    /// The pages a control can sit on.
    public static let grounds = ["background", "surface", "raised"]
}

extension Palette {
    /// The colors ControlLook names.
    public static let named: [String: Swatch] = [
        "background": background, "surface": surface, "raised": raised, "accent": accent, "muted": muted,
        "controlBorder": controlBorder, "ink": ink,
    ]

    /// The lowest contrast between two named colors across both themes, all four appearances and every color vision,
    /// and whether it meets the minimum for that use in every one of them.
    public static func lowest(_ foreground: String, on background: String, use: Use) -> (ratio: Double, passes: Bool)? {
        guard let fg = named[foreground], let bg = named[background] else { return nil }
        var low = Double.infinity, passes = true
        for flavor in Flavor.allCases {
            for mode in Mode.allCases {
                for vision in Vision.allCases {
                    let r = contrast(simulate(fg.hex(mode, flavor), vision), simulate(bg.hex(mode, flavor), vision))
                    low = min(low, r)
                    if r < use.minimum(mode) { passes = false }
                }
            }
        }
        return (low, passes)
    }
}
