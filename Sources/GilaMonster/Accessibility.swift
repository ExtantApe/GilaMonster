import AppKit
import GilaMonsterCore
import SwiftUI

/// Spoken messages for VoiceOver, for things that appear without anyone moving focus to them: a notice, a problem, a
/// request waiting, a job starting or ending. Nothing happens when VoiceOver is off.
@MainActor enum Announcer {
    /// Said once per distinct text within a few seconds, so a view that redraws doesn't repeat itself.
    private static var recent: [String: Date] = [:]
    /// What's already on a page when it opens is read by VoiceOver as the page; only what appears afterwards is
    /// announced. The first moments of a page, and of the app, are quiet.
    private static var quietUntil = Date().addingTimeInterval(Overflow.quietAtLaunch)

    static func pageChanged() { quietUntil = Date().addingTimeInterval(Overflow.quietAfterPageChange) }

    /// `force` skips the quiet moment, for things the owner just did or that need saying now. `always` also says it
    /// when the same words were said a moment ago: an outcome, such as a second no in a row, is news each time.
    static func say(_ text: String, urgent: Bool = false, force: Bool = false, always: Bool = false) {
        let now = Date()
        if !force, !always, now < quietUntil { return }
        recent = recent.filter { now.timeIntervalSince($0.value) < 5 }
        guard always || recent[text] == nil, !text.isEmpty else { return }
        recent[text] = now
        let priority: NSAccessibilityPriorityLevel = urgent ? .high : .medium
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: priority.rawValue])
    }
}

extension Tone {
    /// The word a callout of this tone is announced with.
    var announcement: (prefix: String, urgent: Bool) {
        switch self {
        case .danger: ("Problem", true)
        case .warning: ("Warning", false)
        case .good: ("Done", false)
        case .info: ("Notice", false)
        case .neutral: ("Note", false)
        }
    }
}
