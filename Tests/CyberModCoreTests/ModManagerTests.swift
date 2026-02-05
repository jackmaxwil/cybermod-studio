// ModManagerTests.swift - Tests for ModManager

import XCTest
@testable import CyberModCore

final class ModManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Mod Type Tests
    
    func testModTypeFileExtensions() {
        XCTAssertTrue(ModType.archive.fileExtensions.contains("archive"))
        XCTAssertTrue(ModType.tweakXL.fileExtensions.contains("yaml"))
        XCTAssertTrue(ModType.tweakXL.fileExtensions.contains("yml"))
        XCTAssertTrue(ModType.archiveXL.fileExtensions.contains("xl"))
        XCTAssertTrue(ModType.redscript.fileExtensions.contains("reds"))
        XCTAssertTrue(ModType.red4ext.fileExtensions.contains("dylib"))
    }
    
    func testModTypeMacOSCompatibility() {
        XCTAssertTrue(ModType.archive.isMacOSCompatible)
        XCTAssertTrue(ModType.tweakXL.isMacOSCompatible)
        XCTAssertTrue(ModType.archiveXL.isMacOSCompatible)
        XCTAssertTrue(ModType.redscript.isMacOSCompatible)
        XCTAssertTrue(ModType.red4ext.isMacOSCompatible)
        XCTAssertFalse(ModType.cyber.isMacOSCompatible)
    }
    
    func testModTypeInstallDirectories() {
        XCTAssertEqual(ModType.archive.installDirectory, "archive/pc/mod")
        XCTAssertEqual(ModType.tweakXL.installDirectory, "r6/tweaks")
        XCTAssertEqual(ModType.redscript.installDirectory, "r6/scripts")
        XCTAssertEqual(ModType.red4ext.installDirectory, "red4ext/plugins")
    }
    
    // MARK: - Mod Creation Tests
    
    func testModCreation() {
        let mod = Mod(
            name: "Test Mod",
            version: "1.0.0",
            author: "Test Author",
            type: [.tweakXL],
            stagingPath: tempDirectory
        )
        
        XCTAssertEqual(mod.name, "Test Mod")
        XCTAssertEqual(mod.version, "1.0.0")
        XCTAssertEqual(mod.author, "Test Author")
        XCTAssertTrue(mod.type.contains(.tweakXL))
        XCTAssertTrue(mod.isEnabled)
    }
    
    func testModMetadata() {
        let metadata = ModMetadata(
            nexusUrl: URL(string: "https://nexusmods.com/cyberpunk2077/mods/123"),
            category: "Gameplay",
            tags: ["tweak", "stats"],
            dependencies: [
                ModDependency(name: "TweakXL", nexusId: 4197)
            ]
        )
        
        XCTAssertEqual(metadata.tags.count, 2)
        XCTAssertEqual(metadata.dependencies.count, 1)
        XCTAssertEqual(metadata.dependencies.first?.name, "TweakXL")
    }
    
    // MARK: - Profile Tests
    
    func testProfileCreation() {
        let profile = ModProfile(
            name: "Test Profile",
            gamePath: tempDirectory
        )
        
        XCTAssertEqual(profile.name, "Test Profile")
        XCTAssertFalse(profile.isActive)
    }
    
    func testProfileSettings() {
        var settings = ProfileSettings()
        settings.skipIntroVideos = true
        settings.enableDebugAgent = true
        settings.launchArguments = ["-debug"]
        
        let profile = ModProfile(
            name: "Debug Profile",
            gamePath: tempDirectory,
            settings: settings
        )
        
        XCTAssertTrue(profile.settings.skipIntroVideos)
        XCTAssertTrue(profile.settings.enableDebugAgent)
        XCTAssertEqual(profile.settings.launchArguments, ["-debug"])
    }
}

// MARK: - Compatibility Checker Tests

final class CompatibilityCheckerTests: XCTestCase {
    
    var checker: CompatibilityChecker!
    
    override func setUp() async throws {
        checker = CompatibilityChecker()
    }
    
    func testCompatibleModAnalysis() async {
        let analysis = ModAnalysis(
            modName: "Compatible Mod",
            version: "1.0.0",
            author: "Test",
            detectedTypes: [.archive, .tweakXL],
            files: [
                AnalyzedFile(
                    relativePath: "archive/pc/mod/test.archive",
                    absolutePath: URL(fileURLWithPath: "/tmp/test.archive"),
                    fileType: .archive,
                    size: 1000
                )
            ],
            hasFomod: false,
            fomodConfig: nil
        )
        
        let result = await checker.check(analysis: analysis)
        
        XCTAssertTrue(result.isCompatible)
        XCTAssertTrue(result.issues.isEmpty)
    }
    
    func testIncompatibleDLLMod() async {
        let analysis = ModAnalysis(
            modName: "Windows Only Mod",
            version: "1.0.0",
            author: "Test",
            detectedTypes: [.red4ext],
            files: [
                AnalyzedFile(
                    relativePath: "red4ext/plugins/test.dll",
                    absolutePath: URL(fileURLWithPath: "/tmp/test.dll"),
                    fileType: .red4ext,
                    size: 1000
                )
            ],
            hasFomod: false,
            fomodConfig: nil
        )
        
        let result = await checker.check(analysis: analysis)
        
        XCTAssertFalse(result.isCompatible)
        XCTAssertTrue(result.issues.contains { $0.contains("DLL") })
    }
    
    func testCETModIncompatible() async {
        let analysis = ModAnalysis(
            modName: "CET Mod",
            version: "1.0.0",
            author: "Test",
            detectedTypes: [.cyber],
            files: [
                AnalyzedFile(
                    relativePath: "bin/x64/plugins/cyber_engine_tweaks/mods/test/init.lua",
                    absolutePath: URL(fileURLWithPath: "/tmp/init.lua"),
                    fileType: .cyber,
                    size: 500
                )
            ],
            hasFomod: false,
            fomodConfig: nil
        )
        
        let result = await checker.check(analysis: analysis)
        
        XCTAssertFalse(result.isCompatible)
        XCTAssertTrue(result.issues.contains { $0.contains("CET") || $0.contains("Cyber Engine Tweaks") })
    }
}

// MARK: - Error Tests

final class ErrorTests: XCTestCase {
    
    func testCyberModErrorDescriptions() {
        let gameNotFound = CyberModError.gameNotFound
        XCTAssertNotNil(gameNotFound.errorDescription)
        XCTAssertTrue(gameNotFound.errorDescription!.contains("not found"))
        
        let noProfile = CyberModError.noActiveProfile
        XCTAssertNotNil(noProfile.errorDescription)
        XCTAssertNotNil(noProfile.recoverySuggestion)
        
        let dependencyMissing = CyberModError.dependencyMissing(name: "TweakXL", version: "1.11.0")
        XCTAssertTrue(dependencyMissing.errorDescription!.contains("TweakXL"))
        XCTAssertTrue(dependencyMissing.errorDescription!.contains("1.11.0"))
    }
    
    func testValidationError() {
        let error = ValidationError(
            severity: .error,
            message: "Invalid record type",
            file: "tweaks.yaml",
            line: 15,
            column: 3
        )
        
        XCTAssertEqual(error.severity, .error)
        XCTAssertEqual(error.message, "Invalid record type")
        XCTAssertEqual(error.file, "tweaks.yaml")
        XCTAssertEqual(error.line, 15)
    }
}
