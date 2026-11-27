import Foundation
import Observation

// Waiting on the Keychain, where the owner can see it (K809). GilaMonster isn't signed, so after an update macOS asks
// again before handing over anything this app saved. On 2026-11-26 that password window sat behind other windows for
// about 40 minutes, with nothing in the app to say so and session access not answering. Every Keychain call that can
// ask a person now runs through here: off the main thread, and with a banner once it has waited a couple of seconds.

@MainActor @Observable
public final class KeychainWait {
    public static let shared = KeychainWait()

    /// What the call is for, which is also what waits.
    public enum Purpose: String, Sendable, CaseIterable, Comparable {
        case sessionToken, advisorKey
        public static func < (a: Purpose, b: Purpose) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
    }

    /// How long a call may take before the banner shows. A read that needs nobody's answer comes back in milliseconds.
    public var threshold: TimeInterval = 2

    /// Calls that haven't come back yet, and those of them that have passed the threshold.
    private var pending: [UUID: Purpose] = [:]
    private var overdue: Set<UUID> = []
    /// What was refused, until it works again or the owner dismisses it.
    public private(set) var denied: Set<Purpose> = []

    /// Set by the app: called once when the banner turns on, and once when it turns off.
    @ObservationIgnored public var onShown: (@MainActor ([Purpose]) -> Void)?
    @ObservationIgnored public var onCleared: (@MainActor () -> Void)?

    public init() {}

    /// True while any call has waited longer than the threshold. The banner follows this.
    public var isWaiting: Bool { !overdue.isEmpty }
    /// What the overdue calls are for, session access first.
    public var waitingOn: [Purpose] { Set(overdue.compactMap { pending[$0] }).sorted() }
    /// True from the moment a call starts, whether or not the banner shows yet.
    public func isPending(_ purpose: Purpose) -> Bool { pending.values.contains(purpose) }

    /// Marks a call as started. `end` must follow, whatever happens.
    public func begin(_ purpose: Purpose) -> UUID {
        let id = UUID()
        pending[id] = purpose
        let wait = threshold
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000))
            self?.passedThreshold(id)
        }
        return id
    }

    private func passedThreshold(_ id: UUID) {
        guard pending[id] != nil else { return }
        let wasWaiting = isWaiting
        overdue.insert(id)
        if !wasWaiting { onShown?(waitingOn) }
    }

    /// Marks a call as finished, however it ended.
    public func end(_ id: UUID) {
        let wasWaiting = isWaiting
        pending[id] = nil
        overdue.remove(id)
        if wasWaiting, !isWaiting { onCleared?() }
    }

    /// Records that the Keychain refused, or that it has worked since.
    public func setDenied(_ purpose: Purpose, _ refused: Bool) {
        if refused { denied.insert(purpose) } else { denied.remove(purpose) }
    }

    /// Runs one Keychain call on a background thread of its own and waits for it without holding the main thread.
    /// The call may sit on a macOS password window for as long as the owner takes.
    public func run<T: Sendable>(_ purpose: Purpose, _ work: @escaping @Sendable () -> T) async -> T {
        let id = begin(purpose)
        let value: T = await withCheckedContinuation { done in
            // A plain thread, never one of Swift's few task threads: a long wait there would starve other work.
            let thread = Thread { done.resume(returning: work()) }
            thread.name = "GilaMonster Keychain call"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        end(id)
        return value
    }

    // MARK: Words

    public static let title = "GilaMonster is waiting for you to allow Keychain access"

    /// The banner's second line: where to look, then what waits.
    public static func detail(_ purposes: [Purpose]) -> String {
        var parts = ["Look for a macOS password window. It may be behind other windows."]
        let session = purposes.contains(.sessionToken), advisor = purposes.contains(.advisorKey)
        if session && advisor { parts.append("Session access and the Advisor's key wait until you answer.") }
        else if advisor { parts.append("The Advisor's key waits until you answer.") }
        else { parts.append("Session access waits until you answer.") }
        return parts.joined(separator: " ")
    }

    /// The Mac notification, for when GilaMonster isn't in front.
    public static let notificationID = "gilamonster-keychain-wait"
    public static func notificationBody(_ purposes: [Purpose]) -> String { detail(purposes) }

    /// Whether a notification may be posted: only when macOS already allows them (2 allowed, 3 allowed quietly, as
    /// UNAuthorizationStatus counts) and the owner hasn't turned Mac alerts off. Nobody is asked for this.
    public static func mayNotify(authorization: Int, alertsOn: Bool) -> Bool {
        alertsOn && (authorization == 2 || authorization == 3)
    }

    public static let deniedTitle = "Keychain access wasn't allowed"
    /// What won't work after a no.
    public static func deniedDetail(_ purpose: Purpose) -> String {
        switch purpose {
        case .sessionToken: "Session access is off, so sessions on this Mac can't check status or run commands. Everything else works as usual."
        case .advisorKey: "The Advisor can't open its list of code names, so it can't check a server. Everything else works as usual."
        }
    }
}
