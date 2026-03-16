// ModDatabase.swift - SQLite database for mod persistence

import Foundation
import GRDB
import Logging

/// SQLite database for storing mod data
public actor ModDatabase {
    
    // MARK: - Properties
    
    private var dbQueue: DatabaseQueue?
    private let logger: Logger
    private let databasePath: URL
    
    // MARK: - Singleton
    
    public static let shared = ModDatabase()
    
    // MARK: - Initialization
    
    public init(path: URL? = nil) {
        self.logger = Logger(label: "com.cybermod.database")
        
        if let path = path {
            self.databasePath = path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dataDir = appSupport.appendingPathComponent("CyberModStudio")
            try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            self.databasePath = dataDir.appendingPathComponent("mods.db")
        }
    }
    
    /// Initialize the database connection and schema
    public func initialize() async throws {
        dbQueue = try DatabaseQueue(path: databasePath.path)
        try await migrate()
        logger.info("Database initialized at \(databasePath.path)")
    }
    
    // MARK: - Migrations
    
    private func migrate() async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        var migrator = DatabaseMigrator()
        
        // Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Mods table
            try db.create(table: "mods") { t in
                t.column("id", .text).primaryKey()
                t.column("nexus_id", .integer).indexed()
                t.column("name", .text).notNull()
                t.column("version", .text).notNull()
                t.column("author", .text)
                t.column("description", .text)
                t.column("type", .text).notNull()
                t.column("is_enabled", .boolean).notNull().defaults(to: true)
                t.column("staging_path", .text).notNull()
                t.column("installed_at", .datetime).notNull()
                t.column("metadata", .blob)
            }
            
            // Profiles table
            try db.create(table: "profiles") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
                t.column("game_path", .text).notNull()
                t.column("is_active", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.column("settings", .blob)
            }
            
            // Profile-Mod associations
            try db.create(table: "profile_mods") { t in
                t.column("profile_id", .text).notNull().references("profiles", onDelete: .cascade)
                t.column("mod_id", .text).notNull().references("mods", onDelete: .cascade)
                t.column("load_order", .integer).notNull()
                t.column("is_enabled", .boolean).notNull().defaults(to: true)
                t.primaryKey(["profile_id", "mod_id"])
            }
            
            // Deployed files
            try db.create(table: "deployed_files") { t in
                t.column("id", .text).primaryKey()
                t.column("mod_id", .text).notNull().references("mods", onDelete: .cascade)
                t.column("relative_path", .text).notNull()
                t.column("install_path", .text).notNull()
                t.column("file_type", .text).notNull()
                t.column("checksum", .text).notNull()
            }
            
            try db.create(index: "idx_deployed_files_mod", on: "deployed_files", columns: ["mod_id"])
        }
        
        try migrator.migrate(db)
    }
    
    // MARK: - Mod Operations
    
    /// List all mods
    public func listMods() async throws -> [Mod] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM mods ORDER BY name")
            return rows.compactMap { self.modFromRow($0) }
        }
    }
    
    /// Get a mod by ID
    public func getMod(id: UUID) async throws -> Mod? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        return try await db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM mods WHERE id = ?", arguments: [id.uuidString])
            return row.flatMap { self.modFromRow($0) }
        }
    }
    
    /// Search mods by name
    public func searchMods(query: String) async throws -> [Mod] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM mods WHERE name LIKE ? ORDER BY name",
                arguments: ["%\(query)%"]
            )
            return rows.compactMap { self.modFromRow($0) }
        }
    }
    
    /// Insert a new mod
    public func insertMod(_ mod: Mod) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            let typeJson = try JSONEncoder().encode(Array(mod.type))
            let metadataJson = mod.metadata.flatMap { try? JSONEncoder().encode($0) }
            
            try db.execute(
                sql: """
                    INSERT INTO mods (id, nexus_id, name, version, author, description, type, is_enabled, staging_path, installed_at, metadata)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mod.id.uuidString,
                    mod.nexusId,
                    mod.name,
                    mod.version,
                    mod.author,
                    mod.description,
                    String(data: typeJson, encoding: .utf8),
                    mod.isEnabled,
                    mod.stagingPath.path,
                    mod.installedAt,
                    metadataJson
                ]
            )
        }
    }
    
    /// Update an existing mod
    public func updateMod(_ mod: Mod) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            let typeJson = try JSONEncoder().encode(Array(mod.type))
            let metadataJson = mod.metadata.flatMap { try? JSONEncoder().encode($0) }
            
            try db.execute(
                sql: """
                    UPDATE mods SET
                        nexus_id = ?, name = ?, version = ?, author = ?, description = ?,
                        type = ?, is_enabled = ?, staging_path = ?, metadata = ?
                    WHERE id = ?
                    """,
                arguments: [
                    mod.nexusId,
                    mod.name,
                    mod.version,
                    mod.author,
                    mod.description,
                    String(data: typeJson, encoding: .utf8),
                    mod.isEnabled,
                    mod.stagingPath.path,
                    metadataJson,
                    mod.id.uuidString
                ]
            )
        }
    }
    
    /// Delete a mod
    public func deleteMod(id: UUID) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            try db.execute(sql: "DELETE FROM mods WHERE id = ?", arguments: [id.uuidString])
        }
    }
    
    // MARK: - Profile Operations
    
    /// List all profiles
    public func listProfiles() async throws -> [ModProfile] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM profiles ORDER BY name")
            return rows.compactMap { self.profileFromRow($0) }
        }
    }
    
    /// Get the active profile
    public func getActiveProfile() async throws -> ModProfile? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        return try await db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM profiles WHERE is_active = 1")
            return row.flatMap { self.profileFromRow($0) }
        }
    }
    
    /// Insert a new profile
    public func insertProfile(_ profile: ModProfile) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            let settingsJson = try JSONEncoder().encode(profile.settings)
            
            try db.execute(
                sql: """
                    INSERT INTO profiles (id, name, game_path, is_active, created_at, settings)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    profile.id.uuidString,
                    profile.name,
                    profile.gamePath.path,
                    profile.isActive,
                    profile.createdAt,
                    settingsJson
                ]
            )
        }
    }
    
    /// Update a profile
    public func updateProfile(_ profile: ModProfile) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            let settingsJson = try JSONEncoder().encode(profile.settings)
            
            try db.execute(
                sql: """
                    UPDATE profiles SET
                        name = ?, game_path = ?, is_active = ?, settings = ?
                    WHERE id = ?
                    """,
                arguments: [
                    profile.name,
                    profile.gamePath.path,
                    profile.isActive,
                    settingsJson,
                    profile.id.uuidString
                ]
            )
        }
    }
    
    // MARK: - Profile-Mod Associations
    
    /// Associate a mod with a profile
    public func associateModWithProfile(modId: UUID, profileId: UUID) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            // Get next load order
            let maxOrder = try Int.fetchOne(
                db,
                sql: "SELECT MAX(load_order) FROM profile_mods WHERE profile_id = ?",
                arguments: [profileId.uuidString]
            ) ?? -1
            
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO profile_mods (profile_id, mod_id, load_order, is_enabled)
                    VALUES (?, ?, ?, 1)
                    """,
                arguments: [profileId.uuidString, modId.uuidString, maxOrder + 1]
            )
        }
    }
    
    /// Update load order for a mod in a profile
    public func updateLoadOrder(modId: UUID, profileId: UUID, order: Int) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            try db.execute(
                sql: "UPDATE profile_mods SET load_order = ? WHERE profile_id = ? AND mod_id = ?",
                arguments: [order, profileId.uuidString, modId.uuidString]
            )
        }
    }
    
    // MARK: - Deployed Files
    
    /// Get deployed files for a mod
    public func getDeployedFiles(forMod modId: UUID) async throws -> [DeployedFile] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        return try await db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM deployed_files WHERE mod_id = ?",
                arguments: [modId.uuidString]
            )
            return rows.compactMap { self.deployedFileFromRow($0) }
        }
    }
    
    /// Record deployed files for a mod
    public func recordDeployedFiles(_ files: [DeployedFile], forMod modId: UUID) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            for file in files {
                try db.execute(
                    sql: """
                        INSERT INTO deployed_files (id, mod_id, relative_path, install_path, file_type, checksum)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        modId.uuidString,
                        file.relativePath,
                        file.installPath.path,
                        file.fileType.rawValue,
                        file.checksum
                    ]
                )
            }
        }
    }
    
    /// Clear deployed files for a mod
    public func clearDeployedFiles(forMod modId: UUID) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }
        
        try await db.write { db in
            try db.execute(sql: "DELETE FROM deployed_files WHERE mod_id = ?", arguments: [modId.uuidString])
        }
    }
    
    // MARK: - Row Conversion
    
    private nonisolated func modFromRow(_ row: Row) -> Mod? {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = row["name"] as? String,
              let version = row["version"] as? String,
              let typeJson = row["type"] as? String,
              let stagingPath = row["staging_path"] as? String else {
            return nil
        }
        
        let typeArray = (try? JSONDecoder().decode([ModType].self, from: typeJson.data(using: .utf8)!)) ?? []
        let metadata: ModMetadata? = (row["metadata"] as? Data).flatMap {
            try? JSONDecoder().decode(ModMetadata.self, from: $0)
        }
        
        return Mod(
            id: id,
            nexusId: row["nexus_id"] as? Int,
            name: name,
            version: version,
            author: row["author"] as? String,
            description: row["description"] as? String,
            type: Set(typeArray),
            isEnabled: (row["is_enabled"] as? Int ?? 1) == 1,
            installedAt: row["installed_at"] as? Date ?? Date(),
            stagingPath: URL(fileURLWithPath: stagingPath),
            metadata: metadata
        )
    }
    
    private nonisolated func profileFromRow(_ row: Row) -> ModProfile? {
        guard let idString = row["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = row["name"] as? String,
              let gamePath = row["game_path"] as? String else {
            return nil
        }
        
        let settings: ProfileSettings = (row["settings"] as? Data).flatMap {
            try? JSONDecoder().decode(ProfileSettings.self, from: $0)
        } ?? ProfileSettings()
        
        return ModProfile(
            id: id,
            name: name,
            gamePath: URL(fileURLWithPath: gamePath),
            isActive: (row["is_active"] as? Int ?? 0) == 1,
            createdAt: row["created_at"] as? Date ?? Date(),
            settings: settings
        )
    }
    
    private nonisolated func deployedFileFromRow(_ row: Row) -> DeployedFile? {
        guard let relativePath = row["relative_path"] as? String,
              let installPath = row["install_path"] as? String,
              let fileTypeRaw = row["file_type"] as? String,
              let checksum = row["checksum"] as? String else {
            return nil
        }
        
        return DeployedFile(
            relativePath: relativePath,
            installPath: URL(fileURLWithPath: installPath),
            fileType: ModType(rawValue: fileTypeRaw) ?? .unknown,
            checksum: checksum
        )
    }
}

// MARK: - Errors

public enum DatabaseError: LocalizedError {
    case notInitialized
    case migrationFailed(String)
    case queryFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized"
        case .migrationFailed(let reason):
            return "Database migration failed: \(reason)"
        case .queryFailed(let reason):
            return "Database query failed: \(reason)"
        }
    }
}
