// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeKeyElements",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VibeKeyCore", targets: ["VibeKeyCore"]),
        .executable(name: "vibekey", targets: ["vibekey-cli"]),
        .executable(name: "VibeKeyElements", targets: ["VibeKeyElementsApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "VibeKeyCore",
            dependencies: [],
            path: "Sources/VibeKeyCore"
        ),
        .executableTarget(
            name: "vibekey-cli",
            dependencies: ["VibeKeyCore"],
            path: "Sources/vibekey-cli"
        ),
        .executableTarget(
            name: "VibeKeyElementsApp",
            dependencies: [
                "VibeKeyCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/VibeKeyElementsApp"
        ),
        .testTarget(
            name: "VibeKeyCoreTests",
            dependencies: ["VibeKeyCore"],
            path: "Tests/VibeKeyCoreTests"
        )
    ]
)
