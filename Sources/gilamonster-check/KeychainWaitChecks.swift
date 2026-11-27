import Foundation
@testable import GilaMonsterCore
import Security

/// A stand-in for a Keychain read that waits on a person. It blocks its thread until `release`, as the real call does
/// while the macOS password window is up. No real Keychain is touched, so nothing here can make macOS ask anyone.
final class BlockingKeychain: @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var answer: SessionAccess.TokenRead = .failed(errSecIO)
    private var calls = 0
    private var mainThreadCalls = 0
    private var created: [Bool] = []

    /// The read itself. Called on whatever thread the app picks, which is the thing being checked.
    func read(create: Bool) -> SessionAccess.TokenRead {
        lock.lock(); calls += 1; created.append(create); if Thread.isMainThread { mainThreadCalls += 1 }; lock.unlock()
        gate.wait()
        lock.lock(); defer { lock.unlock() }
        return answer
    }

    /// The person answers the password window.
    func release(_ with: SessionAccess.TokenRead) {
        lock.lock(); answer = with; lock.unlock()
        gate.signal()
    }

    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var ranOnMainThread: Bool { lock.lock(); defer { lock.unlock() }; return mainThreadCalls > 0 }
    var askedToCreate: [Bool] { lock.lock(); defer { lock.unlock() }; return created }
}

