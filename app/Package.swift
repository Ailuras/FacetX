// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FacetX",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FacetXCore",
            path: "Sources/FacetXCore"
        ),
        .executableTarget(
            name: "FacetX",
            dependencies: ["FacetXCore"],
            path: "Sources/FacetX"
        ),
        .executableTarget(
            name: "FacetXCoreChecks",
            dependencies: ["FacetXCore"],
            path: "Checks/FacetXCoreChecks"
        )
    ]
)
