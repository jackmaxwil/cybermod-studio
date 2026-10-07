# CyberMod Studio - Agent Notes

SwiftUI macOS app + `cybermod` CLI for Cyberpunk 2077 mods on top of RED4ext for macOS. Branch: `main` only.
Design: `docs/ARCHITECTURE.md`. CLI reference: `docs/CLI.md`. Registry format: `docs/REGISTRY.md`.

## Layout

- `Sources/CyberModKit/` - all logic: `Kit` (paths, config, seams), `Placement`, `ModStore` (manifests, add/remove/
  enable/disable/adopt), `Sources` (path/URL/github/nexus/nxm/registry), `Network` (HTTP, GitHub, Nexus, Keychain),
  `Loader` (RED4ext bundle), `Play` (launch_red4ext.sh session events), `Doctor` (findings, fixes, RDAR conflicts),
  `Library` (updates, load order), `Registry`. Foundation/CryptoKit/Security only.
- `Sources/CyberModModel/` - `AppModel`, the app's state and one method per user action over CyberModKit. No views,
  no mod rules.
- `Sources/CyberModCLI/` - `cybermod` (ArgumentParser), parsing and printing only.
- `CyberModStudio/` - SwiftUI app (`App/`, `Features/<Screen>/`, `Components/`, `Info.plist` with the `nxm` URL type).
  `CyberModStudio.xcodeproj` is generated from `project.yml`: after adding or removing app files run `xcodegen generate`
  and commit the project.
- `install.sh` (CLI, or the app with `--app`), `.github/workflows/release.yml` (tag `vX.Y.Z[-rcN]` -> release).

## Build and test

```bash
swift build && swift test
xcodebuild -project CyberModStudio.xcodeproj -scheme CyberModStudio -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build
```

CI: `.github/workflows/build-macos.yml` runs exactly these.

## Rules

- Logic goes in CyberModKit, so the CLI and the app behave the same; the model only calls it, views only call the model.
- Errors are `KitError(message, hint:, details:)`; the hint says what to do next. Never swallow errors in views.
- Launching goes through `<game>/launch_red4ext.sh` (from the RED4ext repo). Do not reimplement its steps in Swift
  (UUID/signature pre-flight, plugin gate, scc, `inputloader.pl`, unstaging). Change the script in RED4ext instead.
- Never re-sign the game binary from this repo; never start Steam or the game automatically.
- Install locations: `.archive`/`.archive.xl` -> `archive/pc/mod/` (loaded by ArchiveXL on macOS); tweaks ->
  `r6/tweaks/`; `.reds` -> `r6/scripts/`; RED4ext plugins -> `red4ext/plugins/<Name>/` (`.dylib` only).
- Tests must not launch the game or Steam and must use temporary fake game folders (see the fixtures in
  `Tests/CyberModKitTests/Helpers.swift` and `Tests/CyberModModelTests/AppModelTests.swift`; the launcher is a stub
  script, the network a URLProtocol stub).
- To look at the app without touching your real game, run the built binary with a fake folder:
  `CP2077_GAME_DIR=/tmp/fake/Cyberpunk\ 2077 CYBERMOD_HOME=/tmp/fake/home "build/Build/Products/Release/CyberMod Studio.app/Contents/MacOS/CyberMod Studio"`
  (the folder needs `Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`; never press Play there unless `launch_red4ext.sh` is a stub).
- Swift 5.10 language mode, `@MainActor` for UI state, async/await for I/O, `URL` for paths.
