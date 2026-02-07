// ConflictDetector.swift - File conflict detection and resolution

import Foundation
import Logging

/// Represents a file conflict between mods
public struct FileConflict: Sendable, Identifiable {
    public let id: UUID
    public var filePath: String
    public var mods: [Mod] // All mods that deploy to this path
    public var winner: Mod? // Based on current load order
    
    public init(id: UUID = UUID(), filePath: String, mods: [Mod], winner: Mod? = nil) {
        self.id = id
        self.filePath = filePath
        self.mods = mods
        self.winner = winner
    }
}

/// Conflict detection report
public struct ConflictReport: Sendable {
    public var conflicts: [FileConflict]
    public var hasBlockingConflicts: Bool
    public var suggestions: [String]
    
    public init(
        conflicts: [FileConflict] = [],
        hasBlockingConflicts: Bool = false,
        suggestions: [String] = []
    ) {
        self.conflicts = conflicts
        self.hasBlockingConflicts = hasBlockingConflicts
        self.suggestions = suggestions
    }
}

/// Detects file conflicts between mods
public actor ConflictDetector {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "com.cybermod.conflictdetector")
    }
    
    /// Detect conflicts in a deployment plan
    public func detect(mods: [Mod], deploymentPlan: [DeployedFile]) -> ConflictReport {
        // Group deployed files by install path
        var pathToMods: [String: [Mod]] = [:]
        var pathToFiles: [String: [DeployedFile]] = [:]
        
        // Build index of mods and their deployed files
        for mod in mods where mod.isEnabled {
            // Get deployed files for this mod (would come from database in real implementation)
            // For now, we'll use the deployment plan
            let modFiles = deploymentPlan.filter { file in
                // Match files to mods (simplified - would need mod ID tracking)
                true // Placeholder
            }
            
            for file in modFiles {
                let path = file.installPath.path
                
                if pathToMods[path] == nil {
                    pathToMods[path] = []
                    pathToFiles[path] = []
                }
                
                pathToMods[path]?.append(mod)
                pathToFiles[path]?.append(file)
            }
        }
        
        // Find conflicts (paths with multiple mods)
        var conflicts: [FileConflict] = []
        var blockingConflicts = false
        
        for (path, modsForPath) in pathToMods where modsForPath.count > 1 {
            // Determine winner based on load order (mods list order)
            let winner = modsForPath.first // First mod wins
            
            let conflict = FileConflict(
                filePath: path,
                mods: modsForPath,
                winner: winner
            )
            
            conflicts.append(conflict)
            
            // Check if this is a blocking conflict (critical files)
            if isBlockingConflict(path: path) {
                blockingConflicts = true
            }
        }
        
        // Generate suggestions
        var suggestions: [String] = []
        
        if !conflicts.isEmpty {
            suggestions.append("\(conflicts.count) file conflict(s) detected")
            
            if blockingConflicts {
                suggestions.append("Some conflicts affect critical game files - manual resolution recommended")
            } else {
                suggestions.append("Conflicts can be resolved by adjusting mod load order")
            }
            
            // Group conflicts by mod pairs
            let modPairs = getModPairs(from: conflicts)
            if modPairs.count > 0 {
                suggestions.append("Consider reviewing load order for: \(modPairs.prefix(3).joined(separator: ", "))")
            }
        }
        
        return ConflictReport(
            conflicts: conflicts,
            hasBlockingConflicts: blockingConflicts,
            suggestions: suggestions
        )
    }
    
    /// Resolve conflicts by load order
    public func resolveByLoadOrder(conflicts: [FileConflict], order: [UUID]) -> [FileConflict] {
        return conflicts.map { conflict in
            var resolved = conflict
            
            // Find winner based on load order (earlier in list = higher priority)
            if let winner = conflict.mods.min(by: { mod1, mod2 in
                let index1 = order.firstIndex(of: mod1.id) ?? Int.max
                let index2 = order.firstIndex(of: mod2.id) ?? Int.max
                return index1 < index2
            }) {
                resolved.winner = winner
            }
            
            return resolved
        }
    }
    
    /// Check if a conflict is blocking (affects critical files)
    private func isBlockingConflict(path: String) -> Bool {
        let blockingPatterns = [
            "red4ext/plugins",
            "r6/config",
            "engine/config",
            ".exe",
            ".dylib"
        ]
        
        return blockingPatterns.contains { pattern in
            path.contains(pattern)
        }
    }
    
    /// Get unique mod pairs from conflicts
    private func getModPairs(from conflicts: [FileConflict]) -> [String] {
        var pairs: Set<String> = []
        
        for conflict in conflicts {
            let modNames = conflict.mods.map { $0.name }.sorted()
            if modNames.count >= 2 {
                for i in 0..<modNames.count - 1 {
                    for j in (i+1)..<modNames.count {
                        let pair = "\(modNames[i]) & \(modNames[j])"
                        pairs.insert(pair)
                    }
                }
            }
        }
        
        return Array(pairs)
    }
    
    /// Detect conflicts for a single mod being installed
    public func detectForNewMod(newMod: Mod, existingMods: [Mod], deploymentPlan: [DeployedFile]) -> ConflictReport {
        // Combine new mod with existing mods
        let allMods = existingMods + [newMod]
        
        // Detect conflicts
        return detect(mods: allMods, deploymentPlan: deploymentPlan)
    }
    
    /// Get conflicts for a specific mod
    public func getConflictsForMod(_ mod: Mod, allConflicts: [FileConflict]) -> [FileConflict] {
        return allConflicts.filter { conflict in
            conflict.mods.contains { $0.id == mod.id }
        }
    }
}
