// DependencyResolverTests.swift - Tests for DependencyResolver

import XCTest
@testable import CyberModCore

final class DependencyResolverTests: XCTestCase {
    
    var resolver: DependencyResolver!
    
    override func setUp() async throws {
        resolver = DependencyResolver()
    }
    
    func testResolveDependencies_NoDependencies() async {
        let mod = Mod(
            name: "Test Mod",
            version: "1.0.0",
            type: [.tweakXL],
            stagingPath: URL(fileURLWithPath: "/tmp/test")
        )
        
        let result = await resolver.resolve(for: mod, installedMods: [])
        
        XCTAssertFalse(result.hasIssues)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertTrue(result.versionMismatch.isEmpty)
    }
    
    func testResolveDependencies_MissingRequired() async {
        let dependency = ModDependency(
            name: "TweakXL",
            nexusId: 4197,
            isRequired: true
        )
        
        let mod = Mod(
            name: "Test Mod",
            version: "1.0.0",
            type: [.tweakXL],
            stagingPath: URL(fileURLWithPath: "/tmp/test"),
            metadata: ModMetadata(dependencies: [dependency])
        )
        
        let result = await resolver.resolve(for: mod, installedMods: [])
        
        XCTAssertTrue(result.hasIssues)
        XCTAssertEqual(result.missing.count, 1)
        XCTAssertEqual(result.missing.first?.name, "TweakXL")
    }
    
    func testResolveDependencies_Satisfied() async {
        let dependency = ModDependency(
            name: "TweakXL",
            nexusId: 4197,
            isRequired: true
        )
        
        let installedMod = Mod(
            name: "TweakXL",
            version: "1.11.3",
            type: [.tweakXL],
            stagingPath: URL(fileURLWithPath: "/tmp/tweakxl"),
            metadata: ModMetadata()
        )
        
        let mod = Mod(
            name: "Test Mod",
            version: "1.0.0",
            type: [.tweakXL],
            stagingPath: URL(fileURLWithPath: "/tmp/test"),
            metadata: ModMetadata(dependencies: [dependency])
        )
        
        let result = await resolver.resolve(for: mod, installedMods: [installedMod])
        
        XCTAssertFalse(result.hasIssues)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertEqual(result.satisfied.count, 1)
    }
}
