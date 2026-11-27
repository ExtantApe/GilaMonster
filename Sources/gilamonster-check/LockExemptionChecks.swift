import Darwin
import Foundation
import Network
@testable import GilaMonsterCore

// The default suite runs without the shared test-server lock (K817). To stay exempt it has to keep four promises:
// every JVM it starts asks for a heap of 512 MB or less, nothing it starts opens a TCP port, every JVM runs inside
// the suite's own scratch folder, and none is left running at the end. This file holds the pieces that make that
// true and the self-audit that fails the run when it isn't.
//
//   gilamonster-check                 No TCP port. Stand-in servers claim made-up ports with a file lock.
//   gilamonster-check --with-ports    Only the checks that need a real TCP port. Take the test-server lock first.
//   gilamonster-check --real-...      Real Paper, as before. Take the test-server lock first.

/// The largest heap a JVM started by the default suite may ask for, in MB.
let exemptHeapMB = 512

enum CheckMode {
    /// Flags whose runs boot real Paper or listen on real ports. Each needs the test-server lock.
    static let lockFlags: Set<String> = ["--with-ports", "--sandbox", "--lab", "--experiments", "--trial-backups", "--demo-invites", "--demo-pack",
                                        "--shutdown-sandbox", "--lab-model", "--advisor-eval", "--links-browser"]
    static func needsLock(_ arguments: [String]) -> Bool {
        arguments.contains { lockFlags.contains($0) || $0.hasPrefix("--real-") }
    }
}

/// True when this run may open TCP ports, so it needs the test-server lock. False for the default suite.
let portsAllowed = CheckMode.needsLock(Array(CommandLine.arguments.dropFirst()))

nonisolated(unsafe) var portSkips: [String] = []

/// Says that a group of checks was left out because it listens on a TCP port. Never silent: the end of the run lists them.
func needsPorts(_ what: String) {
    portSkips.append(what)
    print("  left for --with-ports: \(what)")
}

func printPortSkips() {
    guard !portSkips.isEmpty else { return }
    print("\n\(portSkips.count) groups of checks listen on a TCP port and were left out. Run them with --with-ports while holding the test-server lock:")
    for skip in portSkips { print("  - \(skip)") }
}

// MARK: Made-up ports for stand-in servers

/// A stand-in server claims its port by locking `<port>.claim` in this run's scratch folder. The lock goes when the
/// process does, however it ends, so a claim can't outlive its server. `SystemInfo.isPortBusy` reads the same files
/// while the default suite runs, so preflight, test copies and restarts see a taken port without a socket anywhere.
enum StandInPorts {
    static let variable = "GILAMONSTER_CHECK_PORT_CLAIMS"
    static var folder: URL { scratch.appendingPathComponent("port-claims", isDirectory: true) }

    static func isClaimed(_ port: Int, in folder: URL = StandInPorts.folder) -> Bool {
        let fd = open(folder.appendingPathComponent("\(port).claim").path, O_RDWR)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var probe = flock()
        probe.l_type = Int16(F_WRLCK)
        probe.l_whence = Int16(SEEK_SET)
        // F_GETLK changes l_type to F_UNLCK when no other process holds a lock that would block this one.
        guard fcntl(fd, F_GETLK, &probe) == 0 else { return false }
        return probe.l_type != Int16(F_UNLCK)
    }

