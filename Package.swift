// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacPocket",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "MacPocketCore", targets: ["MacPocketCore"]),
        .executable(name: "macpocket-probe", targets: ["MacPocketProbe"]),
        .executable(name: "MacPocket", targets: ["MacPocketApp"]),
        .executable(name: "MacPocketHelper", targets: ["MacPocketHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
        .package(path: "Packages/SSHConfigKit"),
        .package(path: "Packages/KeyboardShortcuts"),
        .package(path: "Packages/AIUsageKit"),
    ],
    targets: [
        .target(name: "MacPocketCore"),
        .target(name: "MacPocketAIUsage", dependencies: ["MacPocketCore", .product(name: "UsageCore", package: "AIUsageKit")]),
        .target(name: "MacPocketSSH", dependencies: [.product(name: "SSHConfigKit", package: "SSHConfigKit"), "KeyboardShortcuts"]),
        .executableTarget(name: "MacPocketProbe", dependencies: ["MacPocketCore"]),
        .executableTarget(name: "MacPocketApp", dependencies: ["MacPocketCore", "MacPocketSSH", "MacPocketAIUsage", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "MacPocketHelper", dependencies: ["MacPocketCore"]),
        .testTarget(name: "MacPocketCoreTests", dependencies: ["MacPocketCore"]),
        .testTarget(name: "MacPocketAppTests", dependencies: ["MacPocketApp", "MacPocketCore"]),
        .testTarget(name: "MacPocketAIUsageTests", dependencies: ["MacPocketAIUsage", .product(name: "UsageCore", package: "AIUsageKit")]),
        .testTarget(name: "MacPocketSSHTests", dependencies: ["MacPocketSSH", .product(name: "SSHConfigKit", package: "SSHConfigKit")]),
    ]
)
