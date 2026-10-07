# CyberMod Studio - Product Requirements Document

## Executive Summary

CyberMod Studio is a native macOS application that provides a unified platform for managing, creating, porting, and debugging Cyberpunk 2077 mods on macOS ARM64. It consolidates five distinct workflows into a single, professional-grade tool with a server-client architecture enabling real-time game integration.

## Problem Statement

### Current State
The macOS Cyberpunk 2077 modding ecosystem is fragmented across multiple tools:

1. **Python Mod Manager** - Functional but requires Python runtime, lacks native UI
2. **RED4ext Launcher** - Shell scripts for game injection
3. **Manual File Editing** - No integrated IDE for tweak/archive files
4. **Windows→macOS Porting** - Entirely manual process requiring deep binary knowledge
5. **Debugging** - No integrated tooling; relies on log files and guesswork

### Pain Points
- **No unified workflow**: Switching between terminal, text editors, and file managers
- **Non-native experience**: Python TUI/Web UI feels foreign on macOS
- **Complex porting**: Windows mod authors struggle to port without macOS expertise
- **Blind debugging**: No visibility into runtime TweakDB state or hook behavior
- **Manual address updates**: Game patches require tedious offset recalculation

## Product Vision

**"The Xcode of Cyberpunk 2077 modding for macOS"**

A single application where mod users can install and manage mods, mod creators can build and test their work, and porters can bring Windows mods to macOS—all with deep game integration for real-time debugging.

## Target Users

### Primary Personas

#### 1. Mod User (60% of users)
- Wants to install mods and play
- May not have technical background
- Values one-click installation and profile management
- Needs compatibility checking for macOS

#### 2. Mod Creator (25% of users)
- Creates TweakXL/ArchiveXL content
- Needs IDE-like experience with validation
- Wants hot-reload for rapid iteration
- Values runtime debugging capabilities

#### 3. Mod Porter (10% of users)
- Ports Windows mods to macOS
- Needs address mapping tools
- Requires binary analysis assistance
- Values scaffold generation

#### 4. Plugin Developer (5% of users)
- Develops RED4ext native plugins
- Needs full debugging capabilities
- Requires hook monitoring and memory inspection
- Values build system integration

## Feature Requirements

### F1: Mod Manager Module

#### F1.1 Installation
| ID | Requirement | Priority |
|----|-------------|----------|
| F1.1.1 | Install mods from local archives (ZIP, 7Z, RAR) | P0 |
| F1.1.2 | Download and install from Nexus Mods | P0 |
| F1.1.3 | FOMOD installer with native wizard UI | P0 |
| F1.1.4 | Transaction-safe installation with rollback | P0 |
| F1.1.5 | Automatic dependency resolution | P1 |
| F1.1.6 | Batch installation from collections | P1 |

#### F1.2 Management
| ID | Requirement | Priority |
|----|-------------|----------|
| F1.2.1 | Enable/disable mods without uninstalling | P0 |
| F1.2.2 | Profile system for mod sets | P0 |
| F1.2.3 | Load order management with drag-drop | P0 |
| F1.2.4 | Conflict detection and resolution UI | P1 |
| F1.2.5 | Automatic backup before changes | P1 |
| F1.2.6 | Version tracking and update checking | P2 |

#### F1.3 Compatibility
| ID | Requirement | Priority |
|----|-------------|----------|
| F1.3.1 | Detect Windows-only mods (DLL without dylib) | P0 |
| F1.3.2 | Identify missing dependencies (RED4ext, TweakXL, etc.) | P0 |
| F1.3.3 | Compatibility score/rating display | P1 |
| F1.3.4 | Suggest macOS alternatives for incompatible mods | P2 |

### F2: Game Runner Module

#### F2.1 Launch
| ID | Requirement | Priority |
|----|-------------|----------|
| F2.1.1 | One-click launch with active mod profile | P0 |
| F2.1.2 | Automatic dylib injection (DYLD_INSERT_LIBRARIES) | P0 |
| F2.1.3 | Launch argument customization | P1 |
| F2.1.4 | Multiple game installation support | P1 |

#### F2.2 Monitoring
| ID | Requirement | Priority |
|----|-------------|----------|
| F2.2.1 | Process status (running/stopped) | P0 |
| F2.2.2 | Crash detection with diagnostic collection | P0 |
| F2.2.3 | Real-time log streaming | P1 |
| F2.2.4 | Resource usage (CPU, memory) | P2 |

### F3: Creation Studio Module

#### F3.1 Project Management
| ID | Requirement | Priority |
|----|-------------|----------|
| F3.1.1 | Create new mod projects (TweakXL, ArchiveXL, RED4ext) | P0 |
| F3.1.2 | Project templates with best practices | P0 |
| F3.1.3 | Project navigator with file tree | P0 |
| F3.1.4 | Build system integration (CMake, xmake) | P1 |

#### F3.2 Editors
| ID | Requirement | Priority |
|----|-------------|----------|
| F3.2.1 | YAML editor with syntax highlighting | P0 |
| F3.2.2 | TweakDB schema validation | P0 |
| F3.2.3 | ArchiveXL (.xl) schema validation | P0 |
| F3.2.4 | Redscript editor with highlighting | P1 |
| F3.2.5 | C++ editor for RED4ext plugins | P2 |
| F3.2.6 | Auto-completion for TweakDB records/flats | P1 |

