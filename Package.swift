// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPocket",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacPocketCore", targets: ["MacPocketCore"]),
        .executable(name: "macpocket-probe", targets: ["MacPocketProbe"]),
        .executable(name: "MacPocket", targets: ["MacPocketApp"]),
    ],
    targets: [
        .target(name: "MacPocketCore"),
        .executableTarget(name: "MacPocketProbe", dependencies: ["MacPocketCore"]),
        .executableTarget(name: "MacPocketApp", dependencies: ["MacPocketCore"]),
        .testTarget(name: "MacPocketCoreTests", dependencies: ["MacPocketCore"]),
    ]
)
