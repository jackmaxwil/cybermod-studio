# CyberMod Studio

A macOS app (plus a `cybermod` command-line tool) for installing Cyberpunk 2077 mods and starting the game with
[RED4ext for macOS](https://github.com/jackmaxwil/RED4ext-macos). It does not replace RED4ext: launching always goes through
RED4ext's own `launch_red4ext.sh` in your game folder.

## Requirements

- Apple Silicon Mac, macOS 14 or newer
- Xcode 16 or newer (to build the app)
- Cyberpunk 2077 from Steam, macOS version
- RED4ext macOS release installed in the game folder (you should have `launch_red4ext.sh` next to `Cyberpunk2077.app`)
- For `.archive` mods: **ArchiveXL** (`red4ext/plugins/ArchiveXL/`). On macOS the game does not load
  `archive/pc/mod` by itself; ArchiveXL does.
- For tweak mods (`r6/tweaks`): **TweakXL** (`red4ext/plugins/TweakXL/`)

## Build and install the app

```bash
git clone https://github.com/jackmaxwil/cybermod-studio.git
cd cybermod-studio
xcodebuild -project CyberModStudio.xcodeproj -scheme CyberModStudio -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build
cp -R "build/Build/Products/Release/CyberMod Studio.app" /Applications/
```

Optional command-line tool: `swift build -c release`, then use `.build/release/cybermod`.

## First run

1. Open **CyberMod Studio** from Applications.
2. It creates a profile called "Default" pointing at
   `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077`. If your game is somewhere else, see
   Troubleshooting.
3. Start Steam and sign in (otherwise the game has no saves).
4. **Mod Manager** → Install → pick a mod `.zip`. Files go where the game expects them:

   | Mod file | Goes to | Needs |
   |----------|---------|-------|
   | `.archive`, `.archive.xl` | `archive/pc/mod/` | ArchiveXL |
   | `.yaml` / `.yml` tweaks | `r6/tweaks/` | TweakXL |
   | `.reds` scripts | `r6/scripts/` | nothing extra |
   | RED4ext plugin `.dylib` | `red4ext/plugins/<Name>/` | macOS build only (Windows `.dll` will not work) |

5. **Game Runner** → Launch. Output goes to `~/Library/Logs/CyberModStudio/game.log`.

## Troubleshooting

- **If launch says "RED4ext is not installed"**, install a RED4ext macOS release into the game folder.
- **If the launch stops with "The game was updated to a build this RED4ext release does not support yet"**, wait for
  a RED4ext release for the new game version. Steam's Play button still starts the game without mods.
- **If it says "The game binary is not set up for RED4ext"** (Steam updated or verified the game), run
  `"<game folder>/red4ext/macos/scripts/install_macos.sh"` once, then launch again.
- **If it says "REDscript compilation failed"**, open `~/Library/Logs/CyberModStudio/game.log`, find the `.reds` file
  named in the `[ERROR` lines and remove or update that mod.
- **If the log says "Not compiling X's scripts"**, RED4ext will not load plugin X for this game version; update the
  plugin.
- **If an `.archive` mod does nothing**, install ArchiveXL.
- **If "Steam is not running"** appears or saves are missing, start Steam and sign in, then launch again.
- **If your game is not in the default Steam folder**, point the profile at it once:
  `.build/release/cybermod profile create Game --game-path "/path/to/Cyberpunk 2077"` then
  `.build/release/cybermod profile activate Game`.
- **If the game crashes**, check `~/Library/Logs/DiagnosticReports/Cyberpunk2077*.ips` and `<game folder>/red4ext/logs/`.

## Build from source (developers)

```bash
swift build          # core library + cybermod CLI
swift test           # unit tests
xcodebuild -project CyberModStudio.xcodeproj -scheme CyberModStudio -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build   # the app
```

CI (`.github/workflows/build-macos.yml`) runs the same commands. The Xcode project is generated from `project.yml`
with [xcodegen](https://github.com/yonaskolb/XcodeGen); run `xcodegen` after adding or removing app source files.

Layout: `Sources/CyberModCore` (logic), `Sources/CyberModCLI` (CLI), `CyberModStudio/` (SwiftUI app),
`docs/` (design notes).
