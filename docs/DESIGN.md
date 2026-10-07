# CyberMod Studio - System Design Document

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CyberMod Studio                                    │
│                           (macOS Application)                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                      Presentation Layer (SwiftUI)                       │   │
│   │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐  │   │
│   │  │    Mod    │ │   Game    │ │ Creation  │ │  Porting  │ │   Debug   │  │   │
│   │  │  Manager  │ │  Runner   │ │  Studio   │ │  Studio   │ │  Studio   │  │   │
│   │  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘  │   │
│   │        │             │             │             │             │        │   │
│   │        └─────────────┴─────────────┼─────────────┴─────────────┘        │   │
│   │                                    │                                    │   │
│   │                         ┌──────────┴──────────┐                         │   │
│   │                         │    ViewModels       │                         │   │
│   │                         │  (ObservableObject) │                         │   │
│   │                         └──────────┬──────────┘                         │   │
│   └─────────────────────────────────────┼───────────────────────────────────┘   │
│                                         │                                       │
│   ┌─────────────────────────────────────┼───────────────────────────────────┐   │
│   │                      Service Layer (CyberModCore)                       │   │
│   │                                     │                                   │   │
│   │  ┌──────────────┐ ┌──────────────┐ │ ┌──────────────┐ ┌──────────────┐  │   │
│   │  │  ModEngine   │ │  GameBridge  │ │ │ProjectEngine │ │ PortingEngine│  │   │
│   │  │              │ │              │ │ │              │ │              │  │   │
│   │  │ • Install    │ │ • Launch     │ │ │ • Projects   │ │ • Analyze    │  │   │
│   │  │ • Profiles   │ │ • Monitor    │ │ │ • Schemas    │ │ • Map addrs  │  │   │
│   │  │ • Nexus API  │ │ • IPC        │ │ │ • Build      │ │ • Scaffold   │  │   │
│   │  └──────┬───────┘ └──────┬───────┘ │ └──────┬───────┘ └──────┬───────┘  │   │
│   │         │                │         │        │                │          │   │
│   │  ┌──────┴────────────────┴─────────┼────────┴────────────────┴───────┐  │   │
│   │  │                    Shared Infrastructure                          │  │   │
│   │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐     │  │   │
│   │  │  │Database │ │  IPC    │ │ Schemas │ │FileOps  │ │ Logging │     │  │   │
│   │  │  │ (GRDB)  │ │Protocol │ │ (JSON)  │ │ (Async) │ │(swift-log)│   │  │   │
│   │  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘     │  │   │
│   │  └───────────────────────────────────────────────────────────────────┘  │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                         │                                       │
└─────────────────────────────────────────┼───────────────────────────────────────┘
                                          │
                                          │ XPC / Unix Socket
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           CyberModDaemon                                        │
│                      (Privileged Helper Tool)                                   │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐    │
│  │ GameMonitor   │  │ Injector      │  │ DebugBridge   │  │ AddressDB     │    │
│  │ (Process mgmt)│  │ (dyld insert) │  │ (Mach tasks)  │  │ (Resolution)  │    │
│  └───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘    │
└─────────────────────────────────────────┼───────────────────────────────────────┘
                                          │
                                          │ DYLD_INSERT_LIBRARIES
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         Game Process (Cyberpunk 2077)                           │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                       │
│  │ RED4ext.dylib │  │DebugAgent.dylib│ │  Plugins...   │                       │
│  │ (Plugin host) │  │ (IPC client)  │  │               │                       │
│  └───────────────┘  └───────────────┘  └───────────────┘                       │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Component Responsibilities

| Component | Responsibility | Process |
|-----------|---------------|---------|
| CyberMod Studio | UI, user interaction, ViewModels | Main App |
| CyberModCore | Business logic, data access | Main App |
| CyberModDaemon | Privileged operations, game injection | LaunchDaemon |
| DebugAgent | In-game IPC, runtime data access | Game Process |

## 2. Module Deep Dives

### 2.1 ModEngine

The ModEngine handles all mod lifecycle operations.

