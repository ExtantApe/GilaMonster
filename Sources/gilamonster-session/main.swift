import Foundation

// gilamonster-session: asks a running GilaMonster for a server's status or recent log, or runs a command from the
// owner's list. It reads the token from the login Keychain with /usr/bin/security, so the first time macOS asks the
// owner to allow it. GILAMONSTER_SESSION_TOKEN and GILAMONSTER_HOME override the token and the folder, for checks.

let usage = """
Usage:
  gilamonster-session --as "Your name" status [--server NAME]
  gilamonster-session --as "Your name" log [--lines 50] [--server NAME]
  gilamonster-session --as "Your name" run "save-all" [--server NAME]
  gilamonster-session --as "Your name" backup status [--server NAME]

Pack library and recipes (no prompt; nothing players see changes):
  gilamonster-session --as "Your name" pack add /full/path/pack.zip
  gilamonster-session --as "Your name" recipe set NAME --packs id1,id2
  gilamonster-session --as "Your name" recipe build NAME

Waits for the owner to press Allow (a Mac notification; no answer in 2 minutes means no):
  gilamonster-session --as "Your name" start|stop|restart [--server NAME]
  gilamonster-session --as "Your name" publish RECIPE [--server NAME]
  gilamonster-session --as "Your name" handoff RECIPE [--by-hand] [--server NAME]
  gilamonster-session --as "Your name" hosting start|stop [--server NAME]
  gilamonster-session --as "Your name" hosting add|remove RECIPE [--server NAME]

  gilamonster-session --as "Your name" hosting status [--server NAME]
  gilamonster-session --as "Your name" gate check URL [--player NAME] [--server NAME]
    (with --player it asks for Allow, since it says whether that player is joining)

Prints GilaMonster's answer as JSON. Exits 0 when ok is true, 1 when refused, 2 when GilaMonster can't be reached.
Only commands on the owner's list in GilaMonster's Settings are sent with run. Nothing is done while a backup is
being written, and a server marked "Children may play here" always asks.
"""

var args = Array(CommandLine.arguments.dropFirst())
func take(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...i + 1)
    return value
}
let caller = take("--as")
let server = take("--server")
let lines = take("--lines").flatMap(Int.init)
let packs = take("--packs")
let player = take("--player")
let byHand = args.contains("--by-hand")
args.removeAll { $0 == "--by-hand" }
func fail(_ text: String) -> Never { FileHandle.standardError.write(Data((text + "\n").utf8)); exit(64) }
guard let caller, let first = args.first else { fail(usage) }
var call = first
var command: String?
var extra: [String: Any] = [:]
let rest = Array(args.dropFirst())
switch first {
case "status", "log", "start", "stop", "restart":
    guard rest.isEmpty else { fail(usage) }
case "run":
    command = rest.joined(separator: " ")
    if command?.isEmpty != false { fail("run needs a command.") }
case "backup":
    guard rest == ["status"] else { fail(usage) }
    call = "backup-status"
case "pack":
    guard rest.count == 2, rest[0] == "add" else { fail(usage) }
    extra["path"] = URL(fileURLWithPath: rest[1]).standardizedFileURL.path
    call = "pack-add"
case "recipe":
    guard rest.count == 2, ["set", "build"].contains(rest[0]) else { fail(usage) }
    call = "recipe-" + rest[0]
    extra["recipe"] = rest[1]
    if rest[0] == "set" {
        guard let packs else { fail("recipe set needs --packs id1,id2") }
        extra["packs"] = packs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
case "publish":
    guard rest.count == 1 else { fail(usage) }
    extra["recipe"] = rest[0]
case "handoff":
    guard rest.count == 1 else { fail(usage) }
    extra["recipe"] = rest[0]
    if byHand { extra["byHand"] = true }
case "hosting":
    guard let verb = rest.first, ["start", "stop", "status", "add", "remove"].contains(verb) else { fail(usage) }
    call = "hosting-" + verb
    if verb == "add" || verb == "remove" {
        guard rest.count == 2 else { fail("hosting \(verb) needs a recipe.") }
        extra["recipe"] = rest[1]
    } else if rest.count != 1 { fail(usage) }
case "gate":
    guard rest.count == 2, rest[0] == "check" else { fail(usage) }
    call = "gate-check"
    extra["url"] = rest[1]
    if let player { extra["player"] = player }
default:
    fail(usage)
}

func token() -> String? {
    if let t = ProcessInfo.processInfo.environment["GILAMONSTER_SESSION_TOKEN"], !t.isEmpty { return t }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "GilaMonster session access", "-a", "token", "-w"]
    let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let home = ProcessInfo.processInfo.environment["GILAMONSTER_HOME"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GilaMonster")
let path = ProcessInfo.processInfo.environment["GILAMONSTER_SESSION_SOCKET"] ?? home.appendingPathComponent("session.sock").path

guard let secret = token() else {
    FileHandle.standardError.write(Data("No token: turn on session access in GilaMonster's Settings, and allow the Keychain prompt if one appears.\n".utf8)); exit(2)
}
var request: [String: Any] = ["token": secret, "caller": caller, "call": call]
if let server { request["server"] = server }
if let lines { request["lines"] = lines }
if let command { request["command"] = command }
request.merge(extra) { $1 }
var body = try! JSONSerialization.data(withJSONObject: request)
body.append(0x0A)

let s = socket(AF_UNIX, SOCK_STREAM, 0)
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
guard path.utf8.count < 104 else { FileHandle.standardError.write(Data("The socket path is too long.\n".utf8)); exit(2) }
withUnsafeMutableBytes(of: &address.sun_path) { raw in
    let bytes = Array(path.utf8)
    for (i, b) in bytes.enumerated() { raw[i] = b }
    raw[bytes.count] = 0
}
let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
guard connected == 0 else { FileHandle.standardError.write(Data("GilaMonster isn't listening. Is it open, with session access on?\n".utf8)); exit(2) }
_ = body.withUnsafeBytes { write(s, $0.baseAddress, $0.count) }
var reply = Data()
var buffer = [UInt8](repeating: 0, count: 4096)
while true {
    let n = read(s, &buffer, buffer.count)
    if n <= 0 { break }
    reply.append(contentsOf: buffer[0..<n])
}
close(s)
FileHandle.standardOutput.write(reply)
let ok = ((try? JSONSerialization.jsonObject(with: reply)) as? [String: Any])?["ok"] as? Bool == true
exit(ok ? 0 : 1)
