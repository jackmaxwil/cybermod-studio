// ModFileManager.swift - File system operations for mods

import Foundation
import Logging
import ZIPFoundation

/// Manages file system operations for mod installation
public actor ModFileManager {
    
    // MARK: - Dependencies
    
    private let fm = FileManager.default
    private let logger: Logger
    private let stagingBase: URL
    
    // MARK: - Singleton
    
    public static let shared = ModFileManager()
    
    // MARK: - Initialization
    
    public init(stagingBase: URL? = nil) {
        self.logger = Logger(label: "com.cybermod.filemanager")
        
        if let base = stagingBase {
            self.stagingBase = base
        } else {
            // Default to Application Support
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.stagingBase = appSupport.appendingPathComponent("CyberModStudio/staging")
        }
        
        // Ensure staging directory exists
        try? fm.createDirectory(at: self.stagingBase, withIntermediateDirectories: true)
    }
    
    // MARK: - Extraction
    
    /// Extract a mod from its source to a staging directory
    public func extract(source: ModSource) async throws -> URL {
        switch source {
        case .local(let url):
            return try await extractArchive(at: url)
        case .nexus, .url:
            // These would need to be downloaded first
            throw FileManagerError.unsupportedSource
        }
    }
    
    /// Extract an archive to a staging directory
    private func extractArchive(at url: URL) async throws -> URL {
        let stagingDir = stagingBase.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "zip":
            try await extractZip(at: url, to: stagingDir)
        case "7z":
            try await extract7z(at: url, to: stagingDir)
        case "rar":
            try await extractRar(at: url, to: stagingDir)
        default:
            // Not an archive - might be a single file
            let destPath = stagingDir.appendingPathComponent(url.lastPathComponent)
            try fm.copyItem(at: url, to: destPath)
        }
        
        logger.debug("Extracted archive to: \(stagingDir.path)")
        return stagingDir
    }
    
    private func extractZip(at url: URL, to destination: URL) async throws {
        try fm.unzipItem(at: url, to: destination)
    }
    
    private func extract7z(at url: URL, to destination: URL) async throws {
        // Use 7z command-line tool
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/7z")
        process.arguments = ["x", "-o\(destination.path)", url.path]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw FileManagerError.extractionFailed("7z extraction failed")
        }
    }
    
    private func extractRar(at url: URL, to destination: URL) async throws {
        // Use unrar or unar command-line tool
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unar")
        process.arguments = ["-o", destination.path, url.path]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw FileManagerError.extractionFailed("RAR extraction failed")
        }
    }
    
    // MARK: - Analysis
    
    /// Analyze the contents of a staging directory
    public func analyze(directory: URL) async throws -> ModAnalysis {
        var detectedTypes: Set<ModType> = []
        var files: [AnalyzedFile] = []
        var hasFomod = false
        var fomodConfig: FomodConfig?
        var modName: String?
        var version: String?
        var author: String?
        
        // Check for FOMOD and parse if present
        let fomodPath = directory.appendingPathComponent("fomod")
        if fm.fileExists(atPath: fomodPath.path) {
            let moduleConfigPath = fomodPath.appendingPathComponent("ModuleConfig.xml")
            // Try case-insensitive search
            var actualConfigPath = moduleConfigPath
            if !fm.fileExists(atPath: moduleConfigPath.path) {
                if let contents = try? fm.contentsOfDirectory(at: fomodPath, includingPropertiesForKeys: nil) {
                    for file in contents {
                        if file.lastPathComponent.lowercased() == "moduleconfig.xml" {
                            actualConfigPath = file
                            break
                        }
                    }
                }
            }
            
            if fm.fileExists(atPath: actualConfigPath.path) {
                hasFomod = true
                
                // Parse FOMOD config
                do {
                    let parser = FomodParser(logger: logger)
                    let extendedConfig = try parser.parse(fomodDir: directory)
                    fomodConfig = extendedConfig.toFomodConfig()
                    
                    // Extract mod info from FOMOD
                    if modName == nil {
                        modName = extendedConfig.info.name
                    }
                    if version == nil {
                        version = extendedConfig.info.version
                    }
                    if author == nil {
                        author = extendedConfig.info.author
                    }
                } catch {
                    logger.warning("Failed to parse FOMOD config: \(error.localizedDescription)")
                }
            }
        }
        
        // Enumerate all files
        let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            let relativePath = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
            
            // Detect mod type from extension
            let fileType = detectModType(extension: ext, path: relativePath)
            if fileType != .unknown {
                detectedTypes.insert(fileType)
            }
            
            files.append(AnalyzedFile(
                relativePath: relativePath,
                absolutePath: fileURL,
                fileType: fileType,
                size: (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            ))
        }
        
        // Try to detect mod name from directory structure
        if modName == nil {
            modName = directory.lastPathComponent
        }
        
        return ModAnalysis(
            modName: modName,
            version: version,
            author: author,
            detectedTypes: detectedTypes,
            files: files,
            hasFomod: hasFomod,
            fomodConfig: fomodConfig
        )
    }
    
    private func detectModType(extension ext: String, path: String) -> ModType {
        // Check by extension first
        for type in ModType.allCases {
            if type.fileExtensions.contains(ext) {
                // Special handling for dylib vs dll
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
    
    // MARK: - Deployment
    
    /// Deploy files from staging to game directory
    public func deploy(
        files: [AnalyzedFile],
        from stagingDir: URL,
        to gamePath: URL
    ) async throws -> [DeployedFile] {
        var deployedFiles: [DeployedFile] = []
        
        for file in files where file.fileType != .unknown {
            let installDir = gamePath.appendingPathComponent(file.fileType.installDirectory)
            
            // Determine install path based on mod structure
            let installPath = determineInstallPath(
                file: file,
                installDir: installDir
            )
            
            // Create parent directory
            try fm.createDirectory(
                at: installPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Deploy using hardlink (preferred) or copy
            try deployFile(from: file.absolutePath, to: installPath)
            
            // Calculate checksum
            let checksum = try calculateChecksum(for: file.absolutePath)
            
            deployedFiles.append(DeployedFile(
                relativePath: file.relativePath,
                installPath: installPath,
                fileType: file.fileType,
                checksum: checksum
            ))
            
            // Remove quarantine attribute (macOS)
            removeQuarantine(at: installPath)
        }
        
        return deployedFiles
    }
    
    private func determineInstallPath(file: AnalyzedFile, installDir: URL) -> URL {
        // If file is already in a proper structure, preserve it
        // Find the relevant part of the path (after archive/pc/mod, r6/tweaks, etc.)
        // For now, just use the filename
        let filename = file.absolutePath.lastPathComponent
        return installDir.appendingPathComponent(filename)
    }
    
    private func deployFile(from source: URL, to destination: URL) throws {
        // Try hardlink first (saves space)
        do {
            try fm.linkItem(at: source, to: destination)
            logger.debug("Hardlinked: \(source.lastPathComponent)")
        } catch {
            // Fall back to copy
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
            logger.debug("Copied: \(source.lastPathComponent)")
        }
    }
    
    private func calculateChecksum(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        // Simple hash for now - could use SHA256
        return String(format: "%08x", data.hashValue)
    }
    
    private func removeQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }
    
    // MARK: - Removal
    
    /// Remove a single file
    public func removeFile(at url: URL) async throws {
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
            logger.debug("Removed file: \(url.path)")
            
            // Clean up empty parent directories
            try cleanEmptyDirectories(from: url.deletingLastPathComponent())
        }
    }
    
    /// Remove a directory and its contents
    public func removeDirectory(at url: URL) async throws {
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
            logger.debug("Removed directory: \(url.path)")
        }
    }
    
    private func cleanEmptyDirectories(from url: URL) throws {
        let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        if contents?.isEmpty == true {
            try fm.removeItem(at: url)
            try cleanEmptyDirectories(from: url.deletingLastPathComponent())
        }
    }
    
    // MARK: - Listing
    
    /// List all files in a directory
    public func listFiles(in directory: URL) async throws -> [AnalyzedFile] {
        let analysis = try await analyze(directory: directory)
        return analysis.files
    }
}

// MARK: - Supporting Types

/// Result of analyzing a mod directory
public struct ModAnalysis: Sendable {
    public var modName: String?
    public var version: String?
    public var author: String?
    public var detectedTypes: Set<ModType>
    public var files: [AnalyzedFile]
    public var hasFomod: Bool
    public var fomodConfig: FomodConfig?
}

/// An analyzed file in a mod
public struct AnalyzedFile: Sendable {
    public var relativePath: String
    public var absolutePath: URL
    public var fileType: ModType
    public var size: Int
}

// MARK: - Errors

/// Errors thrown by ModFileManager
public enum FileManagerError: LocalizedError {
    case unsupportedSource
    case extractionFailed(String)
    case fileNotFound(URL)
    case permissionDenied(URL)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "Unsupported mod source type"
        case .extractionFailed(let reason):
            return "Archive extraction failed: \(reason)"
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .permissionDenied(let url):
            return "Permission denied: \(url.path)"
        }
    }
}
