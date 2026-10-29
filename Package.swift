// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clawd",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
        .package(url: "https://github.com/noxaur/PermissionFlow", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Clawd",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "PermissionFlow", package: "PermissionFlow"),
            ],
            path: "Sources/Clawd"
        )
    ]
)
