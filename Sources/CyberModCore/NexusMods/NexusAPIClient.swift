// NexusAPIClient.swift - Nexus Mods API client

import Foundation
import Logging
import AsyncHTTPClient

/// Keychain helper for storing Nexus API key securely
public struct NexusKeychain {
    private static let service = "com.cybermod.nexusapi"
    private static let account = "api_key"
    
    /// Store API key in Keychain
    public static func store(_ apiKey: String) throws {
        let data = apiKey.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NexusAPIError.networkError(NSError(domain: "Keychain", code: Int(status)))
        }
    }
    
    /// Retrieve API key from Keychain
    public static func retrieve() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    /// Delete API key from Keychain
    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

/// Nexus Mods API client
public actor NexusAPIClient {
    private let baseURLV1 = "https://api.nexusmods.com/v1"
    private let baseURLV2 = "https://api.nexusmods.com/v2"
    private let graphQLURL = "https://api.nexusmods.com/v2/graphql"
    
    private var apiKey: String?
    private let httpClient: HTTPClient
    private let cache: NexusCache
    private let logger: Logger
    private var rateLimits: NexusRateLimits
    
    public static let shared = NexusAPIClient()
    
    public init(apiKey: String? = nil, cache: NexusCache = .shared, logger: Logger? = nil) {
        self.cache = cache
        self.logger = logger ?? Logger(label: "com.cybermod.nexusapi")
        self.rateLimits = NexusRateLimits()
        
        // Try to get API key from parameter, Keychain, or environment
        if let key = apiKey {
            self.apiKey = key
        } else if let key = NexusKeychain.retrieve() {
            self.apiKey = key
        } else if let key = ProcessInfo.processInfo.environment["NEXUS_API_KEY"] {
            self.apiKey = key
        }
        
        var configuration = HTTPClient.Configuration()
        configuration.timeout = HTTPClient.Configuration.Timeout(
            connect: .seconds(30),
            read: .seconds(30)
        )
        
        self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
    }
    
    /// Set API key (stores in Keychain)
    public func setAPIKey(_ apiKey: String) throws {
        try NexusKeychain.store(apiKey)
        self.apiKey = apiKey
    }
    
    /// Get current API key (if available)
    public func getAPIKey() -> String? {
        return apiKey
    }
    
    /// Validate API key and get user info
    public func validateKey() async throws -> NexusUser {
        guard let apiKey = apiKey else {
            throw NexusAPIError.apiKeyRequired
        }
        
        let url = "\(baseURLV1)/users/validate.json"
        
        // Check cache first (5 minute TTL)
        if let cached: NexusUser = await cache.get(url: url, ttl: 300) {
            return cached
        }
        
        var request = try HTTPClient.Request(url: url, method: .GET)
        request.headers.add(name: "apikey", value: apiKey)
        request.headers.add(name: "User-Agent", value: "CyberModStudio/1.0")
        request.headers.add(name: "Accept", value: "application/json")
        
        let response = try await httpClient.execute(request: request).get()
        
        updateRateLimits(from: response)
        
        guard response.status == .ok else {
            throw NexusAPIError.httpError(statusCode: Int(response.status.code))
        }
        
        guard let body = response.body else {
            throw NexusAPIError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let user = try decoder.decode(NexusUser.self, from: Data(buffer: body))
        await cache.set(user, url: url)
        
        return user
    }
    
    /// Get list of all games
    public func getGames() async throws -> [NexusGame] {
        guard apiKey != nil else {
            throw NexusAPIError.apiKeyRequired
        }
        
        let url = "\(baseURLV1)/games.json"
        
        // Check cache (24 hour TTL)
        if let cached: [NexusGame] = await cache.get(url: url, ttl: 86400) {
            return cached
        }
        
        let response = try await makeRequest(url: url)
        let games = try await decodeResponse([NexusGame].self, from: response)
        await cache.set(games, url: url)
        
        return games
    }
    
    /// Get mod information
    public func getMod(gameDomain: String, modId: Int) async throws -> NexusMod {
        guard apiKey != nil else {
            throw NexusAPIError.apiKeyRequired
        }
        
        let url = "\(baseURLV1)/games/\(gameDomain)/mods/\(modId).json"
        
        // Check cache (1 hour TTL)
        if let cached: NexusMod = await cache.get(url: url, ttl: 3600) {
            return cached
        }
        
        let response = try await makeRequest(url: url)
        let mod = try await decodeResponse(NexusMod.self, from: response)
        await cache.set(mod, url: url)
        
        return mod
    }
    
    /// Get mod files
    public func getModFiles(gameDomain: String, modId: Int) async throws -> [NexusFile] {
        guard apiKey != nil else {
            throw NexusAPIError.apiKeyRequired
        }
        
        let url = "\(baseURLV1)/games/\(gameDomain)/mods/\(modId)/files.json"
        
        // Check cache (30 minute TTL)
        if let cached: [NexusFile] = await cache.get(url: url, ttl: 1800) {
            return cached
        }
        
        let response = try await makeRequest(url: url)
        let files = try await decodeResponse([NexusFile].self, from: response)
        await cache.set(files, url: url)
        
        return files
    }
    
    /// Get mod requirements using GraphQL
    public func getModRequirements(gameDomain: String, modId: Int) async throws -> [NexusRequirement] {
        guard apiKey != nil else {
            throw NexusAPIError.apiKeyRequired
        }
        
        let query = """
        query GetModRequirements($gameDomain: String!, $modId: Int!) {
            mod(gameDomainName: $gameDomain, nexusModId: $modId) {
                requirements {
                    id
                    nexusModId
                    name
                    isRequired
                    type
                }
            }
        }
        """
        
        let variables: [String: Any] = [
            "gameDomain": gameDomain,
            "modId": modId
        ]
        
        let response = try await makeGraphQLRequest(query: query, variables: variables)
        
        // Parse GraphQL response
        struct GraphQLData: Codable {
            var mod: ModData?
            
            struct ModData: Codable {
                var requirements: [NexusRequirement]?
            }
        }
        
        struct GraphQLResponse: Codable {
            var data: GraphQLData?
        }
        
        let graphQLResponse = try await decodeResponse(GraphQLResponse.self, from: response)
        return graphQLResponse.data?.mod?.requirements ?? []
    }
    
    /// Search mods using GraphQL
    public func searchMods(
        gameDomain: String,
        query: String? = nil,
        categoryId: Int? = nil,
        sortBy: String = "endorsements",
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> NexusSearchResult {
        guard apiKey != nil else {
            throw NexusAPIError.apiKeyRequired
        }
        
        let graphQLQuery = """
        query SearchMods(
            $gameDomain: String!
            $query: String
            $categoryId: Int
            $limit: Int
            $offset: Int
        ) {
            mods(
                gameDomainName: $gameDomain
                filter: {
                    name: $query
                    categoryId: $categoryId
                }
                count: $limit
                offset: $offset
            ) {
                nodes {
                    id
                    nexusModId
                    name
                    summary
                    description
                    author
                    pictureUrl
                    endorsements
                    totalDownloads
                    uniqueDownloads
                    updatedAt
                    createdAt
                    category {
                        id
                        name
                    }
                }
                nodesCount
                totalCount
            }
        }
        """
        
        var variables: [String: Any] = [
            "gameDomain": gameDomain,
            "limit": limit,
            "offset": offset
        ]
        
        if let query = query {
            variables["query"] = query
        }
        if let categoryId = categoryId {
            variables["categoryId"] = categoryId
        }
        
        let response = try await makeGraphQLRequest(query: graphQLQuery, variables: variables)
        
        // Parse GraphQL response
        struct ModsData: Codable {
            var nodes: [NexusMod]
            var nodesCount: Int
            var totalCount: Int
        }
        
        struct GraphQLData: Codable {
            var mods: ModsData
        }
        
        struct GraphQLResponse: Codable {
            var data: GraphQLData?
        }
        
        let graphQLResponse = try await decodeResponse(GraphQLResponse.self, from: response)
        
        guard let modsData = graphQLResponse.data?.mods else {
            return NexusSearchResult(results: [], total: 0, count: 0)
        }
        
        return NexusSearchResult(
            results: modsData.nodes,
            total: modsData.totalCount,
            count: modsData.nodesCount
        )
    }
    
    /// Get download link for mod file
    public func getDownloadLink(gameDomain: String, modId: Int, fileId: Int) async throws -> NexusDownloadLink {
        guard apiKey != nil else {
            throw NexusAPIError.apiKeyRequired
        }
        
        // Download links are never cached (they expire)
        let url = "\(baseURLV1)/games/\(gameDomain)/mods/\(modId)/files/\(fileId)/download_link.json"
        
        let response = try await makeRequest(url: url)
        return try await decodeResponse(NexusDownloadLink.self, from: response)
    }
    
    /// Download a file with progress reporting
    public func downloadFile(
        url: URL,
        to destination: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws {
        var request = try HTTPClient.Request(url: url.absoluteString, method: .GET)
        request.headers.add(name: "User-Agent", value: "CyberModStudio/1.0")
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok else {
            throw NexusAPIError.httpError(statusCode: Int(response.status.code))
        }
        
        let totalSize = response.headers.first(name: "content-length").flatMap { Int64($0) } ?? 0
        
        // Create destination directory if needed
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Download to file
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }
        
        var downloaded: Int64 = 0
        
        if let body = response.body {
            let data = Data(buffer: body)
            try fileHandle.write(contentsOf: data)
            downloaded = Int64(data.count)
            progress(downloaded, totalSize)
        }
    }
    
    // MARK: - Private Helpers
    
    private func makeRequest(url: String) async throws -> HTTPClient.Response {
        guard let apiKey = apiKey else {
            throw NexusAPIError.apiKeyRequired
        }
        
        if rateLimits.isRateLimited {
            throw NexusAPIError.rateLimitReached
        }
        
        var request = try HTTPClient.Request(url: url, method: .GET)
        request.headers.add(name: "apikey", value: apiKey)
        request.headers.add(name: "User-Agent", value: "CyberModStudio/1.0")
        request.headers.add(name: "Accept", value: "application/json")
        
        let response = try await httpClient.execute(request: request).get()
        updateRateLimits(from: response)
        
        guard response.status == .ok else {
            throw NexusAPIError.httpError(statusCode: Int(response.status.code))
        }
        
        return response
    }
    
    private func makeGraphQLRequest(query: String, variables: [String: Any]) async throws -> HTTPClient.Response {
        guard let apiKey = apiKey else {
            throw NexusAPIError.apiKeyRequired
        }
        
        if rateLimits.isRateLimited {
            throw NexusAPIError.rateLimitReached
        }
        
        // Use JSONSerialization for flexible encoding
        var jsonDict: [String: Any] = ["query": query]
        
        // Convert variables to JSON-compatible types
        var jsonVariables: [String: Any] = [:]
        for (key, value) in variables {
            jsonVariables[key] = value
        }
        jsonDict["variables"] = jsonVariables
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: jsonDict) else {
            throw NexusAPIError.invalidResponse
        }
        
        var request = try HTTPClient.Request(url: graphQLURL, method: .POST)
        request.headers.add(name: "apikey", value: apiKey)
        request.headers.add(name: "User-Agent", value: "CyberModStudio/1.0")
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(bodyData)
        
        let response = try await httpClient.execute(request: request).get()
        updateRateLimits(from: response)
        
        guard response.status == .ok else {
            throw NexusAPIError.httpError(statusCode: Int(response.status.code))
        }
        
        return response
    }
    
    private func decodeResponse<T: Decodable>(_ type: T.Type, from response: HTTPClient.Response) async throws -> T {
        guard let body = response.body else {
            throw NexusAPIError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(T.self, from: Data(buffer: body))
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
            throw NexusAPIError.invalidResponse
        }
    }
    
    private func updateRateLimits(from response: HTTPClient.Response) {
        if let dailyLimit = response.headers.first(name: "x-rl-daily-limit").flatMap({ Int($0) }) {
            rateLimits.dailyLimit = dailyLimit
        }
        if let dailyRemaining = response.headers.first(name: "x-rl-daily-remaining").flatMap({ Int($0) }) {
            rateLimits.dailyRemaining = dailyRemaining
        }
        if let hourlyLimit = response.headers.first(name: "x-rl-hourly-limit").flatMap({ Int($0) }) {
            rateLimits.hourlyLimit = hourlyLimit
        }
        if let hourlyRemaining = response.headers.first(name: "x-rl-hourly-remaining").flatMap({ Int($0) }) {
            rateLimits.hourlyRemaining = hourlyRemaining
        }
    }
    
    deinit {
        try? httpClient.syncShutdown()
    }
}