```
┌─────────────────────────────────────────────────────────────────┐
│                          ModEngine                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │
│  │ ModManager  │   │NexusClient  │   │FomodParser  │           │
│  │   (Actor)   │   │   (Actor)   │   │             │           │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘           │
│         │                 │                 │                   │
│         ▼                 ▼                 ▼                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     ModDatabase                         │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │  Mods   │ │Profiles │ │Backups  │ │ Cache   │       │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   ModFileManager                        │   │
│  │  • Archive extraction (ZIP, 7Z, RAR)                    │   │
│  │  • Staging directory management                         │   │
│  │  • Hardlink deployment                                  │   │
│  │  • Rollback operations                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 CompatibilityChecker                    │   │
│  │  • File type analysis                                   │   │
│  │  • Dependency verification                              │   │
│  │  • macOS compatibility scoring                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Key Types

```swift
// Core mod representation
public struct Mod: Codable, Identifiable, Sendable {
    public let id: UUID
    public var nexusId: Int?
    public var name: String
    public var version: String
    public var author: String?
    public var type: Set<ModType>
    public var isEnabled: Bool
    public var installedAt: Date
    public var stagingPath: URL
    public var metadata: ModMetadata
}

public enum ModType: String, Codable, CaseIterable, Sendable {
    case archive      // .archive files
    case tweakXL      // TweakXL YAML files
    case archiveXL    // ArchiveXL .xl files
    case redscript    // .reds scripts
    case red4ext      // .dylib plugins
    case cyber        // CET scripts (not supported on macOS)
    case unknown
}

// Installation transaction
public actor ModInstaller {
    public func install(
        source: ModSource,
        profile: ModProfile,
        options: InstallOptions
    ) async throws -> InstalledMod {
        // 1. Extract to staging
        let stagingDir = try await extract(source)
        
        // 2. Analyze contents
        let analysis = try await analyze(stagingDir)
        
        // 3. Check compatibility
        let compatibility = try await checkCompatibility(analysis)
        guard compatibility.isCompatible else {
            throw ModInstallError.incompatible(compatibility)
        }
        
        // 4. Handle FOMOD if present
        if analysis.hasFomod {
            guard let choices = options.fomodChoices else {
                throw ModInstallError.fomodRequired(analysis.fomodConfig!)
            }
            try await resolveFomod(stagingDir, choices: choices)
        }
        
        // 5. Deploy to game
        let deployment = try await deploy(stagingDir, to: profile.gamePath)
        
        // 6. Record in database
        let mod = try await database.recordInstallation(
            source: source,
            analysis: analysis,
            deployment: deployment,
            profile: profile
        )
        
        return mod
    }
}
```

### 2.2 GameBridge

The GameBridge manages game launching and runtime communication.

```
┌─────────────────────────────────────────────────────────────────┐
│                         GameBridge                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    GameLauncher                         │   │
│  │  • Environment setup (DYLD_INSERT_LIBRARIES)            │   │
│  │  • Process spawning via Process API                     │   │
│  │  • Launch configuration (args, env vars)                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   ProcessMonitor                        │   │
│  │  • Process lifecycle tracking                           │   │
│  │  • Crash detection (SIGTERM, SIGSEGV, etc.)             │   │
│  │  • Resource usage monitoring                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  RuntimeBridge (IPC)                    │   │
│  │  • Unix socket connection to DebugAgent                 │   │
│  │  • TweakDB queries and mutations                        │   │
│  │  • Hook statistics retrieval                            │   │
│  │  • Memory inspection requests                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Key Types

