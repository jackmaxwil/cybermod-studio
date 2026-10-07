# CyberMod Studio - Architecture Overview

## System Context

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              External Systems                                   │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                       │
│  │  Nexus Mods   │  │   macOS       │  │  Cyberpunk    │                       │
│  │     API       │  │   Keychain    │  │    2077       │                       │
│  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘                       │
└──────────┼──────────────────┼──────────────────┼───────────────────────────────┘
           │                  │                  │
           │                  │                  │
┌──────────▼──────────────────▼──────────────────▼───────────────────────────────┐
│                          CyberMod Studio Platform                              │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│   ┌────────────────────────────────────────────────────────────────────────┐   │
│   │                    CyberMod Studio (macOS App)                         │   │
│   │                                                                        │   │
│   │   ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐         │   │
│   │   │    Mod     │ │    Game    │ │  Creation  │ │   Debug    │         │   │
│   │   │  Manager   │ │   Runner   │ │   Studio   │ │   Studio   │         │   │
│   │   └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────┬──────┘         │   │
│   │         │              │              │              │                │   │
│   │         └──────────────┴──────────────┼──────────────┘                │   │
│   │                                       │                               │   │
│   │                           ┌───────────▼───────────┐                   │   │
│   │                           │    CyberModCore       │                   │   │
│   │                           │   (Swift Package)     │                   │   │
│   │                           └───────────────────────┘                   │   │
│   └────────────────────────────────────────────────────────────────────────┘   │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

## Package Structure

```
cybermod-studio/
├── Package.swift                    # Swift Package Manager manifest
├── Sources/
│   ├── CyberModCore/               # Core business logic library
│   │   ├── ModEngine/              # Mod management
│   │   ├── GameBridge/             # Game launching & monitoring
│   │   ├── ProjectEngine/          # Mod project creation
│   │   ├── PortingEngine/          # Windows→macOS porting
│   │   ├── DebugEngine/            # Runtime debugging
│   │   ├── Database/               # SQLite persistence
│   │   ├── Schemas/                # JSON schemas & validation
│   │   ├── IPC/                    # Inter-process communication
│   │   └── Utilities/              # Shared utilities
│   │
│   └── CyberModCLI/                # Command-line interface
│       └── Commands/
│
├── CyberModStudio/                  # SwiftUI macOS app
│   ├── Views/                       # UI views
│   ├── ViewModels/                  # Observable view models
│   ├── Services/                    # App-level services
│   └── Resources/                   # Assets, schemas
│
├── Tests/
│   └── CyberModCoreTests/          # Unit & integration tests
│
├── docs/                            # Documentation
│   ├── PRD.md
│   ├── DESIGN.md
│   ├── VIEWS.md
│   ├── IPC_PROTOCOL.md
│   ├── ARCHITECTURE.md
│   ├── api/
│   ├── schemas/
│   └── protocols/
│
├── scripts/                         # Build & utility scripts
└── config/                          # Configuration templates
```

## Module Dependencies

```
┌─────────────────────────────────────────────────────────────────┐
│                       CyberModStudio App                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │   Views  │ │ViewModels│ │ Services │ │Resources │           │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────────┘           │
│       │            │            │                               │
│       └────────────┴────────────┘                               │
│                     │                                           │
└─────────────────────┼───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                        CyberModCore                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ModEngine │ │GameBridge│ │ProjectEng│ │DebugEng  │           │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘           │
│       │            │            │            │                  │
│       └────────────┴────────────┼────────────┘                  │
│                                 │                               │
│  ┌──────────┐ ┌──────────┐ ┌────▼─────┐ ┌──────────┐           │
│  │ Database │ │  Schemas │ │   IPC    │ │Utilities │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
└─────────────────────────────────────────────────────────────────┘
                      │
                      │ Dependencies
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    External Packages                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │  GRDB   │ │  Yams   │ │ Crypto  │ │AsyncHTTP│ │   ZIP   │   │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Mod Installation Flow

```
User                App UI              ModEngine           FileSystem          Database
 │                    │                     │                   │                  │
 │  Select archive    │                     │                   │                  │
 │───────────────────>│                     │                   │                  │
 │                    │  install(source)    │                   │                  │
 │                    │────────────────────>│                   │                  │
 │                    │                     │  extract()        │                  │
 │                    │                     │──────────────────>│                  │
 │                    │                     │  <staging dir>    │                  │
 │                    │                     │<──────────────────│                  │
 │                    │                     │  analyze()        │                  │
 │                    │                     │──────────────────>│                  │
 │                    │                     │  <mod type>       │                  │
 │                    │                     │<──────────────────│                  │
 │                    │                     │  checkCompatibility()               │
 │                    │                     │─────────────────────────────────────>│
 │                    │                     │  <compat result>                    │
 │                    │                     │<─────────────────────────────────────│
 │                    │                     │  deploy()         │                  │
 │                    │                     │──────────────────>│                  │
 │                    │                     │  <deployed files> │                  │
 │                    │                     │<──────────────────│                  │
 │                    │                     │  recordInstallation()               │
 │                    │                     │─────────────────────────────────────>│
 │                    │                     │  <mod record>                       │
 │                    │                     │<─────────────────────────────────────│
 │                    │  <InstalledMod>     │                   │                  │
 │                    │<────────────────────│                   │                  │
 │  Update UI         │                     │                   │                  │
 │<───────────────────│                     │                   │                  │