#### F3.3 Live Development
| ID | Requirement | Priority |
|----|-------------|----------|
| F3.3.1 | Hot-reload tweaks to running game | P1 |
| F3.3.2 | File watcher for auto-reload | P1 |
| F3.3.3 | Preview changes before applying | P2 |

### F4: Porting Studio Module

#### F4.1 Analysis
| ID | Requirement | Priority |
|----|-------------|----------|
| F4.1.1 | Analyze Windows mod structure | P0 |
| F4.1.2 | Identify mod type (archive, tweak, plugin, script) | P0 |
| F4.1.3 | Extract Windows address hashes from DLLs | P1 |
| F4.1.4 | Generate portability report | P0 |

#### F4.2 Porting Tools
| ID | Requirement | Priority |
|----|-------------|----------|
| F4.2.1 | Auto-port archive-only mods | P0 |
| F4.2.2 | Address mapping editor (Windows→macOS) | P0 |
| F4.2.3 | Generate macOS scaffold for plugins | P1 |
| F4.2.4 | Hook signature comparison | P2 |

### F5: Debug Studio Module

#### F5.1 Runtime Inspection
| ID | Requirement | Priority |
|----|-------------|----------|
| F5.1.1 | Live TweakDB browser (view records/flats) | P0 |
| F5.1.2 | TweakDB value editing at runtime | P1 |
| F5.1.3 | Hook monitor (active hooks, call stats) | P0 |
| F5.1.4 | Plugin inspector (loaded plugins, status) | P0 |

#### F5.2 Memory & Debugging
| ID | Requirement | Priority |
|----|-------------|----------|
| F5.2.1 | Memory region viewer | P1 |
| F5.2.2 | Address resolution debugger | P0 |
| F5.2.3 | Unified log viewer (all sources) | P0 |
| F5.2.4 | Performance profiler (hook overhead) | P2 |

## Technical Requirements

### T1: Platform
| ID | Requirement |
|----|-------------|
| T1.1 | macOS 14.0 (Sonoma) minimum |
| T1.2 | Apple Silicon (ARM64) native |
| T1.3 | Intel support via Rosetta 2 (best-effort) |
| T1.4 | Sandbox-compatible where possible |

### T2: Architecture
| ID | Requirement |
|----|-------------|
| T2.1 | SwiftUI for all UI components |
| T2.2 | Swift Package for core logic (CyberModCore) |
| T2.3 | XPC for daemon communication |
| T2.4 | SQLite/GRDB for persistence |
| T2.5 | Actor-based concurrency model |

### T3: Integration
| ID | Requirement |
|----|-------------|
| T3.1 | Nexus Mods API v1 + GraphQL v2 |
| T3.2 | RED4ext (DYLD_INSERT_LIBRARIES) for hook orchestration |
| T3.3 | RED4ext SDK compatibility |
| T3.4 | IPC protocol for game communication |

## Non-Functional Requirements

### Performance
- App launch to usable: < 2 seconds
- Mod installation (100MB archive): < 10 seconds
- TweakDB browser refresh: < 500ms
- Game launch latency overhead: < 1 second

### Reliability
- Zero data loss on crash (transaction safety)
- Automatic crash recovery for game sessions
- Rollback capability for all mod operations

### Security
- Nexus API key stored in Keychain
- No plaintext secrets in database
- Signed binaries for Gatekeeper
- Notarized for distribution

### Usability
- Keyboard navigation throughout
- VoiceOver accessibility support
- Consistent with macOS HIG
- Contextual help system

## Success Metrics

| Metric | Target |
|--------|--------|
| Mod installation success rate | > 95% |
| Time to first mod installed | < 5 minutes |
| Crash-free sessions | > 99% |
| User retention (weekly) | > 70% |
| Porting success rate (auto-portable mods) | > 90% |

## Roadmap

### Phase 1: Foundation (MVP)
- Mod Manager (install, enable/disable, profiles)
- Game Runner (launch, basic monitoring)
- Basic Creation Studio (project creation, YAML editor)

### Phase 2: Advanced Management
- FOMOD installer
- Nexus Mods integration
- Dependency resolution
- Conflict detection

### Phase 3: Creation & Porting
- Full Creation Studio (all editors, validation)
- Porting Studio (analysis, auto-port, scaffold)
- Hot-reload support

### Phase 4: Debugging
- Debug Studio (TweakDB browser, hooks, memory)
- IPC protocol implementation
- Performance profiler

### Phase 5: Polish
- Plugin marketplace
- Cloud sync (profiles, settings)
- Localization
- Documentation generator

## Appendices

### A. Glossary
- **TweakDB**: Game's runtime database for stats, items, vehicles
- **RED4ext**: Script extender/mod loader for native plugins
- **TweakXL**: Mod for runtime TweakDB modifications
- **ArchiveXL**: Mod for extending game resources
- **FOMOD**: Mod installer format with conditional options

### B. References
- [RED4ext macOS Port](../related/RED4ext)
- [TweakXL macOS Port](../related/cp2077-tweak-xl)
- [ArchiveXL macOS Port](../related/cp2077-archive-xl-macos)
- [Existing Python Mod Manager](../related/macos-modmanager)
