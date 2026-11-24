import CoreGraphics
import Foundation

/// Where and when the session ask window gets the owner's attention (K679 follow-up, 2026-11-17).
///
/// On 2026-11-17 three asks timed out while the owner sat at the Mac. The log showed why: every GilaMonster
/// notification was held back by the scheduled Sleep Focus ("muted by DND suppression", no sound), and macOS turns
/// time-sensitive down for a locally signed build, so the notification never helped. The ask window did open each
/// time, but it was small, silent and stayed on whichever of the two screens it was first opened on. So the window
/// now moves to the screen the pointer is on, every time, and GilaMonster plays its own sound (which a Focus doesn't
/// mute) when an ask arrives and once more with a minute left.
public enum SessionAskPlacement {
    /// Gap between the top of the usable screen area and the window.
    public static let topGap: CGFloat = 48

    /// The window's frame: centered across the top of the screen the pointer is on, inside that screen's usable area
    /// (below the menu bar, clear of the Dock). Falls back to the first screen when the pointer is on none of them.
    /// Coordinates are AppKit's, with y growing upward.
    public static func frame(size: CGSize, pointer: CGPoint, screens: [(frame: CGRect, visible: CGRect)]) -> CGRect? {
        guard let screen = screens.first(where: { $0.frame.contains(pointer) }) ?? screens.first else { return nil }
        let area = screen.visible
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        let x = area.minX + (area.width - width) / 2
        let y = max(area.minY, area.maxY - topGap - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }

    /// When the reminder sound plays for an ask: one minute before the deadline, if that is at least 20 seconds after
    /// it was asked. Nil when the wait is too short for a second sound to mean anything.
    public static func reminder(asked: Date, deadline: Date) -> Date? {
        let at = deadline.addingTimeInterval(-60)
        return at.timeIntervalSince(asked) >= 20 ? at : nil
    }

    /// The click guard on Allow and Deny (K721): a click in the moment after the rows change is ignored, so a row that
    /// lapses and lets the next one move up under the pointer can't take a click meant for the old one. A key press
    /// can't land on the wrong row that way, so only pointer clicks wait.
    public static let clickGuard: TimeInterval = 0.8
    public static func accepts(pointer: Bool, sinceChange: TimeInterval) -> Bool { !pointer || sinceChange > clickGuard }
}
