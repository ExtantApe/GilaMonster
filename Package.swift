// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GilaMonster",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GilaMonster", targets: ["GilaMonster"])],
    targets: [
        // Everything testable: no SwiftUI, no AppKit.
        .target(name: "GilaMonsterCore"),
        // The Mac app.
        .executableTarget(name: "GilaMonster", dependencies: ["GilaMonsterCore", "GilaMonsterAdvisor"]),
        // Self-tests as a plain executable, so they run without Xcode (XCTest needs it).
        .executableTarget(name: "gilamonster-check", dependencies: ["GilaMonsterCore", "GilaMonsterAdvisor", "gilamonster-mcp"]),
        // Privacy layer for the optional advisor. It must never depend on GilaMonsterCore: see docs/ADVISOR-SECURITY.md.
        .target(name: "GilaMonsterAdvisor"),
        .executableTarget(name: "gilamonster-mcp", dependencies: ["GilaMonsterAdvisor"]),
        // How assistant sessions talk to a running GilaMonster: status, logs and the owner's list of commands.
        .executableTarget(name: "gilamonster-session"),
    ]
)
