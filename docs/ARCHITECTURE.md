# Architecture

```
CyberModKit (library)      all mod logic; Foundation, CryptoKit, Security only
   ^        ^
   |        CyberModModel (library)   @MainActor @Observable AppModel: state + one method per user action
   |           ^
cybermod     CyberMod Studio.app (Xcode, CyberModStudio/)   SwiftUI views over AppModel
(CLI)
```

## CyberModKit (`Sources/CyberModKit`)

| File | What |
|---|---|
| `Kit.swift` | `Kit`: game folder, state folder, `dryRun`, `log` (progress lines), seams (`session`, `isGameRunning`, `openURL`); `KitError {message, hint, details}`; `Config` |
| `Placement.swift` | where each file of a mod goes on macOS; refuses Windows-only content |
| `ModStore.swift` | one manifest per mod (`<state>/mods/<id>.json`), install / remove / enable / disable (hold folder) / adopt |
| `Sources.swift` | `ModSource` (path, https, `github:`, `nexus:`, `nxm://`, `registry:`), fetch + unpack, `ModStore.add` |
| `Network.swift` | HTTP, GitHub releases, Nexus Mods API v1, Keychain (`Secrets`) |
| `Loader.swift` | RED4ext bundle install / update / uninstall (verified zip, address-DB build check), Mach-O UUID |
| `Play.swift` | `PlaySession`: runs `<game>/launch_red4ext.sh`, events (`output`, `compileFailed`, `gameStarted`, `exited(report)`), `stop()` |
| `Doctor.swift` | findings with stable ids and fix ids, `Doctor.fix`, RDAR archive tables and conflicts |
| `Library.swift` | `Updates.check`, `ModStore.update`, `LoadOrder.list` / `prioritize` (`!` prefix rename, recorded in the manifest) |
| `Registry.swift` | community index (docs/REGISTRY.md) |

Long calls are `async` and stop before changing anything once their task is cancelled (downloads and unpacking go to a
temp folder; copies land next to their destination and are renamed into place).

## CyberModModel (`Sources/CyberModModel/AppModel.swift`)

`AppModel(kit:)` holds what the screens show (`mods`, `unmanaged`, `doctor`, `archives`, `updates`, `registry`,
`activities`, `play`, `gameOutput`, `lastExit`, `failure`, `notice`, `nexusWaiting`) and one method per action
(`add`, `setEnabled`, `remove`, `adopt`, `installLoader`, `fix`, `prioritize`, `checkForUpdates`, `update`,
`startGame`, `stopGame`, settings). Every action goes through `run(_:)`: one at a time, off the main thread, refused
while the game runs, cancellable (`cancel()`), recorded as an `Activity` with the library's progress lines, errors
turned into `failure` (the `KitError` with its `Next:` hint), then `refresh()` re-reads the game folder.
No mod rules live here; it only calls the library and arranges results for display.

Non-Premium Nexus downloads: the library opens the files page and throws `Nexus.premiumOnly`; the model turns that into
`nexusWaiting`, and the `nxm://` link the browser hands to the app (`onOpenURL`) continues the install.

## App (`CyberModStudio/`, project generated from `project.yml` by xcodegen)

| Path | What |
|---|---|
| `App/CyberModStudioApp.swift` | single `Window` + `Settings` scenes, sidebar, window-wide drop, alerts, menu commands, `onOpenURL` |
| `Features/Play` | first-run checklist, Play/Stop, game output, exit report |
| `Features/Library` | mods table, filters, inspector, updates, remove |
| `Features/LoadOrder` | archives in load order, overlaps, Move Up / Let X Win |
| `Features/Discover` | add from a link, Nexus Mods and nxm:// handler status, registry search |
| `Features/Health` | doctor findings with Fix buttons, mod loader |
| `Features/Activity` | operations with output and Cancel |
| `Features/Settings` | game folder, Nexus API key, nxm:// handler, registry URL |
| `Components/` | shared presentation helpers |
| `Info.plist` | `CFBundleURLTypes` for `nxm` (merged into the generated Info.plist) |

The app is unsandboxed (it writes the game folder and runs the launcher script) with the hardened runtime.

## State

`~/Library/Application Support/CyberModStudio/` (or `$CYBERMOD_HOME`): `config.json`, and per game folder
`games/<hash>/` with mod manifests, disabled mods, `red4ext.json`, `removed/`. Game output:
`~/Library/Logs/CyberModStudio/game.log`. Nexus API key: Keychain, service `CyberModStudio`.

## Tests

`swift test`: `CyberModKitTests` (placement, store, loader, doctor, play, network over a URLProtocol stub) and
`CyberModModelTests` (the app's flows through `AppModel`: first run, loader from a zip, add / disable / enable / remove,
adopt, load order, doctor fix, play with a stub launcher, errors, cancellation, Nexus nxm handoff). All use temporary
fake game folders; nothing touches the real game, Steam or the network.
