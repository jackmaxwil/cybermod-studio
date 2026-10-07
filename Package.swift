// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CyberModStudio",
    platforms: [.macOS(.v14)],
    products: [
        // All mod logic: loader install, mod placement and manifests, sources, doctor, play sessions.
        .library(name: "CyberModKit", targets: ["CyberModKit"]),
        // The app's state and actions over CyberModKit (no views); the SwiftUI app in CyberModStudio/ uses it.
        .library(name: "CyberModModel", targets: ["CyberModModel"]),
        .executable(name: "cybermod", targets: ["CyberModCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Foundation, CryptoKit and Security only.
        .target(name: "CyberModKit", path: "Sources/CyberModKit"),
        .target(name: "CyberModModel", dependencies: ["CyberModKit"], path: "Sources/CyberModModel"),
        .executableTarget(
            name: "CyberModCLI",
            dependencies: ["CyberModKit", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/CyberModCLI"
        ),
        .testTarget(name: "CyberModKitTests", dependencies: ["CyberModKit"], path: "Tests/CyberModKitTests"),
        .testTarget(name: "CyberModModelTests", dependencies: ["CyberModModel", "CyberModKit"], path: "Tests/CyberModModelTests"),
    ]
)
