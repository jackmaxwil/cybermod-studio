// ModProfile.swift - Mod profile for organizing mod sets

import Foundation

/// A mod profile represents a specific configuration of enabled mods
public struct ModProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var gamePath: URL
    public var isActive: Bool
    public var createdAt: Date
    public var settings: ProfileSettings
    
    public init(
        id: UUID = UUID(),
        name: String,
        gamePath: URL,
        isActive: Bool = false,
        createdAt: Date = Date(),
        settings: ProfileSettings = ProfileSettings()
    ) {
        self.id = id
        self.name = name
        self.gamePath = gamePath
        self.isActive = isActive
        self.createdAt = createdAt
        self.settings = settings
    }
    
    /// Number of enabled mods in this profile (computed externally)
    public var enabledModCount: Int {
        // This would be populated from the database
        0
    }
}

/// Settings specific to a profile
public struct ProfileSettings: Codable, Hashable, Sendable {
    public var launchArguments: [String]
    public var environmentVariables: [String: String]
    public var skipIntroVideos: Bool
    public var enableDebugAgent: Bool
    
    public init(
        launchArguments: [String] = [],
        environmentVariables: [String: String] = [:],
        skipIntroVideos: Bool = false,
        enableDebugAgent: Bool = false
    ) {
        self.launchArguments = launchArguments
        self.environmentVariables = environmentVariables
        self.skipIntroVideos = skipIntroVideos
        self.enableDebugAgent = enableDebugAgent
    }
}

/// Load order entry for a mod in a profile
public struct ModLoadOrder: Codable, Hashable, Sendable {
    public var modId: UUID
    public var profileId: UUID
    public var order: Int
    public var isEnabled: Bool
    
    public init(modId: UUID, profileId: UUID, order: Int, isEnabled: Bool = true) {
        self.modId = modId
        self.profileId = profileId
        self.order = order
        self.isEnabled = isEnabled
    }
}
