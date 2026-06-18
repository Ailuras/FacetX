// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FacetX",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .target(
            name: "FacetXCore",
            path: "Sources/FacetXCore"
        ),
        .executableTarget(
            name: "FacetX",
            dependencies: [
                "FacetXCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/FacetX"
        ),
        .executableTarget(
            name: "FacetXCoreChecks",
            dependencies: ["FacetXCore"],
            path: "Checks/FacetXCoreChecks"
        )
    ]
)
