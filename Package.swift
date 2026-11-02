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
    targets: [
        .target(name: "MacPocketCore"),
        .executableTarget(name: "MacPocketProbe", dependencies: ["MacPocketCore"]),
        .executableTarget(name: "MacPocketApp", dependencies: ["MacPocketCore"]),
        .executableTarget(name: "MacPocketFanHelper", dependencies: ["MacPocketCore"]),
        .testTarget(name: "MacPocketCoreTests", dependencies: ["MacPocketCore"]),
    ]
)
