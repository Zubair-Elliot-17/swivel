// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swivel",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwivelCore"),
        .executableTarget(name: "Swivel", dependencies: ["SwivelCore"]),
        .testTarget(name: "SwivelCoreTests", dependencies: ["SwivelCore"]),
    ]
)
