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
        // Command-line interface
        .executable(
            name: "cybermod",
            targets: ["CyberModCLI"]
        ),
        // Privileged helper daemon
        .executable(
            name: "cybermod-daemon",
            targets: ["CyberModDaemon"]
        )
    ],
    dependencies: [
        // Argument parsing for CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Structured logging
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
        // YAML parsing (for TweakXL/ArchiveXL configs)
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        // SQLite database with type safety
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
        // Archive handling
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.18"),
        // Async HTTP client
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.19.0"),
        // JSON schema validation
        .package(url: "https://github.com/kylef/JSONSchema.swift", from: "0.6.0"),
        // TOML parsing (for config files)
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.5.0"),
        // Crypto for hashing (FNV1a, checksums)
        .package(url: "https://github.com/apple/swift-crypto", from: "3.2.0"),
        // Collections for ordered dictionaries, deques
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    ],
    targets: [
        // MARK: - Core Library
        .target(
            name: "CyberModCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "JSONSchema", package: "JSONSchema.swift"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "Sources/CyberModCore",
            resources: [
                .copy("Schemas/Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-L/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib"])
            ]
        ),
        
        // MARK: - CLI
        .executableTarget(
            name: "CyberModCLI",
            dependencies: [
                "CyberModCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/CyberModCLI"
        ),
        
        // MARK: - Daemon
        .executableTarget(
            name: "CyberModDaemon",
            dependencies: [
                "CyberModCore",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/CyberModDaemon"
        ),
        
        // MARK: - Tests
        .testTarget(
            name: "CyberModCoreTests",
            dependencies: ["CyberModCore"],
            path: "Tests/CyberModCoreTests",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-L/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib"])
            ]
        ),
    ]
)