```

### Game Launch Flow

`GameLauncher` does not reimplement launching. It runs `launch_red4ext.sh` (shipped by RED4ext into the game
folder) with the game folder as working directory, passing the profile's arguments and environment, and writes
its output to `~/Library/Logs/CyberModStudio/game.log`. The script:

1. Refuses to start if the game binary's UUID does not match `red4ext/bin/x64/cyberpunk2077_addresses.json`
   (game updated) or the binary lost RED4ext's signature (`allow-unsigned-executable-memory`; fix with
   `red4ext/macos/scripts/install_macos.sh`).
2. Stages `Scripts` only of plugins that pass `red4ext/bin/red4ext_plugin_check` and are not ignored in
   `red4ext/config.ini`, then compiles with `engine/tools/scc` (stops on errors).
3. Merges `r6/input` key bindings with `engine/tools/inputloader.pl`, run from the game folder.
4. Starts the game with `DYLD_INSERT_LIBRARIES=red4ext/RED4ext.dylib` and unstages plugin scripts after exit.

A refusal is a non-zero exit; `GameLauncher.exitReport` then shows the script's output. Stopping the game from the
app sends SIGTERM to the game (the script's child) so the script still cleans up.

## Security Model

### No Privileged Helper

The app runs unsandboxed as the user and launches the game itself; there is no daemon or XPC service.
`DYLD_INSERT_LIBRARIES` injection works because RED4ext's installer re-signs the game binary with its entitlements.
`launch_red4ext.sh` checks that before every launch; the app never re-signs anything.

### API Key Storage

```swift
// Nexus API key stored in Keychain
let query: [String: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "com.cybermod.studio",
    kSecAttrAccount: "nexus-api-key",
    kSecValueData: apiKey.data(using: .utf8)!,
    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
]
```

## Error Handling Strategy

### Error Hierarchy

```swift
public enum CyberModError: LocalizedError {
    // Installation errors
    case installationFailed(InstallError)
    case dependencyMissing(String)
    case incompatibleMod([IncompatibilityReason])
    
    // Game errors  
    case gameNotFound
    case launchFailed(LaunchError)
    case connectionFailed(ConnectionError)
    
    // Project errors
    case projectNotFound
    case validationFailed([ValidationError])
    case buildFailed(BuildError)
    
    // IPC errors
    case timeout(operation: String)
    case disconnected
    case protocolError(String)
}

public enum InstallError: Error {
    case archiveCorrupt
    case extractionFailed(String)
    case diskFull
    case permissionDenied(URL)
}
```

### Recovery Strategies

| Error Type | Recovery Strategy |
|------------|-------------------|
| Archive corrupt | Prompt re-download |
| Disk full | Show disk usage, suggest cleanup |
| Permission denied | Request permission, show path |
| Game not found | Open game path picker |
| Connection timeout | Retry with backoff |
| Incompatible mod | Show alternatives |

## Performance Considerations

### Async Operations

All I/O-bound operations are async:

```swift
public actor ModManager {
    public func install(_ source: ModSource) async throws -> Mod
    public func listMods() async throws -> [Mod]
    public func enable(_ mod: Mod) async throws
}
```

### Caching Strategy

| Data | Cache Location | TTL | Invalidation |
|------|----------------|-----|--------------|
| Nexus mod metadata | SQLite | 1 hour | Manual refresh |
| TweakDB schema | Memory | Session | Game restart |
| Address database | SQLite | Permanent | Game update |
| Mod file checksums | SQLite | Permanent | File change |

### Lazy Loading

Large data sets use pagination:

```swift
public struct PaginatedResult<T> {
    public let items: [T]
    public let offset: Int
    public let total: Int
    public var hasMore: Bool { offset + items.count < total }
}
```

## Testing Strategy

### Test Categories

| Category | Scope | Tools |
|----------|-------|-------|
| Unit | Individual functions | XCTest |
| Integration | Module interactions | XCTest + TestContainers |
| UI | SwiftUI views | ViewInspector |
| E2E | Full workflows | XCUITest |

### Mock Strategy

```swift
// Protocol-based mocking
protocol ModManagerProtocol {
    func install(_ source: ModSource) async throws -> Mod
}

class MockModManager: ModManagerProtocol {
    var installResult: Result<Mod, Error> = .failure(CyberModError.gameNotFound)
    
    func install(_ source: ModSource) async throws -> Mod {
        try installResult.get()
    }
}
```
