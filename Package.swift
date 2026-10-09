// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Cranny",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cranny",
            path: "Sources/Cranny"
        )
    ]
)
