// ModManager.swift - Central mod management actor

import Foundation
import Logging

/// Central manager for all mod operations
public actor ModManager {
    
    // MARK: - Dependencies
    
    private let database: ModDatabase
    private let fileManager: ModFileManager
    private let compatibilityChecker: CompatibilityChecker
    private let dependencyResolver: DependencyResolver
    private let conflictDetector: ConflictDetector
    private let logger: Logger
    
    // MARK: - State
    
    private var activeProfile: ModProfile?
    
    // MARK: - Singleton
    
    public static let shared = ModManager()
    
    // MARK: - Initialization
    
    public init(
        database: ModDatabase? = nil,
        fileManager: ModFileManager? = nil,
        compatibilityChecker: CompatibilityChecker? = nil,
        dependencyResolver: DependencyResolver? = nil,
        conflictDetector: ConflictDetector? = nil
    ) {
        self.database = database ?? ModDatabase.shared
        self.fileManager = fileManager ?? ModFileManager.shared
        self.compatibilityChecker = compatibilityChecker ?? CompatibilityChecker()
        self.dependencyResolver = dependencyResolver ?? DependencyResolver()
        self.conflictDetector = conflictDetector ?? ConflictDetector()
        self.logger = Logger(label: "com.cybermod.modmanager")
    }
    
    // MARK: - Mod Listing
    
    /// List all installed mods
    public func listMods() async throws -> [Mod] {
        try await database.listMods()
    }
    
    /// Get a specific mod by ID
    public func getMod(id: UUID) async throws -> Mod? {
        try await database.getMod(id: id)
    }
    
    /// Search mods by name
    public func searchMods(query: String) async throws -> [Mod] {
        try await database.searchMods(query: query)
    }
    
    // MARK: - Installation
    
    /// Install a mod from the given source
    public func install(
        _ source: ModSource,
        profile: ModProfile? = nil,
        options: InstallOptions = .default
    ) async throws -> InstalledMod {
        let targetProfile = profile ?? activeProfile
        guard let targetProfile else {
            throw ModManagerError.noActiveProfile
        }
        
        logger.info("Installing mod from source: \(source)")
        
        // Step 1: Extract to staging
        let stagingDir = try await fileManager.extract(source: source)
        logger.debug("Extracted to staging: \(stagingDir.path)")
        
        // Step 2: Analyze contents
        let analysis = try await fileManager.analyze(directory: stagingDir)
        logger.debug("Analysis complete: \(analysis.detectedTypes)")
        
        // Step 3: Check compatibility
        let compatibility = await compatibilityChecker.check(analysis: analysis)
        if !compatibility.isCompatible && !options.forceInstall {
            throw ModManagerError.incompatible(reasons: compatibility.issues)
        }
        
        // Step 3.5: Check dependencies
        let modToInstall = Mod(
            name: analysis.modName ?? stagingDir.lastPathComponent,
            version: analysis.version ?? "1.0.0",
            author: analysis.author,
            type: analysis.detectedTypes,
            stagingPath: stagingDir
        )
        let installedMods = try await database.listMods()
        let dependencyResult = await dependencyResolver.resolve(for: modToInstall, installedMods: installedMods)
        
        if dependencyResult.hasIssues && !options.forceInstall {
            var reasons: [String] = []
            if !dependencyResult.missing.isEmpty {
                let missingNames = dependencyResult.missing.map { $0.name }.joined(separator: ", ")
                reasons.append("Missing required dependencies: \(missingNames)")
            }
            if !dependencyResult.versionMismatch.isEmpty {
                for (dep, installed, required) in dependencyResult.versionMismatch {
                    reasons.append("\(dep.name): installed \(installed), required \(required)")
                }
            }
            throw ModManagerError.dependencyMissing(name: reasons.joined(separator: "; "))
        }
        
        // Step 4: Handle FOMOD if present
        var filesToDeploy = analysis.files
        if analysis.hasFomod {
            guard let choices = options.fomodChoices else {
                throw ModManagerError.fomodRequired(config: analysis.fomodConfig!)
            }
            filesToDeploy = try await resolveFomodChoices(
                stagingDir: stagingDir,
                config: analysis.fomodConfig!,
                choices: choices
            )
        }
        
        // Step 5: Check for conflicts before deploying
        let conflictReport = await conflictDetector.detectForNewMod(
            newMod: modToInstall,
            existingMods: installedMods.filter { $0.isEnabled },
            deploymentPlan: [] // Will be populated after deployment
        )
        
        if conflictReport.hasBlockingConflicts && !options.forceInstall {
            let conflictFiles = conflictReport.conflicts.prefix(5).map { $0.filePath }.joined(separator: ", ")
            throw ModManagerError.installationFailed(reason: "Blocking conflicts detected: \(conflictFiles)")
        }
        
        // Step 6: Deploy files
        let deployedFiles = try await fileManager.deploy(
            files: filesToDeploy,
            from: stagingDir,
            to: targetProfile.gamePath
        )
        logger.info("Deployed \(deployedFiles.count) files")
        
        // Step 7: Record in database
        let mod = Mod(
            name: analysis.modName ?? stagingDir.lastPathComponent,
            version: analysis.version ?? "1.0.0",
            author: analysis.author,
            type: analysis.detectedTypes,
            stagingPath: stagingDir
        )
        
        try await database.insertMod(mod)
        try await database.associateModWithProfile(modId: mod.id, profileId: targetProfile.id)
        
        logger.info("Installation complete: \(mod.name)")
        
        return InstalledMod(
            mod: mod,
            deployedFiles: deployedFiles,
            warnings: compatibility.warnings
        )
    }
    
    /// Uninstall a mod
    public func uninstall(_ mod: Mod) async throws {
        logger.info("Uninstalling mod: \(mod.name)")
        
        // Get deployed files
        let files = try await database.getDeployedFiles(forMod: mod.id)
        
        // Remove deployed files
        for file in files {
            try await fileManager.removeFile(at: file.installPath)
        }
        
        // Remove staging directory
        try await fileManager.removeDirectory(at: mod.stagingPath)
        
        // Remove from database
        try await database.deleteMod(id: mod.id)
        
        logger.info("Uninstallation complete: \(mod.name)")
    }
    
    // MARK: - Enable/Disable
    
    /// Enable a mod (deploy files from staging)
    public func enable(_ mod: Mod) async throws {
        guard !mod.isEnabled else { return }
        
        let profile = try await getActiveProfile()
        
        logger.info("Enabling mod: \(mod.name)")
        
        // Re-deploy files from staging
        let files = try await fileManager.listFiles(in: mod.stagingPath)
        let deployedFiles = try await fileManager.deploy(
            files: files,
            from: mod.stagingPath,
            to: profile.gamePath
        )
        
        // Update database
        var updatedMod = mod
        updatedMod.isEnabled = true
        try await database.updateMod(updatedMod)
        try await database.recordDeployedFiles(deployedFiles, forMod: mod.id)
        
        logger.info("Enabled mod: \(mod.name)")
    }
    
    /// Disable a mod (remove deployed files, keep staging)
    public func disable(_ mod: Mod) async throws {
        guard mod.isEnabled else { return }
        
        logger.info("Disabling mod: \(mod.name)")
        
        // Get and remove deployed files
        let files = try await database.getDeployedFiles(forMod: mod.id)
        for file in files {
            try await fileManager.removeFile(at: file.installPath)
        }
        
        // Update database
        var updatedMod = mod
        updatedMod.isEnabled = false
        try await database.updateMod(updatedMod)
        try await database.clearDeployedFiles(forMod: mod.id)
        
        logger.info("Disabled mod: \(mod.name)")
    }
    
    // MARK: - Profiles
    
    /// List all mod profiles
    public func listProfiles() async throws -> [ModProfile] {
        try await database.listProfiles()
    }
    
    /// Get the currently active profile
    public func getActiveProfile() async throws -> ModProfile {
        if let profile = activeProfile {
            return profile
        }
        
        if let profile = try await database.getActiveProfile() {
            activeProfile = profile
            return profile
        }
        
        throw ModManagerError.noActiveProfile
    }
    
    /// Set the active profile
    public func setActiveProfile(_ profile: ModProfile) async throws {
        // Deactivate current profile
        if let current = activeProfile {
            var updated = current
            updated.isActive = false
            try await database.updateProfile(updated)
        }
        
        // Activate new profile
        var updated = profile
        updated.isActive = true
        try await database.updateProfile(updated)
        
        activeProfile = updated
    }
    
    /// Create a new profile
    public func createProfile(name: String, gamePath: URL) async throws -> ModProfile {
        let profile = ModProfile(
            name: name,
            gamePath: gamePath,
            isActive: false
        )
        try await database.insertProfile(profile)
        return profile
    }
    
    // MARK: - Private Helpers
    
    private func resolveFomodChoices(
        stagingDir: URL,
        config: FomodConfig,
        choices: [FomodChoice]
    ) async throws -> [AnalyzedFile] {
        // Re-parse FOMOD config to get extended version
        let parser = FomodParser(logger: logger)
        let extendedConfig = try parser.parse(fomodDir: stagingDir)
        
        // Resolve files based on choices
        let resolvedFiles = try parser.resolveFiles(
            config: extendedConfig,
            choices: choices,
            baseDir: stagingDir
        )
        
        // Convert to AnalyzedFile format
        var analyzedFiles: [AnalyzedFile] = []
        let fm = FileManager.default
        
        for (source, destination) in resolvedFiles {
            guard let resourceValues = try? source.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            let ext = source.pathExtension.lowercased()
            let relativePath = source.path.replacingOccurrences(of: stagingDir.path + "/", with: "")
            
            let fileType = detectModType(extension: ext, path: relativePath)
            let size = (try? fm.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
            
            analyzedFiles.append(AnalyzedFile(
                relativePath: destination.isEmpty ? relativePath : destination,
                absolutePath: source,
                fileType: fileType,
                size: size
            ))
        }
        
        return analyzedFiles
    }
    
    private func detectModType(extension ext: String, path: String) -> ModType {
        for type in ModType.allCases {
            if type.fileExtensions.contains(ext) {
                if ext == "dll" {
                    return .red4ext // Will be flagged as incompatible later
                }
                return type
            }
        }
        
        // Check by path patterns
        if path.contains("r6/tweaks") || path.contains("r6\\tweaks") {
            return .tweakXL
        }
        if path.contains("r6/scripts") || path.contains("r6\\scripts") {
            return .redscript
        }
        if path.contains("red4ext/plugins") || path.contains("red4ext\\plugins") {
            return .red4ext
        }
        
        return .unknown
    }
}

// MARK: - Supporting Types

/// Options for mod installation
public struct InstallOptions: Sendable {
    public var fomodChoices: [FomodChoice]?
    public var forceInstall: Bool
    public var createBackup: Bool
    
    public static let `default` = InstallOptions(
        fomodChoices: nil,
        forceInstall: false,
        createBackup: true
    )
    
    public init(
        fomodChoices: [FomodChoice]? = nil,
        forceInstall: Bool = false,
        createBackup: Bool = true
    ) {
        self.fomodChoices = fomodChoices
        self.forceInstall = forceInstall
        self.createBackup = createBackup
    }
}

/// FOMOD installer choice
public struct FomodChoice: Codable, Sendable {
    public var stepId: String
    public var groupId: String
    public var optionIds: [String]
    
    public init(stepId: String, groupId: String, optionIds: [String]) {
        self.stepId = stepId
        self.groupId = groupId
        self.optionIds = optionIds
    }
}

/// FOMOD configuration (parsed from ModuleConfig.xml)
public struct FomodConfig: Sendable {
    public var moduleName: String
    public var steps: [FomodStep]
}

/// FOMOD installation step
public struct FomodStep: Sendable {
    public var id: String
    public var name: String
    public var groups: [FomodGroup]
}

/// FOMOD option group
public struct FomodGroup: Sendable {
    public var id: String
    public var name: String
    public var type: FomodGroupType
    public var options: [FomodOption]
}

/// FOMOD group selection type
public enum FomodGroupType: String, Sendable {
    case selectExactlyOne
    case selectAtMostOne
    case selectAtLeastOne
    case selectAll
    case selectAny
}

/// FOMOD selectable option
public struct FomodOption: Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var imagePath: String?
    public var files: [String]
}

// MARK: - Errors

/// Errors thrown by ModManager
public enum ModManagerError: LocalizedError {
    case noActiveProfile
    case modNotFound(UUID)
    case incompatible(reasons: [String])
    case fomodRequired(config: FomodConfig)
    case installationFailed(reason: String)
    case dependencyMissing(name: String)
    
    public var errorDescription: String? {
        switch self {
        case .noActiveProfile:
            return "No active mod profile. Please create or select a profile."
        case .modNotFound(let id):
            return "Mod with ID \(id) not found."
        case .incompatible(let reasons):
            return "Mod is incompatible: \(reasons.joined(separator: ", "))"
        case .fomodRequired:
            return "This mod requires FOMOD installer choices."
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .dependencyMissing(let name):
            return "Required dependency missing: \(name)"
        }
    }
}
