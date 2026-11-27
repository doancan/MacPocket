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
        .executable(name: "MacPocketWidget", targets: ["MacPocketWidget"]),
        .executable(name: "MacPocketNetworkFilter", targets: ["MacPocketNetworkFilter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
        .package(path: "Packages/SSHConfigKit"),
        .package(path: "Packages/KeyboardShortcuts"),
        .package(path: "Packages/AIUsageKit"),
    ],
    targets: [
        .target(name: "MacPocketShared"),
        .target(name: "MacPocketCore", dependencies: ["MacPocketShared"]),
        .target(name: "MacPocketWidgetUI", dependencies: ["MacPocketShared"]),
        .executableTarget(name: "MacPocketWidget", dependencies: ["MacPocketWidgetUI"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        .target(name: "MacPocketNetworkPolicy"),
        .executableTarget(name: "MacPocketNetworkFilter", dependencies: ["MacPocketNetworkPolicy"]),
        .target(name: "MacPocketAIUsage", dependencies: ["MacPocketCore", .product(name: "UsageCore", package: "AIUsageKit")]),
        .target(name: "MacPocketSSH", dependencies: ["MacPocketShared", .product(name: "SSHConfigKit", package: "SSHConfigKit"), "KeyboardShortcuts"]),
        .executableTarget(name: "MacPocketProbe", dependencies: ["MacPocketCore"]),
        .executableTarget(name: "MacPocketApp", dependencies: ["MacPocketCore", "MacPocketNetworkPolicy", "MacPocketSSH", "MacPocketAIUsage", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "MacPocketHelper", dependencies: ["MacPocketCore"]),
        .target(name: "MacPocketTestSupport", path: "Tests/MacPocketTestSupport"),
        .testTarget(name: "MacPocketNetworkPolicyTests", dependencies: ["MacPocketNetworkPolicy"]),
        .testTarget(name: "MacPocketCoreTests", dependencies: ["MacPocketCore", "MacPocketTestSupport"]),
        .testTarget(name: "MacPocketWidgetTests", dependencies: ["MacPocketWidgetUI", "MacPocketShared", "MacPocketTestSupport"]),
        .testTarget(name: "MacPocketAppTests", dependencies: ["MacPocketApp", "MacPocketCore", "MacPocketTestSupport"]),
        .testTarget(name: "MacPocketAIUsageTests", dependencies: ["MacPocketAIUsage", "MacPocketTestSupport", .product(name: "UsageCore", package: "AIUsageKit")]),
        .testTarget(name: "MacPocketSSHTests", dependencies: ["MacPocketSSH", .product(name: "SSHConfigKit", package: "SSHConfigKit")]),
    ]
)
