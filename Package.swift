// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexBrain",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CodexBrain",
            path: "Sources/CodexBrain",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
