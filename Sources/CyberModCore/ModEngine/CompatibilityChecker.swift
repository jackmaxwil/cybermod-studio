// CompatibilityChecker.swift - Check mod compatibility with macOS

import Foundation
import Logging

/// Checks if mods are compatible with macOS
public actor CompatibilityChecker {
    
    private let logger: Logger
    
    public init() {
        self.logger = Logger(label: "com.cybermod.compatibility")
    }
    
    /// Check compatibility of an analyzed mod
    public func check(analysis: ModAnalysis) async -> CompatibilityResult {
        var issues: [String] = []
        var warnings: [String] = []
        
        // Check for Windows-only DLLs
        let dllFiles = analysis.files.filter { $0.relativePath.hasSuffix(".dll") }
        if !dllFiles.isEmpty {
            let hasDylibEquivalent = analysis.files.contains { $0.relativePath.hasSuffix(".dylib") }
            if !hasDylibEquivalent {
                issues.append("Contains Windows DLL files without macOS dylib equivalent")
            } else {
                warnings.append("Contains both DLL and dylib files - using macOS version")
            }
        }
        
        // Check for CET (Cyber Engine Tweaks) - not supported on macOS
        if analysis.detectedTypes.contains(.cyber) {
            issues.append("Cyber Engine Tweaks (CET) mods are not supported on macOS")
        }
        
        // Check for known incompatible dependencies
        for file in analysis.files {
            let path = file.relativePath.lowercased()
            
            if path.contains("codeware") {
                issues.append("Codeware is not ported to macOS")
            }
            
            if path.contains("native settings") || path.contains("nativeui") {
                warnings.append("Native Settings UI may have limited functionality on macOS")
            }
        }
        
        // Check if required frameworks are present
        if analysis.detectedTypes.contains(.red4ext) {
            warnings.append("RED4ext plugin - ensure macOS port of RED4ext is installed")
        }
        
        if analysis.detectedTypes.contains(.tweakXL) {
            warnings.append("TweakXL mod - ensure macOS port of TweakXL is installed")
        }
        
        // On macOS the game never loads archive/pc/mod itself; ArchiveXL loads those archives.
        if analysis.detectedTypes.contains(.archive) || analysis.detectedTypes.contains(.archiveXL) {
            warnings.append("Archive mod - needs ArchiveXL (red4ext/plugins/ArchiveXL); without it the game ignores archive/pc/mod on macOS")
        }
        
        let isCompatible = issues.isEmpty
        
        logger.info("Compatibility check: \(isCompatible ? "PASS" : "FAIL") - \(issues.count) issues, \(warnings.count) warnings")
        
        return CompatibilityResult(
            isCompatible: isCompatible,
            issues: issues,
            warnings: warnings
        )
    }
    
    /// Quick check for a single file
    public func checkFile(path: String, type: ModType) -> CompatibilityResult {
        var issues: [String] = []
        var warnings: [String] = []
        
        if path.hasSuffix(".dll") {
            issues.append("Windows DLL file not compatible with macOS")
        }
        
        if type == .cyber {
            issues.append("CET mods not supported on macOS")
        }
        
        return CompatibilityResult(
            isCompatible: issues.isEmpty,
            issues: issues,
            warnings: warnings
        )
    }
}

/// Result of a compatibility check
public struct CompatibilityResult: Sendable {
    public let isCompatible: Bool
    public let issues: [String]
    public let warnings: [String]
    
    public init(isCompatible: Bool, issues: [String], warnings: [String]) {
        self.isCompatible = isCompatible
        self.issues = issues
        self.warnings = warnings
    }
    
    /// Overall compatibility level
    public var level: CompatibilityLevel {
        if isCompatible && warnings.isEmpty {
            return .fullyCompatible
        } else if isCompatible {
            return .compatibleWithWarnings
        } else {
            return .incompatible
        }
    }
}

/// Compatibility level enum
public enum CompatibilityLevel: String, Sendable {
    case fullyCompatible = "Fully Compatible"
    case compatibleWithWarnings = "Compatible (with warnings)"
    case incompatible = "Incompatible"
    
    public var color: String {
        switch self {
        case .fullyCompatible: return "green"
        case .compatibleWithWarnings: return "orange"
        case .incompatible: return "red"
        }
    }
}