```swift
public actor GameLauncher {
    private let configuration: GameConfiguration
    private let processMonitor: ProcessMonitor
    private var activeSession: GameSession?
    
    public func launch(
        profile: ModProfile,
        options: LaunchOptions = .default
    ) async throws -> GameSession {
        // Verify game path
        guard FileManager.default.fileExists(atPath: configuration.executablePath.path) else {
            throw GameLaunchError.gameNotFound
        }
        
        // Build environment
        var environment = ProcessInfo.processInfo.environment
        
        // Inject RED4ext and required dylibs
        var dylibs: [URL] = [configuration.red4extPath]
        
        if options.enableDebugAgent {
            dylibs.append(configuration.debugAgentPath)
        }
        
        environment["DYLD_INSERT_LIBRARIES"] = dylibs
            .map(\.path)
            .joined(separator: ":")
        
        environment["DYLD_FORCE_FLAT_NAMESPACE"] = "1"
        
        // Apply profile-specific env vars
        for (key, value) in profile.environmentVariables {
            environment[key] = value
        }
        
        // Launch process
        let process = Process()
        process.executableURL = configuration.executablePath
        process.arguments = options.launchArguments
        process.environment = environment
        
        try process.run()
        
        // Create session
        let session = GameSession(
            id: UUID(),
            pid: process.processIdentifier,
            profile: profile,
            startedAt: Date(),
            process: process
        )
        
        activeSession = session
        
        // Start monitoring
        await processMonitor.track(session)
        
        return session
    }
}

public struct GameSession: Identifiable, Sendable {
    public let id: UUID
    public let pid: pid_t
    public let profile: ModProfile
    public let startedAt: Date
    public var status: GameStatus = .running
    
    public enum GameStatus: Sendable {
        case running
        case terminated(exitCode: Int32)
        case crashed(signal: Int32)
    }
}
```

### 2.3 ProjectEngine

The ProjectEngine manages mod creation projects with validation.

```
┌─────────────────────────────────────────────────────────────────┐
│                       ProjectEngine                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  ProjectManager                         │   │
│  │  • Create projects from templates                       │   │
│  │  • Open/save project files                              │   │
│  │  • Project metadata management                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  SchemaRegistry                         │   │
│  │  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐  │   │
│  │  │TweakDBSchema  │ │ArchiveXLSchema│ │ RedscriptGrammar│ │   │
│  │  │ (JSON Schema) │ │ (JSON Schema) │ │  (TextMate)   │  │   │
│  │  └───────────────┘ └───────────────┘ └───────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Validators                           │   │
│  │  • YAML syntax validation                               │   │
│  │  • Schema validation (JSON Schema)                      │   │
│  │  • TweakDB record type validation                       │   │
│  │  • Resource path validation                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   BuildSystem                           │   │
│  │  • CMake integration for RED4ext plugins                │   │
│  │  • xmake integration                                    │   │
│  │  • Archive packaging                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Key Types

```swift
public struct ModProject: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var version: String
    public var author: String
    public var description: String
    public var type: ProjectType
    public var rootPath: URL
    public var files: [ProjectFile]
    public var dependencies: [ModDependency]
    public var buildConfig: BuildConfiguration?
    
    public enum ProjectType: String, Codable {
        case tweakXL
        case archiveXL
        case red4ext
        case redscript
        case mixed
    }
}

public struct ProjectFile: Codable, Identifiable, Hashable {
    public let id: UUID
    public var relativePath: String
    public var fileType: ProjectFileType
    public var content: String?
    
    public enum ProjectFileType: String, Codable {
        case yaml       // TweakXL files
        case xl         // ArchiveXL config
        case reds       // Redscript
        case cpp        // C++ for RED4ext
        case hpp        // C++ headers
        case cmake      // CMakeLists.txt
        case json       // JSON config
        case other
    }
}

public actor TweakDBValidator {
    private let schemaRegistry: SchemaRegistry
    
    public func validate(yaml: String) async throws -> ValidationResult {
        // Parse YAML
        let parsed = try Yams.load(yaml: yaml)
        
        // Validate structure
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Check record types
        if let records = parsed as? [String: Any] {
            for (recordId, recordData) in records {
                // Validate TweakDBID format
                if !isValidTweakDBID(recordId) {
                    errors.append(.invalidRecordId(recordId))
                }
                
                // Validate record type if specified
                if let recordDict = recordData as? [String: Any],
                   let type = recordDict["$type"] as? String {
                    if !schemaRegistry.isValidRecordType(type) {
                        errors.append(.unknownRecordType(type, at: recordId))
                    }
                }
            }
        }
        
        return ValidationResult(errors: errors, warnings: warnings)
    }
}
```

### 2.4 DebugEngine

The DebugEngine provides runtime inspection capabilities.

```
┌─────────────────────────────────────────────────────────────────┐
│                        DebugEngine                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  TweakDBBrowser                         │   │
│  │  • Record enumeration                                   │   │
│  │  • Flat value retrieval                                 │   │
│  │  • Search and filter                                    │   │
│  │  • Live value editing                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   HookMonitor                           │   │
│  │  • Active hook enumeration                              │   │
│  │  • Call statistics (count, timing)                      │   │
│  │  • Hook enable/disable                                  │   │
│  │  • Call stack capture                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  MemoryInspector                        │   │
│  │  • Memory region listing                                │   │
│  │  • Byte-level inspection                                │   │
│  │  • Structure overlay                                    │   │
│  │  • Pointer following                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   LogAggregator                         │   │
│  │  • RED4ext log collection                               │   │
│  │  • Plugin log collection                                │   │
│  │  • Game log parsing                                     │   │
│  │  • Unified timeline view                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 3. Data Model

