# CyberMod Studio - Agent Notes

SwiftUI macOS app + `cybermod` CLI for Cyberpunk 2077 mods on top of RED4ext for macOS. Branch: `main` only.

## Layout

- `Sources/CyberModKit/` - all logic for `cybermod` (and the app's redesign): `Kit` (paths, config, seams), `Placement`
  (where mod files go), `ModStore` (per-mod manifests, add/remove/enable/disable/adopt), `Sources` (path/URL/github/
  nexus/nxm/registry), `Network` (HTTP, GitHub, Nexus, Keychain), `Loader` (RED4ext bundle install/uninstall),
  `Play` (launch_red4ext.sh session events), `Doctor` (RDAR conflicts, findings, fixes), `Library` (updates, load order),
  `Registry`. Foundation/CryptoKit/Security only.
- `Sources/CyberModCLI/` - `cybermod` (ArgumentParser), parsing and printing only. Reference: `docs/CLI.md`
- `Sources/CyberModCore/` - legacy logic the current SwiftUI app still uses; delete once the app moves to CyberModKit
- `CyberModStudio/` - SwiftUI app; `CyberModStudio.xcodeproj` is generated from `project.yml` (xcodegen)
- `install.sh` (CLI installer), `.github/workflows/release.yml` (tag `vX.Y.Z[-rcN]` -> release; manual run = dry run)

## Build and test

```bash
swift build && swift test
xcodebuild -project CyberModStudio.xcodeproj -scheme CyberModStudio -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build
```

CI: `.github/workflows/build-macos.yml` runs exactly these.

## Rules

- Launching goes through `<game>/launch_red4ext.sh` (from the RED4ext repo). Do not reimplement its steps in Swift
  (UUID/signature pre-flight, plugin gate via `red4ext_plugin_check`, scc, `inputloader.pl` run from the game
  folder, unstaging). Change the script in RED4ext instead.
- Never re-sign the game binary from this app.
- Install locations: `.archive`/`.archive.xl` -> `archive/pc/mod/` (loaded by ArchiveXL, not the game, on macOS);
  tweaks -> `r6/tweaks/`; `.reds` -> `r6/scripts/`; RED4ext plugins -> `red4ext/plugins/<Name>/` (`.dylib` only).
- Tests must not launch the game or Steam, and must use temporary fake game folders (`Tests/CyberModKitTests/Helpers.swift`).
- Swift 5.10, actors for shared state, async/await for I/O, `URL` for paths.
