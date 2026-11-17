import CoreGraphics
import Foundation
@testable import LeafJuiceCore

/// The ask window lands where the owner is looking, and the reminder sound comes with a minute left (2026-11-17).
@MainActor func sessionAskPlacementChecks() {
    section("Session asks: where the window opens")
    // Two side-by-side ultrawide screens, as on the owner's desk. The left one has the menu bar.
    let left = (frame: CGRect(x: 0, y: 0, width: 3440, height: 1440), visible: CGRect(x: 0, y: 70, width: 3440, height: 1345))
    let right = (frame: CGRect(x: 3440, y: 0, width: 3440, height: 1440), visible: CGRect(x: 3440, y: 0, width: 3440, height: 1415))
    let size = CGSize(width: 520, height: 180)
    let onRight = SessionAskPlacement.frame(size: size, pointer: CGPoint(x: 5000, y: 700), screens: [left, right])
    check(onRight.map { right.visible.contains($0) } == true, "pointer on the right screen: the window opens on the right screen")
    equal(onRight?.midX, right.visible.midX, "centered across that screen")
    equal(onRight?.maxY, right.visible.maxY - SessionAskPlacement.topGap, "near the top, below the menu bar")
    let onLeft = SessionAskPlacement.frame(size: size, pointer: CGPoint(x: 100, y: 100), screens: [left, right])
    check(onLeft.map { left.visible.contains($0) } == true, "pointer moves to the left screen: the next ask opens there")
    let nowhere = SessionAskPlacement.frame(size: size, pointer: CGPoint(x: -9000, y: -9000), screens: [left, right])
    check(nowhere.map { left.visible.contains($0) } == true, "pointer on no screen: the first screen, not off-screen")
    let tiny = (frame: CGRect(x: 0, y: 0, width: 400, height: 150), visible: CGRect(x: 0, y: 0, width: 400, height: 150))
    let squeezed = SessionAskPlacement.frame(size: size, pointer: .zero, screens: [tiny])
    check(squeezed.map { tiny.visible.contains($0) } == true, "a screen smaller than the window: it shrinks to fit, all of it visible")
    check(SessionAskPlacement.frame(size: size, pointer: .zero, screens: []) == nil, "no screens: no frame (nothing to place)")

    section("Session asks: the reminder sound")
    let asked = Date(timeIntervalSince1970: 1_000_000)
    equal(SessionAskPlacement.reminder(asked: asked, deadline: asked.addingTimeInterval(120)), asked.addingTimeInterval(60), "2-minute wait: the reminder plays with a minute left")
    check(SessionAskPlacement.reminder(asked: asked, deadline: asked.addingTimeInterval(70)) == nil, "70-second wait: no second sound 10 seconds after the first")
}
