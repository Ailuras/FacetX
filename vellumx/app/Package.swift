// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VellumX",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VellumX",
            path: "Sources/VellumX"
        ),
        .testTarget(
            name: "VellumXTests",
            dependencies: ["VellumX"],
            path: "Tests/VellumXTests"
        )
    ]
)