### 3.1 Entity Relationship Diagram

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│      Mod        │       │   ModProfile    │       │   ModFile       │
├─────────────────┤       ├─────────────────┤       ├─────────────────┤
│ id: UUID (PK)   │       │ id: UUID (PK)   │       │ id: UUID (PK)   │
│ nexusId: Int?   │       │ name: String    │       │ modId: UUID (FK)│
│ name: String    │──────<│ gamePath: URL   │       │ relativePath    │
│ version: String │       │ isActive: Bool  │       │ fileType        │
│ author: String? │       │ createdAt: Date │       │ installPath     │
│ type: [ModType] │       └────────┬────────┘       │ checksum: String│
│ isEnabled: Bool │                │                └─────────────────┘
│ stagingPath: URL│                │                        ▲
│ installedAt     │                │                        │
│ metadata: JSON  │       ┌────────┴────────┐               │
└────────┬────────┘       │  ProfileMod     │               │
         │                ├─────────────────┤               │
         │                │profileId (FK)   │               │
         └───────────────>│ modId (FK)      │───────────────┘
                          │ loadOrder: Int  │
                          │ isEnabled: Bool │
                          └─────────────────┘

┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│    Address      │       │ PortingProject  │       │   FomodChoice   │
├─────────────────┤       ├─────────────────┤       ├─────────────────┤
│ id: UUID (PK)   │       │ id: UUID (PK)   │       │ id: UUID (PK)   │
│ hash: UInt32    │       │ name: String    │       │ modId: UUID (FK)│
│ name: String    │       │ sourcePath: URL │       │ stepId: String  │
│ segment: Int    │       │ status: Status  │       │ groupId: String │
│ offset: UInt64  │       │ windowsAddrs    │       │ optionIds:[Str] │
│ gameVersion     │       │ macosAddrs      │       │ savedAt: Date   │
└─────────────────┘       │ createdAt: Date │       └─────────────────┘
                          └─────────────────┘
```

### 3.2 Database Schema (SQL)

```sql
-- Core mod table
CREATE TABLE mods (
    id TEXT PRIMARY KEY,
    nexus_id INTEGER,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    author TEXT,
    type TEXT NOT NULL,  -- JSON array of ModType
    is_enabled INTEGER NOT NULL DEFAULT 1,
    staging_path TEXT NOT NULL,
    installed_at TEXT NOT NULL,
    metadata TEXT,  -- JSON
    UNIQUE(nexus_id) ON CONFLICT REPLACE
);

CREATE INDEX idx_mods_nexus ON mods(nexus_id);
CREATE INDEX idx_mods_enabled ON mods(is_enabled);

-- Mod profiles
CREATE TABLE profiles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    game_path TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    settings TEXT  -- JSON
);

-- Profile-mod relationships
CREATE TABLE profile_mods (
    profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    mod_id TEXT NOT NULL REFERENCES mods(id) ON DELETE CASCADE,
    load_order INTEGER NOT NULL,
    is_enabled INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (profile_id, mod_id)
);

-- Individual files within mods
CREATE TABLE mod_files (
    id TEXT PRIMARY KEY,
    mod_id TEXT NOT NULL REFERENCES mods(id) ON DELETE CASCADE,
    relative_path TEXT NOT NULL,
    file_type TEXT NOT NULL,
    install_path TEXT NOT NULL,
    checksum TEXT NOT NULL
);

