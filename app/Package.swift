// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FacetX",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FacetX",
            path: "Sources/FacetX"
        )
    ]
)
