# CyberMod Studio - Agent Guidelines

## Project Context

CyberMod Studio is a native Swift/SwiftUI macOS application for managing Cyberpunk 2077 mods. It combines mod management, game launching, mod creation tools, Windows→macOS porting assistance, and runtime debugging into a unified platform.

## Current Status (Canonical)

See `docs/STATUS.md` for the up-to-date project status.

## Development Practices

### Swift Standards

1. **Swift 5.10+** with strict concurrency checking enabled
2. **SwiftUI** for all UI components - no AppKit unless absolutely necessary
3. **Actor-based concurrency** for shared state - use `actor` for services
4. **Async/await** for all I/O operations
5. **Codable** for all data models that need persistence

### Package Structure

1. **CyberModCore** - All business logic (no UI dependencies)
2. **CyberModCLI** - Command-line interface using ArgumentParser
3. **CyberModStudio** - SwiftUI macOS application

### Architecture Principles

1. **Separation of concerns** - Views → ViewModels → Services → Database
2. **Protocol-oriented** - Define protocols for testability
3. **Dependency injection** - Pass dependencies explicitly
4. **Actor isolation** - Use actors for all shared mutable state

## Code Standards

### Naming

1. **Types**: PascalCase - `ModManager`, `GameSession`, `TweakDBBrowser`
2. **Functions/Properties**: camelCase - `installMod()`, `isEnabled`
3. **Constants**: camelCase for local, SCREAMING_SNAKE for global
4. **Files**: Match primary type - `ModManager.swift`

### SwiftUI Views

1. **Extract subviews** when body exceeds ~50 lines
2. **Use @StateObject** for view-owned ViewModels
3. **Use @EnvironmentObject** for app-wide state
4. **Prefer** `@Binding` over callbacks for two-way data flow

### Error Handling

1. **Typed errors** - Use `CyberModError` enum
2. **LocalizedError** - Implement `errorDescription` and `recoverySuggestion`
3. **No force unwrapping** - Use `guard let` or `if let`
4. **Log errors** - Use swift-log before throwing

### Documentation

1. **Public APIs** - Document with `///` comments
2. **Complex logic** - Inline comments explaining "why"
3. **Type constraints** - Document any Sendable/actor requirements

## Key Files

| File | Purpose |
|------|---------|
| `Sources/CyberModCore/ModEngine/ModManager.swift` | Central mod operations |
| `Sources/CyberModCore/GameBridge/GameLauncher.swift` | Game launching |
| `Sources/CyberModCore/Database/ModDatabase.swift` | SQLite persistence |
| `CyberModStudio/CyberModStudioApp.swift` | App entry point |
| `docs/IPC_PROTOCOL.md` | Game communication protocol |

## Module Dependencies

```
CyberModStudio (App)
    └── CyberModCore
            ├── GRDB (database)
            ├── Yams (YAML parsing)
            ├── ZIPFoundation (archives)
            ├── AsyncHTTPClient (Nexus API)
            └── swift-log (logging)
```

## Testing

1. **Unit tests** for business logic in CyberModCore
2. **Integration tests** for database operations
3. **Use mocks** for external dependencies (Nexus API, file system)
4. **Test actors** using `await` in test methods

## Common Tasks

### Adding a New Feature

1. Define data models in `CyberModCore`
2. Add service actor with business logic
3. Create ViewModel for UI binding
4. Build SwiftUI view
5. Add tests

### Updating Database Schema

1. Add migration in `ModDatabase.migrate()`
2. Update row conversion methods
3. Increment schema version
4. Test migration path

### Adding CLI Command

1. Create command struct conforming to `AsyncParsableCommand`
2. Add to parent command's `subcommands` array
3. Implement `run()` method
4. Update README with usage

## Related Projects

All sibling projects live under `~/Development/cyberpunk/`:

- `RED4ext/` — Script extender
- `cp2077-tweak-xl/` — TweakXL
- `cp2077-archive-xl-macos/` — ArchiveXL
- `cp2077-modmenu/` — ModMenu
- `macos-modmanager/` — Python mod manager (superseded by this project)

## Common Pitfalls

1. **MainActor isolation** - ViewModels must be `@MainActor`
2. **Sendable conformance** - Data passed between actors must be Sendable
3. **Database access** - Always use `await` for database operations
4. **File paths** - Use `URL` not `String` for all file paths