CREATE INDEX idx_mod_files_mod ON mod_files(mod_id);

-- Address database
CREATE TABLE addresses (
    id TEXT PRIMARY KEY,
    hash INTEGER NOT NULL UNIQUE,
    name TEXT NOT NULL,
    segment INTEGER NOT NULL,
    offset INTEGER NOT NULL,
    game_version TEXT NOT NULL,
    source TEXT,  -- manual, discovered, imported
    confidence REAL DEFAULT 1.0
);

CREATE INDEX idx_addresses_hash ON addresses(hash);
CREATE INDEX idx_addresses_version ON addresses(game_version);

-- Porting projects
CREATE TABLE porting_projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    source_path TEXT NOT NULL,
    target_path TEXT,
    status TEXT NOT NULL,  -- analyzing, mapping, building, complete, failed
    analysis_result TEXT,  -- JSON
    address_mappings TEXT,  -- JSON
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- FOMOD choices for re-installation
CREATE TABLE fomod_choices (
    id TEXT PRIMARY KEY,
    mod_id TEXT NOT NULL REFERENCES mods(id) ON DELETE CASCADE,
    step_id TEXT NOT NULL,
    group_id TEXT NOT NULL,
    option_ids TEXT NOT NULL,  -- JSON array
    saved_at TEXT NOT NULL
);

-- Nexus API cache
CREATE TABLE nexus_cache (
    cache_key TEXT PRIMARY KEY,
    response TEXT NOT NULL,
    cached_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
);

CREATE INDEX idx_nexus_cache_expires ON nexus_cache(expires_at);

-- Application settings
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    encrypted INTEGER NOT NULL DEFAULT 0
);
```

## 4. IPC Protocol

See [IPC_PROTOCOL.md](./IPC_PROTOCOL.md) for the complete IPC specification.

## 5. Security Considerations

### 5.1 Sandboxing Strategy

The main application runs with minimal entitlements:
- `com.apple.security.files.user-selected.read-write` - User-selected files
- `com.apple.security.network.client` - Nexus API access
- `com.apple.security.temporary-exception.mach-lookup` - XPC to daemon

The daemon runs as a LaunchDaemon with elevated privileges:
- Process spawning (game launch)
- DYLD injection
- Mach task access (debugging)

### 5.2 Secrets Management

```swift
actor KeychainManager {
    private let service = "com.cybermod.studio"
    
    func store(apiKey: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: apiKey.data(using: .utf8)!
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailure(status)
        }
    }
    
    func retrieve(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
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
}
```

## 6. Error Handling Strategy

### 6.1 Error Types

```swift
public enum CyberModError: LocalizedError {
    // Mod operations
    case modNotFound(UUID)
    case installationFailed(reason: String, suggestion: String?)
    case incompatibleMod(reasons: [String])
    case dependencyMissing(name: String, version: String?)
    case conflictDetected(with: [Mod])
    
    // Game operations
    case gameNotFound(expectedPath: URL)
    case launchFailed(reason: String)
    case injectionFailed(dylib: URL, reason: String)
    case gameAlreadyRunning
    
    // IPC operations
    case connectionFailed(reason: String)
    case timeout(operation: String)
    case invalidResponse(expected: String)
    
    // Project operations
    case projectNotFound(URL)
    case validationFailed(errors: [ValidationError])
    case buildFailed(log: String)
    
    public var errorDescription: String? {
        switch self {
        case .modNotFound(let id):
            return "Mod with ID \(id) not found"
        case .installationFailed(let reason, _):
            return "Installation failed: \(reason)"
        // ... etc
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .installationFailed(_, let suggestion):
            return suggestion
        case .dependencyMissing(let name, _):
            return "Install \(name) first, then retry"
        // ... etc
        }
    }
}
```

### 6.2 Result Type Usage

```swift
public typealias ModResult<T> = Result<T, CyberModError>

