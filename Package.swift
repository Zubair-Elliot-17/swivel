// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swivel",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode", from: "1.6.0"),
    ],
    targets: [
        .target(name: "SwivelCore", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]),
        .executableTarget(name: "Swivel", dependencies: ["SwivelCore"]),
        .testTarget(name: "SwivelCoreTests", dependencies: ["SwivelCore", .product(name: "libwebp", package: "libwebp-Xcode")]),
    ]
)
