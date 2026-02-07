// NexusModels.swift - Nexus Mods API response models

import Foundation

// MARK: - User Models

/// Nexus Mods user information
public struct NexusUser: Codable, Sendable {
    public var userId: Int
    public var name: String
    public var email: String?
    public var isPremium: Bool
    public var isSupporter: Bool
    public var profileUrl: URL?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case email
        case isPremium = "is_premium"
        case isSupporter = "is_supporter"
        case profileUrl = "profile_url"
    }
}

// MARK: - Game Models

/// Nexus Mods game information
public struct NexusGame: Codable, Sendable {
    public var id: Int
    public var name: String
    public var domainName: String
    public var approvedDate: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case domainName = "domain_name"
        case approvedDate = "approved_date"
    }
}

/// Mod category
public struct NexusCategory: Codable, Sendable {
    public var id: Int
    public var name: String
    public var parentCategory: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentCategory = "parent_category"
    }
}

// MARK: - Mod Models

/// Nexus Mods mod information
public struct NexusMod: Codable, Sendable, Identifiable {
    public var id: Int
    public var nexusModId: Int
    public var name: String
    public var summary: String?
    public var description: String?
    public var author: String?
    public var pictureUrl: URL?
    public var endorsements: Int
    public var totalDownloads: Int
    public var uniqueDownloads: Int
    public var updatedAt: Date?
    public var createdAt: Date?
    public var category: NexusCategory?
    public var requirements: [NexusRequirement]?
    public var nexusUrl: URL?
    
    enum CodingKeys: String, CodingKey {
        case id
        case nexusModId = "mod_id"
        case name
        case summary
        case description
        case author
        case pictureUrl = "picture_url"
        case endorsements
        case totalDownloads = "total_downloads"
        case uniqueDownloads = "mod_unique_downloads"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case category
        case requirements
        case nexusUrl = "nexus_url"
    }
}

/// Mod requirement/dependency
public struct NexusRequirement: Codable, Sendable {
    public var id: Int
    public var nexusModId: Int?
    public var name: String
    public var isRequired: Bool
    public var type: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case nexusModId = "nexusModId"
        case name
        case isRequired = "isRequired"
        case type
    }
}

/// Mod file information
public struct NexusFile: Codable, Sendable, Identifiable {
    public var id: Int
    public var fileId: Int
    public var name: String
    public var version: String?
    public var categoryId: Int
    public var categoryName: String
    public var description: String?
    public var size: Int64
    var sizeKb: Int64?
    public var uploadedAt: Date?
    public var updatedAt: Date?
    public var modVersion: String?
    public var virusScanUrl: URL?
    public var changelogHtml: String?
    public var isPrimary: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case fileId = "file_id"
        case name
        case version
        case categoryId = "category_id"
        case categoryName = "category_name"
        case description
        case size
        case sizeKb = "size_kb"
        case uploadedAt = "uploaded_at"
        case updatedAt = "updated_at"
        case modVersion = "mod_version"
        case virusScanUrl = "virus_scan_url"
        case changelogHtml = "changelog_html"
        case isPrimary = "is_primary"
    }
    
    public var sizeInBytes: Int64 {
        sizeKb.map { $0 * 1024 } ?? size
    }
}

/// Mod file download link
public struct NexusDownloadLink: Codable, Sendable {
    public var name: String
    public var shortName: String
    public var uri: URL
    
    enum CodingKeys: String, CodingKey {
        case name
        case shortName = "short_name"
        case uri
    }
}

// MARK: - Search Models

/// Search result for mods
public struct NexusSearchResult: Codable, Sendable {
    public var results: [NexusMod]
    public var total: Int
    public var count: Int
    
    enum CodingKeys: String, CodingKey {
        case results
        case total
        case count
    }
}

// MARK: - Rate Limit Models

/// Rate limit information from API headers
public struct NexusRateLimits: Sendable {
    public var dailyLimit: Int?
    public var dailyRemaining: Int?
    public var hourlyLimit: Int?
    public var hourlyRemaining: Int?
    public var resetTime: Date?
    
    public init(dailyLimit: Int? = nil, dailyRemaining: Int? = nil, hourlyLimit: Int? = nil, hourlyRemaining: Int? = nil, resetTime: Date? = nil) {
        self.dailyLimit = dailyLimit
        self.dailyRemaining = dailyRemaining
        self.hourlyLimit = hourlyLimit
        self.hourlyRemaining = hourlyRemaining
        self.resetTime = resetTime
    }
    
    public var isRateLimited: Bool {
        (dailyRemaining ?? 100) == 0 || (hourlyRemaining ?? 100) == 0
    }
}

// MARK: - GraphQL Models

/// GraphQL query variables
public struct GraphQLVariables: Codable {
    public var gameDomain: String?
    public var modId: Int?
    public var query: String?
    public var categoryId: Int?
    public var limit: Int?
    public var offset: Int?
    public var includeRequirements: Bool?
    
    enum CodingKeys: String, CodingKey {
        case gameDomain
        case modId
        case query
        case categoryId
        case limit
        case offset
        case includeRequirements
    }
}

/// GraphQL response wrapper
public struct GraphQLResponse<T: Codable>: Codable {
    public var data: T?
    public var errors: [GraphQLError]?
}

/// GraphQL error
public struct GraphQLError: Codable {
    public var message: String
    public var locations: [GraphQLLocation]?
    public var path: [String]?
}

/// GraphQL error location
public struct GraphQLLocation: Codable {
    public var line: Int
    public var column: Int
}

// MARK: - Errors

/// Nexus API errors
public enum NexusAPIError: LocalizedError {
    case apiKeyRequired
    case rateLimitReached
    case invalidResponse
    case networkError(Error)
    case httpError(statusCode: Int)
    case graphQLError(String)
    
    public var errorDescription: String? {
        switch self {
        case .apiKeyRequired:
            return "Nexus Mods API key is required"
        case .rateLimitReached:
            return "Nexus API rate limit reached. Please wait."
        case .invalidResponse:
            return "Invalid response from Nexus API"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .graphQLError(let message):
            return "GraphQL error: \(message)"
        }
    }
}
