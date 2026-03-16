# CyberMod Studio

Native macOS application for managing Cyberpunk 2077 mods.

**Status:** Phase 1 complete — Mod Manager and Game Runner functional.

## What it does

CyberMod Studio is a SwiftUI application that combines mod management, game launching, and framework monitoring into a single native macOS app. It replaces the Python-based `macos-modmanager` with a faster, more integrated experience.

### Phase 1 (Complete)

- **Mod Manager** — install from disk or Nexus Mods, FOMOD wizard, enable/disable, load order, compatibility checks, conflict detection
- **Game Runner** — launch with DYLD injection, real-time log viewer, framework status, process monitoring

### Phase 2+ (Planned)

- Privileged daemon (XPC)
- Debug Studio (in-game IPC)
- Creation Studio (mod project editor)
- Porting Studio (Windows-to-macOS guidance)

## Prerequisites

- macOS 14+, Xcode 15+
- Swift 5.10+

## Build

```bash
# SPM package
swift build --target CyberModCore

# Xcode project (generated via xcodegen)
open CyberModStudio.xcodeproj
```

## Key files

| File | Purpose |
|------|---------|
| `Sources/CyberModCore/` | Business logic (ModManager, GameLauncher, ModDatabase) |
| `CyberModStudio/` | SwiftUI views and app entry point |
| `project.yml` | xcodegen project spec |
| `Package.swift` | SPM package definition |
| `docs/STATUS.md` | Project status |

## Related projects

| Project | Description |
|---------|-------------|
| [RED4ext](../RED4ext) | Core mod loader (launched by Game Runner) |
| [TweakXL](../cp2077-tweak-xl) | Managed as framework dependency |
| [ArchiveXL](../cp2077-archive-xl-macos) | Managed as framework dependency |
| [ModMenu](../cp2077-modmenu) | In-game settings companion |
| [macos-modmanager](../macos-modmanager) | Python predecessor (superseded) |
