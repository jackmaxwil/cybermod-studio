// Mod.swift - Core mod data types

import Foundation

/// Represents an installed mod
public struct Mod: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var nexusId: Int?
    public var name: String
    public var version: String
    public var author: String?
    public var description: String?
    public var type: Set<ModType>
    public var isEnabled: Bool
    public var installedAt: Date
    public var stagingPath: URL
    public var metadata: ModMetadata?
    
    public init(
        id: UUID = UUID(),
        nexusId: Int? = nil,
        name: String,
        version: String,
        author: String? = nil,
        description: String? = nil,
        type: Set<ModType>,
        isEnabled: Bool = true,
        installedAt: Date = Date(),
        stagingPath: URL,
        metadata: ModMetadata? = nil
    ) {
        self.id = id
        self.nexusId = nexusId
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.type = type
        self.isEnabled = isEnabled
        self.installedAt = installedAt
        self.stagingPath = stagingPath
        self.metadata = metadata
    }
}

/// Type of mod content
public enum ModType: String, Codable, CaseIterable, Hashable, Sendable {
    case archive      // .archive files (game resources)
    case tweakXL      // TweakXL YAML files
    case archiveXL    // ArchiveXL .xl config files
    case redscript    // .reds Redscript files
    case red4ext      // .dylib native plugins
    case cyber        // CET Lua scripts (Windows only)
    case unknown
    
    /// Whether this mod type is supported on macOS
    public var isMacOSCompatible: Bool {
        switch self {
        case .archive, .tweakXL, .archiveXL, .redscript, .red4ext:
            return true
        case .cyber, .unknown:
            return false
        }
    }
    
    /// Installation directory relative to game root
    public var installDirectory: String {
        switch self {
        case .archive:
            return "archive/pc/mod"
        case .tweakXL:
            return "r6/tweaks"
        case .archiveXL:
            return "archive/pc/mod"
        case .redscript:
            return "r6/scripts"
        case .red4ext:
            return "red4ext/plugins"
        case .cyber:
            return "bin/x64/plugins/cyber_engine_tweaks/mods"
        case .unknown:
            return ""
        }
    }
    
    /// File extensions associated with this mod type
    public var fileExtensions: Set<String> {
        switch self {
        case .archive:
            return ["archive"]
        case .tweakXL:
            return ["yaml", "yml"]
        case .archiveXL:
            return ["xl"]
        case .redscript:
            return ["reds"]
        case .red4ext:
            return ["dylib", "dll"]
        case .cyber:
            return ["lua"]
        case .unknown:
            return []
        }
    }
}

/// Additional mod metadata
public struct ModMetadata: Codable, Hashable, Sendable {
    public var nexusUrl: URL?
    public var homepage: URL?
    public var category: String?
    public var tags: [String]
    public var dependencies: [ModDependency]
    public var checksum: String?
    public var originalArchiveName: String?
    
    public init(
        nexusUrl: URL? = nil,
        homepage: URL? = nil,
        category: String? = nil,
        tags: [String] = [],
        dependencies: [ModDependency] = [],
        checksum: String? = nil,
        originalArchiveName: String? = nil
    ) {
        self.nexusUrl = nexusUrl
        self.homepage = homepage
        self.category = category
        self.tags = tags
        self.dependencies = dependencies
        self.checksum = checksum
        self.originalArchiveName = originalArchiveName
    }
}

/// Mod dependency specification
public struct ModDependency: Codable, Hashable, Sendable {
    public var name: String
    public var nexusId: Int?
    public var versionRequirement: String?
    public var isRequired: Bool
    
    public init(
        name: String,
        nexusId: Int? = nil,
        versionRequirement: String? = nil,
        isRequired: Bool = true
    ) {
        self.name = name
        self.nexusId = nexusId
        self.versionRequirement = versionRequirement
        self.isRequired = isRequired
    }
}

/// Source from which a mod is being installed
public enum ModSource: Sendable {
    case local(url: URL)
    case nexus(modId: Int, fileId: Int)
    case url(URL)
}

/// Result of mod installation
public struct InstalledMod: Sendable {
    public let mod: Mod
    public let deployedFiles: [DeployedFile]
    public let warnings: [String]
    
    public init(mod: Mod, deployedFiles: [DeployedFile], warnings: [String] = []) {
        self.mod = mod
        self.deployedFiles = deployedFiles
        self.warnings = warnings
    }
}

/// A file deployed to the game directory
public struct DeployedFile: Codable, Hashable, Sendable {
    public let relativePath: String
    public let installPath: URL
    public let fileType: ModType
    public let checksum: String
    
    public init(relativePath: String, installPath: URL, fileType: ModType, checksum: String) {
        self.relativePath = relativePath
        self.installPath = installPath
        self.fileType = fileType
        self.checksum = checksum
    }
}
