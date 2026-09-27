// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lagoon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lagoon",
            path: "Sources/Lagoon"
        )
    ]
)