extension ModResult {
    func logOnFailure(logger: Logger) -> Self {
        if case .failure(let error) = self {
            logger.error("Operation failed: \(error.localizedDescription)")
        }
        return self
    }
}
```

## 7. Testing Strategy

### 7.1 Unit Tests

```swift
final class ModEngineTests: XCTestCase {
    var sut: ModManager!
    var mockDatabase: MockModDatabase!
    var mockFileManager: MockModFileManager!
    
    override func setUp() {
        mockDatabase = MockModDatabase()
        mockFileManager = MockModFileManager()
        sut = ModManager(database: mockDatabase, fileManager: mockFileManager)
    }
    
    func testInstallArchiveMod() async throws {
        // Given
        let source = ModSource.local(url: testArchiveURL)
        let profile = ModProfile.default
        
        // When
        let result = try await sut.install(source, profile: profile, options: .default)
        
        // Then
        XCTAssertTrue(result.isEnabled)
        XCTAssertEqual(result.type, [.archive])
        XCTAssertTrue(mockFileManager.deployedFiles.contains { $0.hasSuffix(".archive") })
    }
    
    func testRejectIncompatibleMod() async throws {
        // Given
        let source = ModSource.local(url: windowsOnlyModURL)
        
        // When/Then
        await XCTAssertThrowsError(try await sut.install(source, profile: .default, options: .default)) { error in
            guard case CyberModError.incompatibleMod(let reasons) = error else {
                XCTFail("Expected incompatibleMod error")
                return
            }
            XCTAssertTrue(reasons.contains { $0.contains("DLL") })
        }
    }
}
```

### 7.2 Integration Tests

```swift
final class ModInstallationIntegrationTests: XCTestCase {
    var tempDirectory: URL!
    var gamePath: URL!
    
    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create mock game structure
        gamePath = tempDirectory.appendingPathComponent("Cyberpunk2077")
        try createMockGameStructure(at: gamePath)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testFullInstallationCycle() async throws {
        // Create real services with temp paths
        let database = try ModDatabase(path: tempDirectory.appendingPathComponent("mods.db"))
        let fileManager = ModFileManager(gamePath: gamePath, stagingBase: tempDirectory)
        let manager = ModManager(database: database, fileManager: fileManager)
        
        // Install
        let source = ModSource.local(url: sampleArchiveURL)
        let mod = try await manager.install(source, profile: .default, options: .default)
        
        // Verify files deployed
        let deployedPath = gamePath.appendingPathComponent("archive/pc/mod/sample.archive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: deployedPath.path))
        
        // Disable
        try await manager.disable(mod)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deployedPath.path))
        
        // Re-enable
        try await manager.enable(mod)
        XCTAssertTrue(FileManager.default.fileExists(atPath: deployedPath.path))
        
        // Uninstall
        try await manager.uninstall(mod)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deployedPath.path))
    }
}
```

## 8. Performance Considerations

### 8.1 Async Operations

All I/O operations are async to keep the UI responsive:

```swift
public actor ModFileManager {
    public func extract(_ archive: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.syncExtract(archive)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

### 8.2 Caching

```swift
public actor NexusAPIClient {
    private let cache: NexusCache
    private let httpClient: HTTPClient
    
    public func getModDetails(nexusId: Int) async throws -> ModDetails {
        let cacheKey = "mod_details_\(nexusId)"
        
        // Check cache first
        if let cached: ModDetails = try await cache.get(key: cacheKey) {
            return cached
        }
        
        // Fetch from API
        let details = try await fetchModDetails(nexusId)
        
        // Cache for 1 hour
        try await cache.set(key: cacheKey, value: details, ttl: 3600)
        
        return details
    }
}
```

### 8.3 Lazy Loading

Large data sets (mod lists, TweakDB records) use pagination:

```swift
public struct PaginatedQuery<T> {
    public let offset: Int
    public let limit: Int
    public let total: Int
    public let items: [T]
    
    public var hasMore: Bool {
        offset + items.count < total
    }
}

extension TweakDBBrowser {
    public func listRecords(
        filter: TweakDBFilter? = nil,
        offset: Int = 0,
        limit: Int = 100
    ) async throws -> PaginatedQuery<TweakDBRecord> {
        // ...
    }
}
```
