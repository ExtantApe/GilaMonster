import AppKit
import GilaMonsterCore
import SwiftUI

// Quitting during a backup (owner, 2026-11-15, D215): "if you quit, restart, log out or shut down while a backup runs,
// GilaMonster asks first and shows progress and time left." Wait quits when it's done; Cancel and quit stops it and
// deletes only that run's unfinished file; Keep using cancels the quit.

enum QuitChoice: Equatable { case wait, cancelAndQuit, keepUsing }

extension QuitReason {
    /// The question's heading.
    var backupHeading: String {
        switch self {
        case .user: "A backup is still running"
        case .shutdown: "Your Mac is shutting down, but a backup is still running"
        case .restart: "Your Mac is restarting, but a backup is still running"
        case .logout: "You're logging out, but a backup is still running"
        }
    }
}

@MainActor @Observable final class QuitDuringBackupState {
    var reason: QuitReason
    var progress: [BackupProgress] = []
    var waiting = false
    var now = Date()
    init(reason: QuitReason, progress: [BackupProgress] = []) { self.reason = reason; self.progress = progress }
}

struct QuitDuringBackupView: View {
    let state: QuitDuringBackupState
    let choose: (QuitChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // A whole sentence, so it is set as written and wraps (K820 review): never in capitals.
            Text(state.reason.backupHeading).type(.title(15, .title3)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(state.progress.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.words(now: state.now)).foregroundStyle(Theme.ink)
                    if let f = p.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                }
                .accessibilityElement(children: .combine)
            }
            if state.waiting {
                Text("GilaMonster quits as soon as it's done. Running servers are stopped with a save first.")
                    .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Quitting now would stop it part way. Wait to finish it, then quit. Or cancel it: only this backup's unfinished file is deleted, and your earlier backups stay. Either way, running servers are stopped with a save.")
                    .foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            // Each button is as wide as its label, and the row wraps when the three don't fit (K820 review: two of
            // them were cut short at the default text size).
            WrapRow(trailing: true) {
                Button("Keep Using GilaMonster") { choose(.keepUsing) }
                    .keyboardShortcut(.cancelAction).fixedSize()
                Button("Cancel Backup and Quit", role: .destructive) { choose(.cancelAndQuit) }.fixedSize()
                if !state.waiting {
                    Button("Wait, Then Quit") { choose(.wait) }.keyboardShortcut(.defaultAction).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: Theme.sheet(480))
        .background(Theme.background)
    }
}

/// Shows the question in a panel of its own, keeps the progress current, and answers once.
@MainActor final class QuitDuringBackup {
    private static var current: QuitDuringBackup?
    private let state: QuitDuringBackupState
    private var panel: NSPanel?
    private var timer: Timer?
    private var answers: [(QuitChoice) -> Void]

    private init(reason: QuitReason, done: @escaping (QuitChoice) -> Void) {
        state = QuitDuringBackupState(reason: reason, progress: Backups.running())
        answers = [done]
    }

    /// Asks, unless no backup is running, which answers `.cancelAndQuit` at once (there's nothing to cancel).
    /// `.wait` is answered only once every backup has finished. A second quit while it's open joins the first.
    static func ask(_ reason: QuitReason, done: @escaping (QuitChoice) -> Void) {
        guard Backups.writing else { done(.cancelAndQuit); return }
        if let current {
            current.answers.append(done)
            current.panel?.makeKeyAndOrderFront(nil)
            return
        }
        let asker = QuitDuringBackup(reason: reason, done: done)
        current = asker
        asker.show()
    }

    private func show() {
        let host = NSHostingView(rootView: QuitDuringBackupView(state: state) { [weak self] in self?.chose($0) }.tint(Theme.accent))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Quit GilaMonster"
        panel.contentView = host
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        state.now = Date()
        state.progress = Backups.running()
        // Done: the quit that was asked for goes ahead, whether or not Wait was clicked.
        if state.progress.isEmpty { finish(.wait) }
        else if let panel, let host = panel.contentView { panel.setContentSize(host.fittingSize) }
    }

    private func chose(_ choice: QuitChoice) {
        switch choice {
        case .wait: state.waiting = true
        case .cancelAndQuit: Backups.cancelInFlight(); finish(.cancelAndQuit)
        case .keepUsing: finish(.keepUsing)
        }
    }

    private func finish(_ choice: QuitChoice) {
        timer?.invalidate()
        panel?.orderOut(nil)
        Self.current = nil
        let all = answers
        answers = []
        all.forEach { $0(choice) }
    }
}
