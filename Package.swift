// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacPocket",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "MacPocketCore", targets: ["MacPocketCore"]),
        .executable(name: "macpocket-probe", targets: ["MacPocketProbe"]),
        .executable(name: "MacPocket", targets: ["MacPocketApp"]),
        .executable(name: "MacPocketFanHelper", targets: ["MacPocketFanHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "MacPocketCore"),
        .executableTarget(name: "MacPocketProbe", dependencies: ["MacPocketCore"]),
        .executableTarget(name: "MacPocketApp", dependencies: ["MacPocketCore", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "MacPocketFanHelper", dependencies: ["MacPocketCore"]),
        .testTarget(name: "MacPocketCoreTests", dependencies: ["MacPocketCore"]),
    ]
)