    /// Java for the stand-ins: a file lock when the suite gave a claims folder, a real loopback socket otherwise.
    static let java = #"""
      static Closeable claimPort(int port) throws Exception {
        String claims = System.getenv("GILAMONSTER_CHECK_PORT_CLAIMS");
        if (claims == null || claims.isEmpty()) return new ServerSocket(port, 50, InetAddress.getLoopbackAddress());
        var channel = java.nio.channels.FileChannel.open(Path.of(claims, port + ".claim"), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
        if (channel.tryLock() == null) { channel.close(); throw new BindException("Address already in use: stand-in port " + port); }
        return channel;
      }
    """#
}

/// Options for the JDK's own tools (javac, jar), which are JVMs too.
let jdkToolHeap = ["-J-Xmx256m"]

// MARK: Watching what the run starts

struct SeenJVM: Equatable {
    var pid: Int32
    var path: String
    var arguments: [String]
    var directory: String?
    var tool: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct SeenListener: Hashable {
    var pid: Int32
    var program: String
    var port: Int
    /// The local address it's bound to: 127.0.0.1 for this Mac only, 0.0.0.0 or :: for every interface.
    var address: String = "127.0.0.1"
    var thisMacOnly: Bool { address.hasPrefix("127.") || address == "::1" }
}

/// Samples this process and everything it started, many times a second, for the whole run: which JVMs exist, with what
/// arguments and in which folder, and whether any of them, or this process, has a TCP socket that's listening.
/// It reads the kernel's own tables, so it sees a process or a listener whichever code path made it.
final class ProcessWatch: @unchecked Sendable {
    static let shared = ProcessWatch()
    private let lock = NSLock()
    private var jvms: [Int32: SeenJVM] = [:]
    private var listeners: Set<SeenListener> = []
    private var known: Set<Int32> = []
    private var launches: [SeenJVM] = []
    private var samples = 0
    private var running = false
    private var stopped = false

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        running = true
        let thread = Thread { [self] in
            while true {
                lock.lock(); let stop = stopped; lock.unlock()
                if stop { return }
                sample()
                usleep(40_000)
            }
        }
        thread.name = "gilamonster-check.process-watch"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func stop() { lock.lock(); stopped = true; lock.unlock() }

    func recordLaunch(java: String, arguments: [String], directory: URL) {
        lock.lock(); defer { lock.unlock() }
        launches.append(SeenJVM(pid: 0, path: java, arguments: arguments, directory: directory.path))
    }

    var seenJVMs: [SeenJVM] { lock.lock(); defer { lock.unlock() }; return jvms.values.sorted { $0.pid < $1.pid } }
    var seenListeners: [SeenListener] { lock.lock(); defer { lock.unlock() }; return listeners.sorted { ($0.pid, $0.port) < ($1.pid, $1.port) } }
    var seenLaunches: [SeenJVM] { lock.lock(); defer { lock.unlock() }; return launches }
    var sampleCount: Int { lock.lock(); defer { lock.unlock() }; return samples }

    /// JVMs this run started that are still alive, and still the program that was seen.
    func liveJVMs() -> [SeenJVM] {
        seenJVMs.filter { SystemInfo.isAlive(pid: $0.pid) && ProcessWatch.path(of: $0.pid) == $0.path }
    }

    /// Ends what the run left behind. Only processes this run started, was seen starting, and that still run in its folder.
    func killLeftovers() {
        let root = ProcessWatch.real(scratch.path)
        let left = liveJVMs().filter { jvm in SystemInfo.workingDirectory(pid: jvm.pid).map { ProcessWatch.real($0.path).hasPrefix(root) } ?? false }
        guard !left.isEmpty else { return }
        for jvm in left { kill(jvm.pid, SIGTERM) }
        for _ in 0..<50 where left.contains(where: { SystemInfo.isAlive(pid: $0.pid) }) { usleep(100_000) }
        for jvm in left where SystemInfo.isAlive(pid: jvm.pid) && ProcessWatch.path(of: jvm.pid) == jvm.path { kill(jvm.pid, SIGKILL) }
    }

    func sample() {
        let me = getpid()
        lock.lock(); var pids = known; lock.unlock()
        var frontier = [me]
        while let parent = frontier.popLast() {
            for child in ProcessWatch.children(of: parent) where !pids.contains(child) { pids.insert(child); frontier.append(child) }
        }
        // A child's own children are found through it even after this pass, since every pid seen stays on the list.
        for pid in pids where pid != me { for child in ProcessWatch.children(of: pid) { pids.insert(child) } }
        var foundJVMs: [SeenJVM] = []
        var foundListeners: [SeenListener] = []
        lock.lock(); let settled = Set(jvms.filter { $0.value.directory != nil }.keys); lock.unlock()
        for pid in [me] + pids.sorted() {
            let program = ProcessWatch.path(of: pid) ?? ""
            let name = URL(fileURLWithPath: program).lastPathComponent
            if pid != me, ["java", "javac", "jar"].contains(name) {
                // Read once, and again only while the kernel can't yet say which folder it runs in.
                if !settled.contains(pid), let arguments = ProcessWatch.arguments(of: pid) {
                    foundJVMs.append(SeenJVM(pid: pid, path: program, arguments: arguments, directory: SystemInfo.workingDirectory(pid: pid).map { ProcessWatch.real($0.path) }))
                }
            }
            for (port, address) in ProcessWatch.listeningTCPPorts(of: pid) { foundListeners.append(SeenListener(pid: pid, program: pid == me ? "gilamonster-check" : name, port: port, address: address)) }
        }
        lock.lock()
        known = pids.filter { SystemInfo.isAlive(pid: $0) }
        for jvm in foundJVMs {
            // Keep the first full reading: a process that is exiting can lose its folder.
            if let old = jvms[jvm.pid], old.path == jvm.path, old.directory != nil { continue }
            jvms[jvm.pid] = jvm
        }
        listeners.formUnion(foundListeners)
        samples += 1
        lock.unlock()
    }

    /// One spelling for a path, whether or not it still exists. Foundation writes /private/tmp as /tmp only for
    /// folders that exist, and a test copy's folder is gone by the time the audit reads where it ran.
    static func real(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        for prefix in ["/private/tmp", "/private/var", "/private/etc"] where resolved == prefix || resolved.hasPrefix(prefix + "/") {
            return String(resolved.dropFirst("/private".count))
        }
        return resolved
    }

    static func children(of parent: Int32) -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 1024)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parent), &buffer, Int32(buffer.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [] }
        return buffer.prefix(Int(bytes) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    static func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// The arguments a process was started with, from the kernel (KERN_PROCARGS2): a count, the program, then each one.
    static func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let count = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // the program's path
        while index < size, buffer[index] == 0 { index += 1 }   // padding
        var out: [String] = []
        while out.count < count, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            out.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return out.count == count && count > 0 ? out : nil
    }

    /// Local ports and addresses of this process's TCP sockets that accept connections.
    static func listeningTCPPorts(of pid: Int32) -> [(port: Int, address: String)] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard got > 0 else { return [] }
        var ports: [(port: Int, address: String)] = []
        for entry in fds.prefix(Int(got) / stride) where entry.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let wanted = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, entry.proc_fd, PROC_PIDFDSOCKETINFO, &info, wanted) == wanted else { continue }
            guard info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            let accepting = (Int32(info.psi.soi_options) & SO_ACCEPTCONN) != 0 || tcp.tcpsi_state == Int32(TSI_S_LISTEN)
            guard accepting else { continue }
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            var local = tcp.tcpsi_ini.insi_laddr
            if Int32(tcp.tcpsi_ini.insi_vflag) & INI_IPV6 != 0 { inet_ntop(AF_INET6, &local.ina_6, &text, socklen_t(text.count)) }
            else { inet_ntop(AF_INET, &local.ina_46.i46a_addr4, &text, socklen_t(text.count)) }
            ports.append((Int(UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport).byteSwapped), String(cString: text)))
        }
        return ports
    }
}

// MARK: Judging it

enum ExemptionAudit {
    /// A JVM memory size such as 512m, 1G or 268435456, in MB (rounded up). Nil when it can't be read.
    static func megabytes(_ text: String) -> Int? {
        guard let last = text.last else { return nil }
        let units: [Character: Double] = ["k": 1.0 / 1024, "m": 1, "g": 1024, "t": 1024 * 1024]
        if let unit = units[Character(last.lowercased())] {
            guard let number = Double(text.dropLast()), number >= 0, text.dropLast().allSatisfy(\.isNumber) else { return nil }
            return Int((number * unit).rounded(.up))
        }
        guard text.allSatisfy(\.isNumber), let bytes = Double(text) else { return nil }
        return Int((bytes / 1_048_576).rounded(.up))
    }

    /// The largest heap these arguments ask for. Java takes the last -Xmx (or -XX:MaxHeapSize); the JDK's tools take
    /// them behind -J. Nil when none is given, which would leave the JVM to pick a quarter of the Mac's memory.
    static func maxHeapMB(_ arguments: [String]) -> Int?? {
        var found: Int?? = nil
        for raw in arguments {
            let arg = raw.hasPrefix("-J") ? String(raw.dropFirst(2)) : raw
            if arg.hasPrefix("-Xmx") { found = .some(megabytes(String(arg.dropFirst(4)))) }
            else if arg.hasPrefix("-XX:MaxHeapSize=") { found = .some(megabytes(String(arg.dropFirst(16)))) }
            // Arguments after the jar or the main class are the program's, not the JVM's.
            if raw == "-jar" { break }
        }
        return found
    }

    /// `java -version` and the like: the JVM prints and exits without running a program.
    static func isVersionProbe(_ jvm: SeenJVM) -> Bool {
        jvm.tool == "java" && !jvm.arguments.dropFirst().isEmpty && jvm.arguments.dropFirst().allSatisfy { ["-version", "--version", "-fullversion", "-XshowSettings:properties"].contains($0) }
    }

    /// What breaks the exemption, in plain words. Empty means the run kept to it.
    static func problems(jvms: [SeenJVM], listeners: [SeenListener], scratch: String, limitMB: Int = exemptHeapMB) -> [String] {
        var out: [String] = []
        let root = ProcessWatch.real(scratch)
        for jvm in jvms where !isVersionProbe(jvm) {
            let shown = "\(jvm.tool) \(jvm.arguments.dropFirst().prefix(6).joined(separator: " "))"
            switch maxHeapMB(jvm.arguments) {
            case .none: out.append("\(shown): no -Xmx, so the JVM would choose its own heap")
            case .some(.none): out.append("\(shown): its -Xmx can't be read")
            case let .some(.some(mb)) where mb > limitMB: out.append("\(shown): heap \(mb) MB is over \(limitMB) MB")
            default: break
            }
            if jvm.tool == "java" {
                if let directory = jvm.directory {
                    let real = ProcessWatch.real(directory)
                    if real != root && !real.hasPrefix(root + "/") { out.append("\(shown): runs in \(directory), outside the suite's scratch folder") }
                } else {
                    out.append("\(shown): the folder it runs in couldn't be read")
                }
            }
        }
        for listener in listeners { out.append("\(listener.program) (pid \(listener.pid)) listened on TCP port \(listener.port)") }
        return out
    }

    /// Listeners that something off this Mac could reach: bound to every interface, or to a network address.
    static func reachableFromOutside(_ listeners: [SeenListener]) -> [String] {
        listeners.filter { !$0.thisMacOnly }.map { "\($0.program) (pid \($0.pid)) listened on \($0.address) port \($0.port), not 127.0.0.1" }
    }
}

// MARK: Set-up and the checks

/// Called once, as soon as the scratch folder exists.
func beginLockExemption() {
    ServerProcess.launchObserver = { java, arguments, directory in
        ProcessWatch.shared.recordLaunch(java: java, arguments: ["java"] + arguments, directory: directory)
    }
    ProcessWatch.shared.start()
    guard !portsAllowed else { return }
    try? FileManager.default.createDirectory(at: StandInPorts.folder, withIntermediateDirectories: true)
    setenv(StandInPorts.variable, StandInPorts.folder.path, 1)
    SystemInfo.portProbeStandIn = { StandInPorts.isClaimed($0) }
}

/// For a helper process a check starts (`--drill-signal-child`): it inherits the claims folder, so its own port
/// check has to read the claims too. Without this it would bind real ports for a moment to see if they're free.
func adoptStandInPorts() {
    guard let claims = ProcessInfo.processInfo.environment[StandInPorts.variable], !claims.isEmpty else { return }
    let folder = URL(fileURLWithPath: claims, isDirectory: true)
    SystemInfo.portProbeStandIn = { StandInPorts.isClaimed($0, in: folder) }
}

/// The audit's own judgement, on made-up records. Runs in every set.
@MainActor func exemptionRuleChecks() {
    section("Lock exemption: the rules the audit applies")
    equal(ExemptionAudit.megabytes("512m"), 512, "512m"); equal(ExemptionAudit.megabytes("512M"), 512, "512M")
    equal(ExemptionAudit.megabytes("1G"), 1024, "1G"); equal(ExemptionAudit.megabytes("2g"), 2048, "2g")
    equal(ExemptionAudit.megabytes("524288k"), 512, "kilobytes"); equal(ExemptionAudit.megabytes("536870912"), 512, "plain bytes")
    equal(ExemptionAudit.megabytes("536870913"), 513, "a byte over rounds up")
    equal(ExemptionAudit.megabytes("lots"), nil, "words aren't a size"); equal(ExemptionAudit.megabytes(""), nil, "nor is nothing")
    let home = "/made/up/scratch"
    func java(_ arguments: String, in directory: String? = "/made/up/scratch/server", tool: String = "/made/up/jdk/bin/java") -> SeenJVM {
        SeenJVM(pid: 7, path: tool, arguments: [URL(fileURLWithPath: tool).lastPathComponent] + arguments.split(separator: " ").map(String.init), directory: directory)
    }
    func problems(_ jvm: SeenJVM) -> [String] { ExemptionAudit.problems(jvms: [jvm], listeners: [], scratch: home) }
    equal(problems(java("-Xms256M -Xmx512M -jar standin.jar nogui")), [], "512 MB in the scratch folder is fine")
    check(problems(java("-Xms1024M -Xmx2048M -jar standin.jar nogui")).contains { $0.contains("2048 MB is over 512 MB") }, "2048 MB is caught")
    check(problems(java("-Xmx513m -jar standin.jar")).count == 1, "one MB over is caught")
    check(problems(java("-Xmx1G -jar standin.jar")).count == 1, "so is a gigabyte, written with G")
    check(problems(java("-Xmx256m -Xmx4G -jar standin.jar")).count == 1, "the last -Xmx is the one Java uses")
    check(problems(java("-XX:MaxHeapSize=2g -jar standin.jar")).count == 1, "the long spelling counts")
    check(problems(java("-jar standin.jar")).contains { $0.contains("no -Xmx") }, "no -Xmx at all is caught, since Java would take a quarter of the memory")
    check(problems(java("-Xmxbig -jar standin.jar")).contains { $0.contains("can't be read") }, "an -Xmx that can't be read is caught")
    equal(problems(java("-Xmx256m -jar standin.jar -Xmx9G")), [], "an argument after the jar is the program's own")
    check(problems(java("-Xmx512M -jar standin.jar", in: "/made/up/elsewhere")).contains { $0.contains("outside") }, "a folder outside the scratch folder is caught")
    check(problems(java("-Xmx512M -jar standin.jar", in: "/made/up/scratch-other")).contains { $0.contains("outside") }, "a folder that only starts with the same letters is outside too")
    check(problems(java("-Xmx512M -jar standin.jar", in: nil)).contains { $0.contains("couldn't be read") }, "a folder that can't be read isn't taken on trust")
    equal(problems(java("-version")), [], "asking Java its version runs no program")
    equal(ExemptionAudit.problems(jvms: [java("-Xmx512M -jar standin.jar", in: "/private/tmp/made-up-scratch/test-copies/gone")], listeners: [], scratch: "/tmp/made-up-scratch"), [],
          "a folder that's since been deleted is still matched to the scratch folder, with or without /private")
    check(problems(java("-d out StandIn.java", tool: "/made/up/jdk/bin/javac")).contains { $0.contains("no -Xmx") }, "the compiler is a JVM too")
    equal(problems(java("-J-Xmx256m -d out StandIn.java", in: "/made/up/elsewhere", tool: "/made/up/jdk/bin/javac")), [], "and takes its heap behind -J")
    equal(ExemptionAudit.problems(jvms: [], listeners: [SeenListener(pid: 9, program: "java", port: 25597)], scratch: home), ["java (pid 9) listened on TCP port 25597"], "any listening TCP port is caught")
    func bound(_ address: String) -> [String] { ExemptionAudit.reachableFromOutside([SeenListener(pid: 9, program: "java", port: 25597, address: address)]) }
    equal(bound("127.0.0.1"), [], "a listener on 127.0.0.1 is this Mac only"); equal(bound("::1"), [], "and so is one on ::1")
    equal(bound("0.0.0.0"), ["java (pid 9) listened on 0.0.0.0 port 25597, not 127.0.0.1"], "a listener on every interface is caught")
    check(bound("::").count == 1 && bound("192.168.1.20").count == 1 && bound("").count == 1, "and so is one on every IPv6 interface, on a network address, or on an address that can't be read")
    check(CheckMode.needsLock(["--with-ports"]) && CheckMode.needsLock(["--real-paper", "--i-accept-the-minecraft-eula"]) && CheckMode.needsLock(["--sandbox"]), "port and real-server runs are marked as needing the lock")
    check(!CheckMode.needsLock([]) && !CheckMode.needsLock(["--connections"]) && !CheckMode.needsLock(["--live"]), "the default suite and --connections aren't")

    // Made-up ports: a claim is seen only while another process holds it.
    let claims = folder("claims-\(UUID().uuidString)")
    check(!StandInPorts.isClaimed(25000, in: claims), "a port nobody claimed is free")
    write("", claims.appendingPathComponent("25000.claim"))
    check(!StandInPorts.isClaimed(25000, in: claims), "a claim file nobody holds is free too, so a claim can't outlive its server")
    let holder = Process()
    holder.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    holder.arguments = ["-c", "import fcntl,sys,time\nf=open(sys.argv[1],'w')\nfcntl.lockf(f,fcntl.LOCK_EX)\nprint('held',flush=True)\ntime.sleep(60)", claims.appendingPathComponent("25000.claim").path]
    let said = Pipe()
    holder.standardOutput = said
    if (try? holder.run()) != nil {
        _ = said.fileHandleForReading.availableData
        check(StandInPorts.isClaimed(25000, in: claims), "held by another process, it's taken")
        check(!StandInPorts.isClaimed(25001, in: claims), "and the next port isn't")
        holder.terminate(); holder.waitUntilExit()
        check(!StandInPorts.isClaimed(25000, in: claims), "and it's free the moment that process is gone")
    } else { print("  skipped: no python3 to hold a claim") }
}

/// The self-audit. Fails the default suite if anything it started broke the exemption from the test-server lock.
@MainActor func lockExemptionAudit() async {
    section("Lock exemption: what this run started")
    let watch = ProcessWatch.shared
    guard !portsAllowed else {
        print("  not judged: this run may open ports, so it needs the test-server lock")
        return
    }
    // Cleaned up: every JVM gone, waiting about as long as the lock's own rule does.
    let gone = await until(60) { watch.liveJVMs().isEmpty }
    let left = watch.liveJVMs()
    check(gone, "no JVM this run started is still running: \(left.map { "pid \($0.pid) \($0.arguments.suffix(3).joined(separator: " "))" })")
    if !gone { watch.killLeftovers() }
    watch.sample()
    let jvms = watch.seenJVMs, launches = watch.seenLaunches, listeners = watch.seenListeners
    let problems = ExemptionAudit.problems(jvms: jvms, listeners: listeners, scratch: scratch.path)
    let launchProblems = ExemptionAudit.problems(jvms: launches, listeners: [], scratch: scratch.path)
    check(SystemInfo.portProbeStandIn != nil, "the port check never touched a socket")
    equal(ProcessInfo.processInfo.environment[StandInPorts.variable], StandInPorts.folder.path, "stand-in servers were given a claims folder in place of ports")
    check(watch.sampleCount > 20, "the watch was running (\(watch.sampleCount) samples)")
    equal(listeners.map { "\($0.program) pid \($0.pid) port \($0.port)" }, [], "nothing this run started listened on a TCP port")
    equal(launchProblems, [], "every server launch asked for \(exemptHeapMB) MB or less, in the scratch folder")
    equal(problems, [], "every JVM seen running kept to \(exemptHeapMB) MB and the scratch folder")
    let servers = jvms.filter { $0.tool == "java" && !ExemptionAudit.isVersionProbe($0) }
    check(launches.isEmpty || !servers.isEmpty, "the watch saw the servers the launcher started (\(servers.count) seen, \(launches.count) launched)")
    // The evidence, for whoever reads the run.
    var heaps: [String: Int] = [:]
    for jvm in jvms where !ExemptionAudit.isVersionProbe(jvm) {
        let heap = (ExemptionAudit.maxHeapMB(jvm.arguments) ?? nil).map { "\($0) MB" } ?? "unknown"
        heaps["\(jvm.tool), heap \(heap)", default: 0] += 1
    }
    print("  \(launches.count) server launches, \(jvms.count) JVMs seen over \(watch.sampleCount) samples, \(listeners.count) TCP listeners")
    for (kind, count) in heaps.sorted(by: { $0.key < $1.key }) { print("  \(count) × \(kind)") }
    print("  \(jvms.filter(ExemptionAudit.isVersionProbe).count) × java asked only for its version")
}

// MARK: The checks that need a real port

/// `SystemInfo.isPortBusy` against real sockets. In the default suite it reads claim files, so this is where the
/// real one is proved.
@MainActor func portProbeChecks() {
    guard portsAllowed else { needsPorts("The port check against a real socket"); return }
    section("The port check, against a real socket")
    // A port held only on 127.0.0.1, as the Lab does.
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(25977).bigEndian
    address.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(fd, 1)
    check(SystemInfo.isPortBusy(25977), "a port held only on this Mac's loopback address counts as busy")
    // The watch has to see this, or the default suite's audit would prove nothing.
    ProcessWatch.shared.sample()
    check(ProcessWatch.shared.seenListeners.contains { $0.port == 25977 && $0.pid == getpid() }, "and the audit's watch sees the listener")
    equal(ProcessWatch.shared.seenListeners.first { $0.port == 25977 }?.address, "127.0.0.1", "and reads the address it's bound to")
    close(fd)
    check(!SystemInfo.isPortBusy(25977), "and is free once released")
}

/// The stand-in jar on a real loopback port: the port is seen as busy while it runs and free afterwards, and the
/// audit's watch sees both the JVM and its listener.
@MainActor func standInOnRealPortChecks() async {
    guard portsAllowed else { needsPorts("A stand-in server on a real port: busy while it runs, free after"); return }
    section("Stand-in server on a real TCP port")
    let runtimes = await JavaManager.discover()
    guard let jdk = runtimes.first(where: { FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: $0.path).deletingLastPathComponent().appendingPathComponent("javac").path) }) else {
        print("  skipped: no JDK found")
        return
    }
    do {
        let port = 25597
        let root = folder("standin-real-port")
        try await buildStandIn(jdk: jdk, into: root.appendingPathComponent("standin.jar"))
        write("server-port=\(port)\nserver-ip=127.0.0.1\nmotd=made up\nlevel-name=world\n", root.appendingPathComponent("server.properties"))
        makeJarInPlugins(root, "Foo")
        let c = try await ServerController.adopt(root: root, name: "Stand-in Real Port")
        defer { c.forceStop(by: .app("for a check")); c.stopTicker() }
        c.requiresEULA = false
        c.profile.software.flavor = .custom
        c.profile.software.jarName = "standin.jar"
        c.profile.software.mcVersion = "1.21.11"
        c.profile.software.requiredJava = jdk.major
        c.profile.launch.javaPath = jdk.path
        c.profile.launch.preset = .none
        c.profile.launch.restartOnCrash = false
        c.profile.launch.maxMemoryMB = exemptHeapMB
        c.profile.launch.minMemoryMB = 256
        c.profile.backup.enabled = false
        c.profile.lastPluginCheck = Date()
        c.profile.software.lastCheck = Date()
        check(SystemInfo.portProbeStandIn == nil, "the real port check is in use")
        check(!SystemInfo.isPortBusy(port), "the port is free before it starts")
        await c.start()
        await checkUntil(30, "reached running (last: \(c.console.suffix(3).map(\.text)))") { c.state == .running }
        check(SystemInfo.isPortBusy(port), "port detected as busy")
        let busy = await c.preflight()
        check(busy.contains { if case .portBusy = $0.kind { true } else { false } }, "preflight sees the port")
        equal(Trial.freePort(after: port - 1) > port, true, "a test copy would be given another port")
        let watch = ProcessWatch.shared
        await checkUntil(5, "the audit's watch sees the stand-in's listener") { watch.seenListeners.contains { $0.port == port && $0.program == "java" } }
        let standInListener = watch.seenListeners.first { $0.port == port && $0.program == "java" }
        check(standInListener?.thisMacOnly == true, "the stand-in listens on this Mac only: \(standInListener?.address ?? "not seen")")
        let seen = watch.seenJVMs.first { $0.directory == ProcessWatch.real(root.path) }
        check(seen?.arguments.contains("-Xmx\(exemptHeapMB)M") == true, "and reads its arguments from the kernel: \(seen?.arguments.prefix(4) ?? [])")
        equal(seen.map { ExemptionAudit.problems(jvms: [$0], listeners: [], scratch: scratch.path) }, [], "which pass the heap and folder rules")
        check(!ExemptionAudit.problems(jvms: [], listeners: watch.seenListeners, scratch: scratch.path).isEmpty, "while the listener would fail the default suite")
        c.stop(by: .app("for a check"))
        await checkUntil(60, "stopped") { c.state == .stopped }
        check(!SystemInfo.isPortBusy(port), "port released")
        await checkUntil(60, "and no JVM is left") { watch.liveJVMs().isEmpty }
    } catch { failures.append("stand-in on a real port: \(error)") }
}

/// The ports set's own audit: every listener it opened, in this process or a stand-in, was bound to this Mac only.
/// A stand-in or a test listener on every interface would be reachable from the network while the run lasts.
@MainActor func loopbackOnlyAudit() {
    section("Ports set: every listener was on 127.0.0.1 only")
    let watch = ProcessWatch.shared
    watch.sample()
    let listeners = watch.seenListeners
    check(listeners.count >= 5, "the watch saw this set's listeners (\(listeners.count))")
    check(listeners.contains { $0.program == "java" } || watch.seenLaunches.isEmpty, "the stand-in servers' among them")
    equal(ExemptionAudit.reachableFromOutside(listeners), [], "none was bound to every interface or to a network address")
    print("  \(listeners.count) listeners seen, on ports \(Set(listeners.map(\.port)).sorted().map(String.init).joined(separator: ", "))")
}
