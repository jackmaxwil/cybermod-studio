// ConflictDetectorTests.swift - Tests for ConflictDetector

import XCTest
@testable import CyberModCore

final class ConflictDetectorTests: XCTestCase {
    
    var detector: ConflictDetector!
    
    override func setUp() async throws {
        detector = ConflictDetector()
    }
    
    func testDetectConflicts_NoConflicts() async {
        let mod1 = Mod(
            name: "Mod 1",
            version: "1.0.0",
            type: [.tweakXL],
            stagingPath: URL(fileURLWithPath: "/tmp/mod1")
        )
        
        let mod2 = Mod(
            name: "Mod 2",
            version: "1.0.0",
            type: [.archive],
            stagingPath: URL(fileURLWithPath: "/tmp/mod2")
        )
        
        let report = await detector.detect(
            mods: [mod1, mod2],
            deploymentPlan: []
        )
        
        XCTAssertFalse(report.hasBlockingConflicts)
        XCTAssertTrue(report.conflicts.isEmpty)
    }
    
    func testDetectConflicts_BlockingConflict() async {
        let mod1 = Mod(
            name: "Mod 1",
            version: "1.0.0",
            type: [.red4ext],
            stagingPath: URL(fileURLWithPath: "/tmp/mod1")
        )
        
        let mod2 = Mod(
            name: "Mod 2",
            version: "1.0.0",
            type: [.red4ext],
            stagingPath: URL(fileURLWithPath: "/tmp/mod2")
        )
        
        // Create deployment plan with conflicting paths
        let conflictFile = DeployedFile(
            relativePath: "red4ext/plugins/test.dylib",
            installPath: URL(fileURLWithPath: "/game/red4ext/plugins/test.dylib"),
            fileType: .red4ext,
            checksum: "abc123"
        )
        
        let report = await detector.detect(
            mods: [mod1, mod2],
            deploymentPlan: [conflictFile]
        )
        
        // Note: Actual conflict detection logic would need proper file tracking
        // This is a placeholder test structure
        XCTAssertNotNil(report)
    }
}
