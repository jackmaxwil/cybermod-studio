// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CyberModStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Core library containing all business logic
        .library(
            name: "CyberModCore",
            targets: ["CyberModCore"]
        ),
        // Mod-loader install, mod placement, sources, doctor: the logic behind `cybermod` (and the app later)
        .library(
            name: "CyberModKit",
            targets: ["CyberModKit"]
        ),
        // Command-line interface
        .executable(
            name: "cybermod",
            targets: ["CyberModCLI"]
        ),
    ],
    dependencies: [
        // Argument parsing for CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Structured logging
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
        // SQLite database with type safety
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
        // Archive handling
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.18"),
        // Async HTTP client
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.19.0"),
        // Crypto for hashing (FNV1a, checksums)
        .package(url: "https://github.com/apple/swift-crypto", from: "3.2.0"),
    ],
    targets: [
        // MARK: - Core Library
        .target(
            name: "CyberModCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/CyberModCore",
            resources: [
                .copy("Schemas/Resources")
            ]
        ),
        
        // MARK: - Kit (Foundation, CryptoKit and Security only)
        .target(
            name: "CyberModKit",
            path: "Sources/CyberModKit"
        ),

        // MARK: - CLI (thin layer over CyberModKit)
        .executableTarget(
            name: "CyberModCLI",
            dependencies: [
                "CyberModKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CyberModCLI"
        ),
        
        // MARK: - Tests
        .testTarget(
            name: "CyberModCoreTests",
            dependencies: ["CyberModCore"],
            path: "Tests/CyberModCoreTests"
        ),
        .testTarget(
            name: "CyberModKitTests",
            dependencies: ["CyberModKit"],
            path: "Tests/CyberModKitTests"
        ),
    ]
)
