// DependencyResolver.swift - Mod dependency resolution

import Foundation
import Logging

/// Result of dependency resolution
public struct DependencyResult: Sendable {
    public var satisfied: [ModDependency]
    public var missing: [ModDependency]
    public var versionMismatch: [(dependency: ModDependency, installed: String, required: String)]
    public var installOrder: [ModDependency] // Topological sort
    
    public init(
        satisfied: [ModDependency] = [],
        missing: [ModDependency] = [],
        versionMismatch: [(ModDependency, String, String)] = [],
        installOrder: [ModDependency] = []
    ) {
        self.satisfied = satisfied
        self.missing = missing
        self.versionMismatch = versionMismatch
        self.installOrder = installOrder
    }
    
    public var hasIssues: Bool {
        !missing.isEmpty || !versionMismatch.isEmpty
    }
}

/// Resolves mod dependencies and generates installation order
public actor DependencyResolver {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "com.cybermod.dependencyresolver")
    }
    
    /// Resolve dependencies for a mod against installed mods
    public func resolve(for mod: Mod, installedMods: [Mod]) -> DependencyResult {
        guard let dependencies = mod.metadata?.dependencies, !dependencies.isEmpty else {
            return DependencyResult()
        }
        
        var satisfied: [ModDependency] = []
        var missing: [ModDependency] = []
        var versionMismatch: [(ModDependency, String, String)] = []
        
        for dependency in dependencies {
            // Try to find matching installed mod
            if let installedMod = findMatchingMod(dependency: dependency, in: installedMods) {
                // Check version requirement
                if let versionReq = dependency.versionRequirement {
                    if !satisfiesVersion(installed: installedMod.version, requirement: versionReq) {
                        versionMismatch.append((
                            dependency,
                            installedMod.version,
                            versionReq
                        ))
                        continue
                    }
                }
                
                satisfied.append(dependency)
            } else {
                if dependency.isRequired {
                    missing.append(dependency)
                } else {
                    // Optional dependency not found - still satisfied
                    satisfied.append(dependency)
                }
            }
        }
        
        // Generate topological sort for installation order
        let installOrder = topologicalSort(dependencies: dependencies, installedMods: installedMods)
        
        return DependencyResult(
            satisfied: satisfied,
            missing: missing,
            versionMismatch: versionMismatch,
            installOrder: installOrder
        )
    }
    
    /// Find a matching mod for a dependency
    private func findMatchingMod(dependency: ModDependency, in mods: [Mod]) -> Mod? {
        // First try by Nexus ID (most reliable)
        if let nexusId = dependency.nexusId {
            if let match = mods.first(where: { $0.nexusId == nexusId }) {
                return match
            }
        }
        
        // Then try by name (case-insensitive, fuzzy matching)
        let dependencyNameLower = dependency.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for mod in mods {
            let modNameLower = mod.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Exact match
            if modNameLower == dependencyNameLower {
                return mod
            }
            
            // Contains match (for cases like "TweakXL" matching "TweakXL v1.11.3")
            if modNameLower.contains(dependencyNameLower) || dependencyNameLower.contains(modNameLower) {
                return mod
            }
        }
        
        return nil
    }
    
    /// Check if installed version satisfies requirement
    private func satisfiesVersion(installed: String, requirement: String) -> Bool {
        let installedVersion = parseVersion(installed)
        let req = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse requirement (e.g., ">= 1.11.0", "== 2.0.0", "< 3.0.0")
        if req.hasPrefix(">=") {
            let versionStr = String(req.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let requiredVersion = parseVersion(versionStr)
            return compareVersions(installedVersion, requiredVersion) >= 0
        } else if req.hasPrefix("<=") {
            let versionStr = String(req.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let requiredVersion = parseVersion(versionStr)
            return compareVersions(installedVersion, requiredVersion) <= 0
        } else if req.hasPrefix(">") {
            let versionStr = String(req.dropFirst(1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let requiredVersion = parseVersion(versionStr)
            return compareVersions(installedVersion, requiredVersion) > 0
        } else if req.hasPrefix("<") {
            let versionStr = String(req.dropFirst(1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let requiredVersion = parseVersion(versionStr)
            return compareVersions(installedVersion, requiredVersion) < 0
        } else if req.hasPrefix("==") || req.hasPrefix("=") {
            let versionStr = String(req.dropFirst(req.hasPrefix("==") ? 2 : 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let requiredVersion = parseVersion(versionStr)
            return compareVersions(installedVersion, requiredVersion) == 0
        } else {
            // No operator, assume >=
            let requiredVersion = parseVersion(req)
            return compareVersions(installedVersion, requiredVersion) >= 0
        }
    }
    
    /// Parse version string to comparable components
    private func parseVersion(_ version: String) -> [Int] {
        let components = version
            .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            .split(separator: ".")
            .compactMap { Int($0) }
        
        return components.isEmpty ? [0] : components
    }
    
    /// Compare two version arrays
    private func compareVersions(_ v1: [Int], _ v2: [Int]) -> Int {
        let maxLength = max(v1.count, v2.count)
        
        for i in 0..<maxLength {
            let component1 = i < v1.count ? v1[i] : 0
            let component2 = i < v2.count ? v2[i] : 0
            
            if component1 < component2 {
                return -1
            } else if component1 > component2 {
                return 1
            }
        }
        
        return 0
    }
    
    /// Generate topological sort for dependency installation order
    private func topologicalSort(dependencies: [ModDependency], installedMods: [Mod]) -> [ModDependency] {
        // Simple implementation: return dependencies in order
        // A more sophisticated implementation would handle dependency chains
        return dependencies
    }
    
    /// Generate auto-install plan for missing dependencies
    public func autoInstallPlan(missing: [ModDependency]) -> [ModDependency] {
        // Return missing dependencies that have Nexus IDs (can be auto-installed)
        return missing.filter { $0.nexusId != nil }
    }
}
