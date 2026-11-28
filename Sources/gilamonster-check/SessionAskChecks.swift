import CoreGraphics
import Foundation
@testable import GilaMonsterCore

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

    section("Session asks: an open window that grows (K820 recheck)")
    let open = CGRect(x: 4000, y: 900, width: 580, height: 200)   // on the right screen
    let screens = [left, right]
    let grown = SessionAskPlacement.resized(open, to: CGSize(width: 580, height: 260), screens: screens)
    equal(grown, CGRect(x: 4000, y: 840, width: 580, height: 260), "it grows downward: same screen, top edge, left edge and width")
    // The pointer has since gone to the other screen. Nothing here asks where it is.
    equal(grown.flatMap { SessionAskPlacement.area(of: $0, screens: screens) }, right.visible, "and stays on the window's own screen")
    equal(SessionAskPlacement.resized(open, to: CGSize(width: 580, height: 160), screens: screens)?.maxY, open.maxY, "shrinking keeps the top edge too")
    equal(SessionAskPlacement.resized(open, to: CGSize(width: 580, height: 5000), screens: screens), CGRect(x: 4000, y: 0, width: 580, height: 1100), "taller than the room below: it stops at the screen's usable bottom, top edge unmoved")
    let low = CGRect(x: 100, y: -50, width: 580, height: 200)
    equal(SessionAskPlacement.resized(low, to: CGSize(width: 580, height: 260), screens: screens), low, "dragged below the screen: it isn't made shorter, and the top edge stays")
    let wider = SessionAskPlacement.resized(CGRect(x: 6200, y: 900, width: 580, height: 200), to: CGSize(width: 700, height: 200), screens: screens)
    check(wider.map { right.visible.contains($0) } == true, "a new width keeps it inside the screen")
    check(SessionAskPlacement.resized(open, to: open.size, screens: []) == nil, "no screens: no new frame")
    let prompts = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster/SessionPrompts.swift"), encoding: .utf8)) ?? ""
    let resize = prompts.range(of: "    private func resize() {").flatMap { from in prompts.range(of: "\n    }\n", range: from.upperBound..<prompts.endIndex).map { String(prompts[from.lowerBound..<$0.upperBound]) } } ?? ""
    check(resize.contains("SessionAskPlacement.resized(panel.frame") && resize.contains("panel.setFrame(frame, display: true)") && resize.contains("AskPanelSize.shared.moved = Date()"), "the window is sized again, and the click guard reset, when its content changes")
    check(!resize.isEmpty && !["makeKey", "activate", "orderFront", "askPanelFocus", "makeFirstResponder", "mouseLocation", "defaultButtonCell"].contains(where: resize.contains), "sizing it again takes no focus, brings nothing forward and doesn't look for the pointer")
    check(prompts.contains(".onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { [weak self] frame in self?.contentChanged(frame) }"), "the content says when its size changes")
    check(prompts.contains(".frame(minHeight: 0, maxHeight: .infinity, alignment: .top)"), "on a screen too short for it all, the top of the prompt and the name stay in view")
    check(prompts.contains(".onChange(of: service.waiting.map { $0.extensions >= SessionAccessService.maxExtensions }) { AskPanelSize.shared.moved = Date() }"), "a row running out of time resets the guard without moving focus")

    section("Session asks: the reminder sound")
    let asked = Date(timeIntervalSince1970: 1_000_000)
    equal(SessionAskPlacement.reminder(asked: asked, deadline: asked.addingTimeInterval(120)), asked.addingTimeInterval(60), "2-minute wait: the reminder plays with a minute left")
    check(SessionAskPlacement.reminder(asked: asked, deadline: asked.addingTimeInterval(70)) == nil, "70-second wait: no second sound 10 seconds after the first")

    section("Session asks: the click guard")
    check(!SessionAskPlacement.accepts(pointer: true, sinceChange: 0.2), "a pointer click just after the rows change is ignored")
    check(SessionAskPlacement.accepts(pointer: true, sinceChange: 1.0), "a pointer click after the guard counts")
    check(SessionAskPlacement.accepts(pointer: false, sinceChange: 0.0), "a key press goes straight through: it can't land on the wrong row")
}
