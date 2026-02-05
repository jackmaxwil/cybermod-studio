# CyberMod Studio

A native macOS application for managing, creating, porting, and debugging Cyberpunk 2077 mods on Apple Silicon.

## Overview

CyberMod Studio is an all-in-one solution for the Cyberpunk 2077 modding ecosystem on macOS, featuring:

- **Mod Manager** - Install, organize, and manage mods with profiles
- **Game Runner** - Launch the game with mod injection and monitoring
- **Creation Studio** - Create TweakXL/ArchiveXL mods with validation
- **Porting Studio** - Port Windows mods to macOS
- **Debug Studio** - Runtime debugging with TweakDB inspection

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (ARM64) - Intel Macs supported via Rosetta 2
- Cyberpunk 2077 (macOS version)
- Xcode 15+ (for building from source)

## Installation

### From Release

Download the latest release from the Releases page and drag `CyberMod Studio.app` to your Applications folder.

### From Source

```bash
# Clone the repository
git clone https://github.com/yourusername/cybermod-studio.git
cd cybermod-studio

# Build with Swift Package Manager
swift build -c release

# Or open in Xcode
open Package.swift
```

## Quick Start

1. **Configure Game Path**: On first launch, select your Cyberpunk 2077 installation directory
2. **Create a Profile**: Set up a mod profile for organizing your mods
3. **Install Mods**: Drag-and-drop mod archives or browse Nexus Mods
4. **Launch Game**: Click "Launch" to start with your enabled mods

## Architecture

CyberMod Studio uses a server-client architecture:

```
┌─────────────────────────────────────┐
│     CyberMod Studio (SwiftUI)       │
│  ┌─────────┐ ┌─────────┐ ┌───────┐  │
│  │   Mod   │ │  Game   │ │Debug  │  │
│  │ Manager │ │ Runner  │ │Studio │  │
│  └────┬────┘ └────┬────┘ └───┬───┘  │
│       └───────────┼──────────┘      │
│                   │                 │
│           CyberModCore              │
│         (Swift Package)             │
└───────────────────┼─────────────────┘
                    │ XPC
┌───────────────────┼─────────────────┐
│           CyberModDaemon            │
│         (Privileged Helper)         │
└───────────────────┼─────────────────┘
                    │ DYLD_INSERT
┌───────────────────┼─────────────────┐
│           Game Process              │
│  RED4ext │ FridaGadget │ DebugAgent │
└─────────────────────────────────────┘
```

## Project Structure

```
cybermod-studio/
├── Package.swift              # Swift Package manifest
├── Sources/
│   ├── CyberModCore/         # Core business logic
│   │   ├── ModEngine/        # Mod management
│   │   ├── GameBridge/       # Game launching
│   │   ├── Database/         # SQLite persistence
│   │   └── IPC/              # Inter-process communication
│   ├── CyberModCLI/          # Command-line interface
│   └── CyberModDaemon/       # Privileged helper
├── CyberModStudio/           # SwiftUI macOS app
│   ├── Views/                # UI views
│   ├── ViewModels/           # Observable state
│   └── Resources/            # Assets
├── Tests/                    # Unit & integration tests
└── docs/                     # Documentation
```

## CLI Usage

```bash
# List installed mods
cybermod list

# Install a mod
cybermod install /path/to/mod.zip

# Enable/disable mods
cybermod enable "Mod Name"
cybermod disable "Mod Name"

# Manage profiles
cybermod profile list
cybermod profile create MyProfile --game-path /path/to/game
cybermod profile activate MyProfile

# Launch game
cybermod launch
cybermod launch --debug  # With debug agent
```

## Documentation

- [Product Requirements (PRD)](docs/PRD.md)
- [System Design](docs/DESIGN.md)
- [View Architecture](docs/VIEWS.md)
- [IPC Protocol](docs/IPC_PROTOCOL.md)
- [Architecture Overview](docs/ARCHITECTURE.md)
- [TweakDB Schema](docs/schemas/TWEAKDB_SCHEMA.md)
- [ArchiveXL Schema](docs/schemas/ARCHIVEXL_SCHEMA.md)

## Dependencies

CyberMod Studio relies on the following macOS mod infrastructure:

- [RED4ext](https://github.com/WopsS/RED4ext) - Script extender (macOS port)
- [TweakXL](https://github.com/psiberx/cp2077-tweak-xl) - TweakDB modifications (macOS port)
- [ArchiveXL](https://github.com/psiberx/cp2077-archive-xl) - Resource extensions (macOS port)
- [Frida](https://frida.re/) - Dynamic instrumentation for hooking

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- CDPR for Cyberpunk 2077
- The Windows modding community for pioneering tools
- WopsS for RED4ext
- psiberx for TweakXL and ArchiveXL