/// A Keychain wait is never silent (K809): the banner turns on after the threshold and off when the call returns, the
/// main thread stays free, a no is said plainly, and a session that asks during the wait is refused with the reason.
@MainActor func keychainWaitChecks() async {
    section("Keychain wait: the banner's state")
    func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    let wait = KeychainWait()
    equal(wait.threshold, 2, "the banner waits two seconds, so an ordinary read never shows it")
    wait.threshold = 0.3
    var shown: [[KeychainWait.Purpose]] = []
    var cleared = 0
    wait.onShown = { shown.append($0) }
    wait.onCleared = { cleared += 1 }

    let quick = await wait.run(.sessionToken) { 7 }
    await pause(0.5)
    check(quick == 7 && !wait.isWaiting && shown.isEmpty && cleared == 0, "a call that comes straight back never shows the banner, even after the threshold has passed")

    // A longer threshold for the blocking part, so a slow CI machine can't pass it before the "not yet" look.
    wait.threshold = 2
    let slow = BlockingKeychain()
    let started = Date()
    let reading = Task { await wait.run(.sessionToken) { slow.read(create: false) } }
    await checkUntil(5, "the blocking stand-in was called") { slow.callCount == 1 }
    check(!slow.ranOnMainThread, "and not on the main thread, which went on running this check while it blocked")
    if Date().timeIntervalSince(started) < 1.5 {
        check(wait.isPending(.sessionToken) && !wait.isWaiting && shown.isEmpty, "before the threshold: pending, and no banner yet")
    } else {
        print("  note: the machine took over 1.5 s to start the read, so the before-the-threshold look was skipped")
    }
    await checkUntil(8, "after the threshold the banner turns on") { wait.isWaiting }
    equal(wait.waitingOn, [.sessionToken], "and it knows what's waiting")
    equal(shown, [[.sessionToken]], "the app is told once, for its one notification and its spoken line")

    // A second slow call while the first still waits: the same banner, and no second notification.
    let second = BlockingKeychain()
    let readingToo = Task { await wait.run(.advisorKey) { second.read(create: false) } }
    await checkUntil(5, "a second slow call joins the same banner, session access named first") { wait.waitingOn == [.sessionToken, .advisorKey] }
    equal(shown.count, 1, "with no second notification")
    second.release(.missing)
    _ = await readingToo.value
    check(wait.isWaiting && cleared == 0, "one of two coming back leaves the banner up")
    slow.release(.token("made-up-token"))
    equal(await reading.value, .token("made-up-token"), "the call's answer comes back unchanged")
    check(!wait.isWaiting && wait.waitingOn.isEmpty && !wait.isPending(.sessionToken), "the banner goes when the last call returns")
    equal(cleared, 1, "and the app is told once, to take its notification away")

    // A wait that ends before its threshold, followed by a later one: the first one's timer mustn't show the second early.
    let begun = wait.begin(.advisorKey)
    wait.end(begun)
    await pause(0.5)
    check(!wait.isWaiting && shown.count == 1, "a call that finished in time leaves nothing behind when its timer fires")

    equal(wait.banners, [], "with nothing waiting and nothing refused, there's no banner")

    section("Keychain wait: how it ended is said, and a retry keeps its banner")
    let told = KeychainWait()
    told.threshold = 0.3
    var outcomes: [KeychainWait.Outcome] = []
    var toldShown = 0
    told.onOutcome = { outcomes.append($0) }
    told.onShown = { _ in toldShown += 1 }
    _ = await told.run(.sessionToken) { 1 }
    told.report(.allowed)
    equal(outcomes, [], "an ordinary launch, where the token comes straight back, says nothing")
    var held = BlockingKeychain()
    var holding = Task { await told.run(.sessionToken) { [held] in held.read(create: true) } }
    await checkUntil(5, "a wait the owner is shown") { told.banners == [.waiting([.sessionToken])] }
    held.release(.token("made-up"))
    _ = await holding.value
    told.report(.allowed)
    equal(outcomes, [.allowed], "allowed after a wait that was shown: said")
    told.report(.allowed)
    equal(outcomes, [.allowed], "and only once")
    told.report(.denied)
    told.report(.denied)
    equal(outcomes, [.allowed, .denied, .denied], "a no is said every time, a second one in a row too")
    equal(told.banners, [.denied(retrying: false)], "after a no: the denied banner, with its button ready")
    toldShown = 0
    held = BlockingKeychain()
    holding = Task { await told.run(.sessionToken) { [held] in held.read(create: true) } }
    await checkUntil(5, "the retry starts") { held.callCount == 1 }
    equal(told.banners, [.denied(retrying: true)], "during a retry the same banner stays, as waiting, so its buttons and the focus don't vanish")
    await pause(0.6)
    equal(told.banners, [.denied(retrying: true)], "and past the threshold there's still one banner, not a second one beside it")
    equal(toldShown, 0, "with no second spoken line or notification for the retry the owner just pressed")
    let other = BlockingKeychain()
    let otherHolding = Task { await told.run(.advisorKey) { other.read(create: false) } }
    await checkUntil(5, "another wait during a retry gets its own banner") { told.banners == [.waiting([.advisorKey]), .denied(retrying: true)] }
    other.release(.missing)
    _ = await otherHolding.value
    held.release(.token("made-up"))
    _ = await holding.value
    told.report(.allowed)
    check(outcomes.last == .allowed && outcomes.count == 4 && told.banners.isEmpty, "allowed on the retry: said, and the banner goes")
    told.report(.failed)
    check(outcomes.last == .failed && told.banners.isEmpty, "a failed read is said too, and isn't shown as a no")
    equal(KeychainWait.spoken(.allowed), "Keychain access allowed. Session access is on.", "the words for allowed")
    equal(KeychainWait.spoken(.denied), "Keychain access wasn't allowed. Session access is off.", "for a no")
    equal(KeychainWait.spoken(.failed), "GilaMonster couldn't read the Keychain. Session access is off.", "and for a failure")
    equal(KeychainWait.spokenWait, "GilaMonster is waiting for you to allow Keychain access. Look for a macOS password window. It may be behind other windows.", "the spoken line for a wait says where to look")
    check(KeychainWait.spokenRetry.hasSuffix(KeychainWait.whereToLook) && KeychainWait.retryDetail.hasPrefix(KeychainWait.whereToLook), "and so do the retry's line and banner")
    equal(KeychainWait.retryButton, "Try Keychain Again", "the retry button says what it retries")
    #if DEBUG
    let drawn = KeychainWait()
    var drawnTold = 0
    drawn.onShown = { _ in drawnTold += 1 }
    drawn.preview(waiting: [.sessionToken, .advisorKey])
    equal(drawn.banners, [.waiting([.sessionToken, .advisorKey])], "the snapshot's made-up wait shows the waiting banner")
    let refusedDrawn = KeychainWait()
    refusedDrawn.preview(denied: [.sessionToken])
    equal(refusedDrawn.banners, [.denied(retrying: false)], "and its made-up no shows the denied one")
    await pause(0.1)
    equal(drawnTold, 0, "neither tells the app, so no notification is posted for a picture")
    #endif

    section("Keychain wait: the words")
    let words = [KeychainWait.title, KeychainWait.deniedTitle, KeychainWait.spokenWait, KeychainWait.retryTitle, KeychainWait.retryDetail, KeychainWait.spokenRetry, KeychainWait.retryButton]
        + [.allowed, .denied, .failed].map(KeychainWait.spoken) + KeychainWait.Purpose.allCases.map(KeychainWait.deniedDetail)
        + [[.sessionToken], [.advisorKey], [.sessionToken, .advisorKey]].map(KeychainWait.detail)
        + [SessionAccess.Refusal.keychainWait.message]
    check(words.allSatisfy { !$0.contains("\u{2014}") && !$0.contains("\u{2013}") && !$0.isEmpty }, "plain sentences, no dashes")
    check(KeychainWait.title.contains("waiting for you to allow Keychain access"), "the title says who is waited for, and for what")
    check(KeychainWait.detail([.sessionToken]).contains("macOS password window") && KeychainWait.detail([.sessionToken]).contains("behind other windows"), "the detail says where to look")
    check(KeychainWait.detail([.sessionToken]).contains("Session access waits") && !KeychainWait.detail([.sessionToken]).contains("Advisor"), "and names only what's really waiting: session access")
    check(KeychainWait.detail([.advisorKey]).contains("Advisor's key waits") && !KeychainWait.detail([.advisorKey]).contains("Session access"), "or the Advisor's key")
    check(KeychainWait.detail([.sessionToken, .advisorKey]).contains("Session access and the Advisor's key wait"), "or both")
    check(KeychainWait.deniedDetail(.sessionToken).contains("Session access is off") && KeychainWait.deniedDetail(.sessionToken).contains("can't check status or run commands"), "after a no, it says what won't work")
    check(SessionAccess.Refusal.keychainWait.message.contains("waiting for Keychain access on the Mac") && SessionAccess.Refusal.keychainWait.message.contains("Nothing was done"), "a session is told it's a wait on the Mac, and that nothing was done")

    section("Keychain wait: the Mac notification")
    equal([0, 1, 2, 3, 4, 99].map { KeychainWait.mayNotify(authorization: $0, alertsOn: true) }, [false, false, true, true, false, false],
          "posted only when macOS already allows notifications: never when not asked yet, turned off, or unknown")
    check(!KeychainWait.mayNotify(authorization: 2, alertsOn: false), "and never with Mac alerts turned off in Settings")

    section("Keychain wait: what a Keychain answer means for the token")
    equal(SessionAccess.tokenRead(status: errSecSuccess, data: Data("made-up".utf8)), .token("made-up"), "a token read is a token")
    equal(SessionAccess.tokenRead(status: errSecSuccess, data: Data()), .failed(errSecSuccess), "an empty one is a failure, never a token")
    equal(SessionAccess.tokenRead(status: errSecItemNotFound, data: nil), .missing, "none there is missing, the only case a new token is made for")
    for status in [errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem] {
        equal(SessionAccess.tokenRead(status: status, data: nil), .denied, "a no (\(status)) is a no, and no new token is made to get around it")
    }
    equal(SessionAccess.tokenRead(status: errSecInteractionNotAllowed, data: nil), .failed(errSecInteractionNotAllowed), "anything else is a failure")
    // The real code against a throwaway keychain file: made when missing, read back, and left alone when only reading.
    let (keychainPath, _) = throwawayKeychain("keychain-wait")
    var kc: SecKeychain?
    if SecKeychainOpen(keychainPath, &kc) == errSecSuccess, let kc {
        equal(SessionAccess.readToken(create: false, keychain: kc), .missing, "a real keychain with no token: missing, and none made when only reading")
        let made = SessionAccess.readToken(create: true, keychain: kc)
        if case let .token(value) = made { equal(value.count, 64, "with create, one is made") } else { check(false, "with create, one is made: \(made)") }
        equal(SessionAccess.readToken(create: true, keychain: kc), made, "and the next read gets the same one, not another")
    } else {
        check(false, "couldn't open the throwaway keychain")
    }

    section("Keychain wait: session access while the token is waited for")
    let root = folder("keychain-wait-server")
    write("server-port=25597\nserver-ip=127.0.0.1\nmotd=made up\n", root.appendingPathComponent("server.properties"))
    guard let server = try? await ServerController.adopt(root: root, name: "Made-up Waiting") else { check(false, "couldn't adopt a made-up server"); return }
    var on = SessionAccessSettings(); on.enabled = true
    try? SessionAccess.saveSettings(on)
    defer { try? SessionAccess.saveSettings(SessionAccessSettings()) }
    let socketPath = "/private/tmp/gm-kcwait-\(getpid()).sock"
    defer { try? FileManager.default.removeItem(atPath: socketPath) }
    let token = "made-up-token-fedcba9876543210"

    var spoken: [KeychainWait.Outcome] = []
    func service(_ keychain: BlockingKeychain, log name: String) -> SessionAccessService {
        let s = SessionAccessService()
        s.keychainWait = KeychainWait()
        s.keychainWait.threshold = 0.3
        s.keychainWait.onOutcome = { said in spoken.append(said) }
        s.tokenReader = { keychain.read(create: $0) }
        s.logFile = folder(name).appendingPathComponent("calls.jsonl")
        s.servers = { [server] }
        return s
    }
    /// One request over the real socket, as a session's program sends it.
    func send(_ json: String) async -> [String: Any] {
        let reply: Data = await withCheckedContinuation { done in
            Thread.detachNewThread {
                let s = socket(AF_UNIX, SOCK_STREAM, 0)
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                withUnsafeMutableBytes(of: &address.sun_path) { raw in
                    let bytes = Array(socketPath.utf8)
                    for (i, b) in bytes.enumerated() { raw[i] = b }
                    raw[bytes.count] = 0
                }
                let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
                guard connected == 0 else { close(s); done.resume(returning: Data()); return }
                var timeout = timeval(tv_sec: 5, tv_usec: 0)
                setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let body = Data((json + "\n").utf8)
                _ = body.withUnsafeBytes { Darwin.write(s, $0.baseAddress, $0.count) }
                var reply = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = read(s, &buffer, buffer.count)
                    if n <= 0 { break }
                    reply.append(contentsOf: buffer[0..<n])
                }
                close(s)
                done.resume(returning: reply)
            }
        }
        return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] ?? [:]
    }
    func status(_ t: String?) -> String {
        t.map { #"{"token":"\#($0)","caller":"Made-up Session","call":"status"}"# } ?? #"{"caller":"Made-up Session","call":"status"}"#
    }
    func said(_ r: [String: Any]) -> String { r["error"] as? String ?? "" }

    // The owner hasn't answered yet.
    var keychain = BlockingKeychain()
    var s = service(keychain, log: "keychain-wait-log-1")
    var applying = Task { await s.apply(on, path: socketPath) }
    await checkUntil(5, "turning session access on reads the token") { keychain.callCount == 1 }
    check(!keychain.ranOnMainThread, "off the main thread")
    equal(keychain.askedToCreate, [true], "making one if there's none")
    check(s.waitingForKeychain && s.isListening && s.cachedToken == nil, "while it waits, the socket is open and there's no token in hand")
    var r = await send(status(token))
    check(r["ok"] as? Bool == false && said(r).contains("waiting for Keychain access on the Mac"), "a session asking during the wait is told why, with the right token: \(said(r))")
    check(r["servers"] == nil, "and gets nothing else")
    r = await send(status("any-other-token"))
    check(r["ok"] as? Bool == false && said(r).contains("waiting for Keychain access on the Mac") && r["servers"] == nil, "the same with any other token: nothing can be checked, so nothing is allowed")
    r = await send(#"{"token":"\#(token)","caller":"Made-up Session","call":"run","command":"save-all"}"#)
    check(r["ok"] as? Bool == false && said(r).contains("waiting for Keychain access on the Mac") && r["sent"] == nil, "a listed command isn't sent")
    r = await send(#"{"token":"\#(token)","caller":"Made-up Session","call":"stop"}"#)
    check(r["ok"] as? Bool == false && said(r).contains("waiting for Keychain access on the Mac") && s.waiting.isEmpty, "an action isn't put to the owner")
    equal(said(await send(status(nil))), SessionAccess.Refusal.noToken.message, "a request with no token still hears that")
    equal(said(await send("not json")), SessionAccess.Refusal.unreadable.message, "and an unreadable one hears that")
    equal(keychain.callCount, 1, "none of those went back to the Keychain, so no second password window is queued")
    await checkUntil(5, "the banner is on after the threshold") { s.keychainWait.isWaiting }
    let refusedLog = SessionAccess.recentLog(20, from: s.logFile!)
    check(refusedLog.count == 6 && refusedLog.allSatisfy { !$0.allowed }, "every call during the wait is on the record as refused")
    check(refusedLog.contains { $0.note == SessionAccess.Refusal.keychainWait.message }, "with the reason")
    check(!((try? String(contentsOf: s.logFile!, encoding: .utf8)) ?? "").contains(token), "and never the token")

    // The owner allows it.
    keychain.release(.token(token))
    await applying.value
    check(!s.keychainWait.isWaiting && !s.waitingForKeychain, "allowed: the banner goes")
    check(s.isListening && s.cachedToken == token && s.error == nil && s.keychainWait.denied.isEmpty, "and session access is listening with the token")
    equal(spoken, [.allowed], "and that's said, once")
    r = await send(status(token))
    check(r["ok"] as? Bool == true && (r["servers"] as? [[String: Any]])?.first?["name"] as? String == "Made-up Waiting", "the right token now answers")
    equal(said(await send(status("any-other-token"))), SessionAccess.Refusal.badToken.message, "and a wrong one is refused as wrong")
    await s.apply(on, path: socketPath)
    equal(keychain.callCount, 1, "turning it on again doesn't go back to the Keychain")
    await s.apply(SessionAccessSettings())
    check(!s.isListening && !FileManager.default.fileExists(atPath: socketPath), "turned off, the socket is gone")

    // The owner says no.
    keychain = BlockingKeychain()
    s = service(keychain, log: "keychain-wait-log-2")
    applying = Task { await s.apply(on, path: socketPath) }
    await checkUntil(5, "a second wait shows the banner again") { s.keychainWait.isWaiting }
    keychain.release(.denied)
    await applying.value
    check(!s.keychainWait.isWaiting, "denied: the waiting banner goes")
    check(s.keychainWait.denied == [.sessionToken], "and the denied message takes its place")
    equal(spoken, [.allowed, .denied], "the no is said")
    check(!s.isListening && !FileManager.default.fileExists(atPath: socketPath) && s.cachedToken == nil, "nothing listens and there's no token: a no is never worked around")
    check(s.error?.contains("didn't let GilaMonster read its session token") == true, "Settings says so too: \(s.error ?? "nothing")")
    r = await send(status(token))
    check(r.isEmpty, "a session finds nobody there")
    equal(keychain.callCount, 1, "the Keychain was asked once, not again behind the owner's back")
    // Try Again asks once more; this time the answer is yes.
    applying = Task { await s.apply(on, path: socketPath) }
    await checkUntil(5, "Try Again asks the Keychain once more") { keychain.callCount == 2 }
    keychain.release(.token(token))
    await applying.value
    check(s.isListening && s.keychainWait.denied.isEmpty && s.error == nil, "allowed this time: listening, and the denied message is gone")
    equal(spoken, [.allowed, .denied, .allowed], "and the yes is said, though this read came back fast")
    await s.apply(SessionAccessSettings())

    // A read that fails some other way closes the socket too.
    keychain = BlockingKeychain()
    s = service(keychain, log: "keychain-wait-log-3")
    applying = Task { await s.apply(on, path: socketPath) }
    await checkUntil(5, "a third read starts") { keychain.callCount == 1 }
    keychain.release(.failed(errSecIO))
    await applying.value
    check(!s.isListening && s.cachedToken == nil && s.error?.contains("couldn't read its session token") == true && s.keychainWait.denied.isEmpty, "a failed read: nothing listens, and it isn't called a no")
    equal(spoken.last, .failed, "it's said as a failure")
    keychain.release(.token(""))
    await s.apply(on, path: socketPath)
    check(!s.isListening && s.cachedToken == nil, "an empty token is no token: nothing listens")

    // Turned off during the wait, then answered.
    keychain = BlockingKeychain()
    s = service(keychain, log: "keychain-wait-log-4")
    applying = Task { await s.apply(on, path: socketPath) }
    await checkUntil(5, "a fourth read starts") { keychain.callCount == 1 && s.isListening }
    await s.apply(SessionAccessSettings())
    check(!s.isListening, "turned off during the wait: it stops at once")
    keychain.release(.token(token))
    await applying.value
    check(!s.isListening && !FileManager.default.fileExists(atPath: socketPath), "and stays off when the answer comes")
    check(spoken.last != .allowed, "with nothing said about session access being on")

    // Turned off and on again during the wait.
    keychain = BlockingKeychain()
    s = service(keychain, log: "keychain-wait-log-5")
    applying = Task { await s.apply(on, path: socketPath) }
    await checkUntil(5, "a fifth read starts") { keychain.callCount == 1 && s.isListening }
    await s.apply(SessionAccessSettings())
    await s.apply(on, path: socketPath)
    equal(keychain.callCount, 1, "off and on during the wait doesn't queue a second password window")
    keychain.release(.token(token))
    await applying.value
    r = await send(status(token))
    check(s.isListening && r["ok"] as? Bool == true, "and it's listening once the answer comes, as the switch says")
    await s.apply(SessionAccessSettings())
    check(!FileManager.default.fileExists(atPath: socketPath), "the check leaves no socket behind")

    section("Keychain wait: where the app shows it")
    let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GilaMonster")
    func source(_ name: String) -> String { (try? String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    let rootView = source("RootView.swift"), appModel = source("AppModel.swift"), advisor = source("AdvisorPage.swift")
    let theme = source("Theme.swift")
    check(rootView.contains("VStack(spacing: 8) {\n            KeychainBanner()\n"), "the banner is the first row of every server window's banners")
    check(rootView.contains(".safeAreaInset(edge: .top, spacing: 0) { KeychainBanner()"), "and on the welcome screen, where there's no banner row")
    let banner = rootView.components(separatedBy: "struct KeychainBanner").dropFirst().first?.components(separatedBy: "// MARK: - Main window").first ?? ""
    check(banner.contains("Callout(tone: .warning, title: KeychainWait.title, detail: KeychainWait.detail(purposes), announces: false, spokenAsOne: true)"), "it's the app's own callout (ink on the warning wash, held to 4.5:1 by the color checks), read by VoiceOver as one element")
    check(!banner.isEmpty && !banner.contains(".focusable()"), "with no Tab stop on words that can't be pressed")
    check(banner.contains("title: retrying ? KeychainWait.retryTitle : KeychainWait.deniedTitle") && banner.contains("Button(retrying ? KeychainWait.retryButtonWaiting : KeychainWait.retryButton)") && banner.contains("Button(\"Dismiss\") { wait.setDenied(.sessionToken, false) }"), "a no shows what won't work, with Try Keychain Again and Dismiss, in one callout that stays through a retry")
    check(!banner.contains("\"Try Again\""), "no button is called just Try Again")
    check(!banner.contains("inBannerRow") && !theme.contains("inBannerRow") && rootView.contains(".frame(minHeight: Self.columnMinHeight, maxHeight: .infinity)"), "neither banner needs a layout of its own: the column they sit in can't be pushed taller than the window (K815)")
    check(appModel.contains(".frame(minWidth: wide ? 1700 : 1120, minHeight: 640)"), "the snapshot draws pages at the real window's minimum size")
    check(banner.contains("if focus == .retry { focus = .dismiss }") && banner.contains(".disabled(retrying).focused($focus, equals: .retry)") && banner.contains(".focused($focus, equals: .dismiss)"), "when the retry button goes gray, the keyboard focus moves to Dismiss first")
    check(banner.contains("Announcer.say(KeychainWait.spokenRetry, urgent: true, always: true)"), "pressing it says that macOS is being asked, and where to look")
    check(!banner.contains("animation") && !banner.contains("transition") && !banner.contains("ProgressView"), "nothing in it moves, so Reduce Motion has nothing to turn off")
    check(appModel.contains("Announcer.say(\"\\(Tone.warning.announcement.prefix): \\(KeychainWait.spokenWait)\", urgent: true, always: true)"), "VoiceOver is told when it appears, with where to look, even in the quiet moment after launch")
    check(appModel.contains("KeychainWait.shared.onOutcome = { outcome in Announcer.say(KeychainWait.spoken(outcome), urgent: outcome != .allowed, always: true) }"), "and told how it ended")
    let announcer = source("Accessibility.swift")
    check(announcer.contains("if !force, !always, now < quietUntil { return }") && announcer.contains("guard always || recent[text] == nil, !text.isEmpty else { return }"), "an outcome is said even when the same words were said seconds ago")
    check(theme.contains("guard announces else { return }") && theme.contains(".accessibilityElement(children: spokenAsOne && !long ? .ignore : .contain)"), "the callout can leave the announcing to its owner, and be read as one element when it has nothing to press")
    check(appModel.contains("case \"wait\": KeychainWait.shared.preview(waiting: [.sessionToken, .advisorKey])") && appModel.contains("case \"denied\": KeychainWait.shared.preview(denied: [.sessionToken])"), "the snapshot can draw a made-up wait and a made-up no")
    let fixtures = (try? String(contentsOf: app.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/snapshot-fixtures.sh"), encoding: .utf8)) ?? ""
    check(fixtures.contains("GILAMONSTER_SNAPSHOT_KEYCHAIN=\"${KEYCHAIN:-}\"") && fixtures.contains("\"\"|wait|denied) ;;"), "and the fixture script passes the switch on, refusing any other word")
    check(appModel.contains("guard KeychainWait.mayNotify(authorization: settings.authorizationStatus.rawValue, alertsOn: alertsOn) else { return }\n            center.add(request)"), "the notification is posted only after macOS says notifications are already allowed")
    let waitNotice = appModel.components(separatedBy: "static func keychainWait(").dropFirst().first?.components(separatedBy: "private static func show").first ?? ""
    check(!waitNotice.isEmpty && !waitNotice.contains("requestAuthorization"), "and nobody is asked for notification permission for it")
    check(appModel.range(of: "KeychainWait.shared.onShown")?.lowerBound ?? appModel.endIndex < appModel.range(of: "SessionAccessService.shared.apply(SessionAccess.loadSettings())")?.lowerBound ?? appModel.startIndex, "both are in place before the launch read of the token starts")
    // Every interactive Keychain call in the app goes through the wait, so none can hold the main thread.
    let interactive = advisor.components(separatedBy: "KeychainVault(interactive: true").count - 1
    check(interactive == 1 && advisor.contains("await wait.run(.advisorKey) {\n            do { _ = try KeychainVault(interactive: true, alsoTrusted: [program]).key(create: true); return nil }"), "the Advisor's Allow Keychain Access asks off the main thread, through the wait")
    check(advisor.contains("let asking = wait.begin(.advisorKey)\n        let refused = await Self.helper(program, \"--allow-keychain\")\n        wait.end(asking)"), "and the helper's own ask is shown the same way")
    let appFiles = (try? FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? []
    let direct = appFiles.filter { ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").range(of: #"SecItem(CopyMatching|Add|Update|Delete)|SessionAccess\.(token|readToken|newToken)\("#, options: .regularExpression) != nil }
    check(!appFiles.isEmpty && direct.isEmpty, "no screen calls the Keychain's read functions or the token's directly: \(direct.map(\.lastPathComponent))")
}
