# CyberMod Studio — Status

> **Last updated:** 2026-10-07
> **Phase:** 1 (Mod Manager + Game Runner)
> **Platform:** macOS 14+ (Apple Silicon)

## What's complete

### cybermod CLI / CyberModKit (see docs/CLI.md)
- [x] Loader: install/update/uninstall the RED4ext macOS release (SHA256SUMS, build check, install_macos.sh), play
- [x] Mods: add from path/zip/7z/rar, https, GitHub, Nexus (premium + nxm://), registry; list/info/remove/enable/disable
- [x] adopt hand-installed mods, outdated/update, archive load order, doctor with fixes, JSON output
- [x] install.sh + release workflow

### Infrastructure
- [x] `CyberModCore` SPM package builds (all dependencies resolved)
- [x] `CyberModStudio.xcodeproj` generated via xcodegen, depends on CyberModCore
- [x] SQLite database (GRDB) with migrations for mods, profiles, deployed files

### Mod Manager (Phase 4.1)
- [x] `ModManager` actor with install/uninstall/enable/disable
- [x] `InstallModSheet` — file picker, FOMOD detection, staged install
- [x] `NexusBrowserSheet` — search, trending, file picker, download + auto-install
- [x] `ModManagerView` — mod list with search, enable/disable toggle, context menus
- [x] `ModDetailView` — metadata, mod types, dependencies, actions
- [x] Load order persistence via `profile_mods.load_order` in database
- [x] `CompatibilityChecker` — detects DLL-only mods, framework requirements
- [x] `DependencyResolver` — checks missing/version-mismatched deps
- [x] `ConflictDetector` — file-level conflict detection pre-install
- [x] `FomodParser` — parse ModuleConfig.xml and resolve file choices
- [x] `FomodInstallerSheet` — step-through wizard for FOMOD options

### Game Runner (Phase 4.2)
- [x] `GameLauncher` actor that runs the game folder's `launch_red4ext.sh`
- [x] `GameRunnerView` — launch button, status, uptime, PID display
- [x] Real-time uptime timer
- [x] Game path configuration (browse picker)
- [x] Framework status display (RED4ext, TweakXL, ArchiveXL, ModMenu)
- [x] Log viewer — reads latest RED4ext log, color-coded by level
- [x] Process monitoring via `ProcessMonitor` actor
- [x] Error display in UI

## Not yet started (Phase 2+)

- [ ] Debug Studio (in-game IPC)
- [ ] Creation Studio (mod project editor)
- [ ] Porting Studio (Windows→macOS guidance)

## Build

See README.md.

## Key files

| Area | File |
|------|------|
| App entry | `CyberModStudio/CyberModStudioApp.swift` |
| Navigation | `CyberModStudio/Views/ContentView.swift` |
| Mod list | `CyberModStudio/Views/ModManagerView.swift` |
| Nexus browser | `CyberModStudio/Views/NexusBrowserSheet.swift` |
| FOMOD wizard | `CyberModStudio/Views/FomodInstallerSheet.swift` |
| Mod engine | `Sources/CyberModCore/ModEngine/ModManager.swift` |
| Game launcher | `Sources/CyberModCore/GameBridge/GameLauncher.swift` |
| Database | `Sources/CyberModCore/Database/ModDatabase.swift` |
| Nexus API | `Sources/CyberModCore/NexusMods/NexusAPIClient.swift` |
| Xcode project | `project.yml` (xcodegen spec) |
