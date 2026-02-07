// NexusCache.swift - File-based caching for Nexus API responses

import Foundation
import Logging
import Crypto

/// Manages file-based caching for Nexus API responses
public actor NexusCache {
    private let cacheDir: URL
    private let fileManager: FileManager
    private let logger: Logger
    
    public static let shared: NexusCache = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("CyberModStudio/nexus_cache")
        return NexusCache(cacheDir: cacheDir)
    }()
    
    public init(cacheDir: URL? = nil, logger: Logger? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDir = cacheDir ?? appSupport.appendingPathComponent("CyberModStudio/nexus_cache")
        self.fileManager = FileManager.default
        self.logger = logger ?? Logger(label: "com.cybermod.nexuscache")
        
        // Ensure cache directory exists
        try? fileManager.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
    }
    
    /// Generate cache key from URL and parameters
    private func cacheKey(url: String, params: [String: Any]? = nil) -> String {
        var keyString = url
        if let params = params {
            let sortedParams = params.sorted { $0.key < $1.key }
            let paramString = sortedParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            keyString += "?" + paramString
        }
        
        // Use SHA256 for cache key
        let data = Data(keyString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Get cached response if available and not expired
    public func get<T: Codable>(url: String, params: [String: Any]? = nil, ttl: TimeInterval) -> T? {
        let key = cacheKey(url: url, params: params)
        let cachePath = cacheDir.appendingPathComponent("\(key).json")
        
        guard fileManager.fileExists(atPath: cachePath.path) else {
            return nil
        }
        
        // Check if cache is expired
        do {
            let attributes = try fileManager.attributesOfItem(atPath: cachePath.path)
            if let modDate = attributes[.modificationDate] as? Date {
                let age = Date().timeIntervalSince(modDate)
                if age > ttl {
                    // Cache expired, remove it
                    try? fileManager.removeItem(at: cachePath)
                    return nil
                }
            }
        } catch {
            logger.warning("Failed to check cache expiration: \(error.localizedDescription)")
            return nil
        }
        
        // Read and decode cached data
        do {
            let data = try Data(contentsOf: cachePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.warning("Failed to decode cached data: \(error.localizedDescription)")
            // Remove corrupted cache file
            try? fileManager.removeItem(at: cachePath)
            return nil
        }
    }
    
    /// Store response in cache
    public func set<T: Codable>(_ value: T, url: String, params: [String: Any]? = nil) {
        let key = cacheKey(url: url, params: params)
        let cachePath = cacheDir.appendingPathComponent("\(key).json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(value)
            try data.write(to: cachePath)
        } catch {
            logger.warning("Failed to cache response: \(error.localizedDescription)")
        }
    }
    
    /// Clear all cached responses
    public func clear() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
            logger.info("Cleared Nexus API cache")
        } catch {
            logger.warning("Failed to clear cache: \(error.localizedDescription)")
        }
    }
    
    /// Clear expired cache entries
    public func clearExpired() -> Int {
        var cleared = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey])
            
            for file in contents {
                if let attributes = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modDate = attributes.contentModificationDate {
                    // Default TTL is 1 hour, but we'll check for files older than 24 hours
                    let age = Date().timeIntervalSince(modDate)
                    if age > 86400 { // 24 hours
                        try? fileManager.removeItem(at: file)
                        cleared += 1
                    }
                }
            }
        } catch {
            logger.warning("Failed to clear expired cache: \(error.localizedDescription)")
        }
        
        if cleared > 0 {
            logger.info("Cleared \(cleared) expired cache entries")
        }
        
        return cleared
    }
    
    /// Get cache size in bytes
    public func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])
            
            for file in contents {
                if let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attributes.fileSize {
                    totalSize += Int64(size)
                }
            }
        } catch {
            logger.warning("Failed to calculate cache size: \(error.localizedDescription)")
        }
        
        return totalSize
    }
}
