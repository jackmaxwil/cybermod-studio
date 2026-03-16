# Cyberpunk 2077 macOS Modding Ecosystem — Execution Plan

> **Created:** 2026-02-08
> **Target:** 100% completion of all projects
> **Constraint:** 1 sequential AI agent
> **Excluded:** Python mod manager (discontinued)

---

## Runtime Environment & Agent Assumptions

### Environment

The executing agent operates in a **CLI terminal** (zsh on macOS ARM64). It has
full shell access, can build projects, read logs, and launch the game. It does
**not** have GUI automation — it cannot click menus, navigate game UI, or
interact with in-game prompts.

### Human-in-the-loop

A human operator is always present and will handle all GUI interactions:

- **Game startup:** After the agent launches the game via the launcher script,
  the human will navigate from the main menu into gameplay (load save, start
  new game, etc.) whenever the agent needs in-game verification.
- **In-game checks:** The human can confirm visual results (e.g., "does the
  settings menu appear when you press F10?", "do custom appearances load?").
- **Crash reporting:** If the game crashes, the human will report what happened
  and the agent will read crash logs.

**The agent should never wait or ask "please launch the game" — it should launch
the game itself and assume the human will progress past the main menu.**

### How to Launch the Game

There are two launcher scripts. **Always prefer the installed launcher** in the
game directory, since it picks up Frida Gadget, address databases, and
REDscript compilation automatically.

**Installed launcher (preferred):**

```bash
cd "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
./launch_red4ext.sh
```

This script:
1. Builds the `DYLD_INSERT_LIBRARIES` injection list (RED4ext.dylib + FridaGadget.dylib)
2. Compiles REDscript sources if the compiler is present
3. Processes input mappings if the loader is present
4. Launches the game binary with injection environment variables

**Development launcher (fallback, if installed launcher doesn't exist):**

```bash
cd ~/Development/cyberpunk/RED4ext
./red4ext_launcher.sh
```

This simpler script injects `RED4ext.dylib` from `$(pwd)/bin/` but does **not**
handle Frida Gadget, REDscript compilation, or input mappings.

### Game Directory Layout

```
~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/
├── Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077   # Game binary
├── launch_red4ext.sh                                 # Installed launcher
├── red4ext/
│   ├── RED4ext.dylib                                 # Loader
│   ├── FridaGadget.dylib                             # Hooking runtime
│   ├── FridaGadget.config                            # Frida config
│   ├── red4ext_hooks.js                              # Hook definitions
│   ├── config.ini                                    # RED4ext config
│   ├── logs/red4ext.log                              # Loader log (check after launch)
│   ├── bin/x64/
│   │   ├── cyberpunk2077_addresses.json              # SDK address DB
│   │   └── cyberpunk2077_symbols.json                # Symbol mappings
│   └── plugins/
│       ├── TweakXL/TweakXL.dylib
│       ├── ArchiveXL/ArchiveXL.dylib
│       ├── ModMenu/libModMenu.dylib
│       └── MetalFXDenoiser/MetalFXDenoiser.dylib
├── r6/
│   ├── tweaks/                                       # TweakXL tweak files
│   └── scripts/                                      # REDscript mods
└── archive/pc/mod/                                   # Archive mods
```

### Log Checking Pattern

After every game launch, the agent should:

```bash
# Wait for game to start and RED4ext to initialize
sleep 10

# Check RED4ext loader log
cat "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/red4ext/logs/red4ext.log"

# Check plugin-specific logs (if they exist)
cat "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/red4ext/plugins/TweakXL/TweakXL.log" 2>/dev/null
```

### Installing Built Plugins

After building a plugin, copy it to the game directory:

```bash
GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"

# TweakXL
cp build/TweakXL.dylib "$GAME_DIR/red4ext/plugins/TweakXL/"

# ArchiveXL
cp build-macos/ArchiveXL.dylib "$GAME_DIR/red4ext/plugins/ArchiveXL/"

# ModMenu
cp build/libModMenu.dylib "$GAME_DIR/red4ext/plugins/ModMenu/"

# MetalFX Denoiser
cp build/MetalFXDenoiser.dylib "$GAME_DIR/red4ext/plugins/MetalFXDenoiser/"
cp build/MetalFXDenoiserCore.dylib "$GAME_DIR/red4ext/plugins/MetalFXDenoiser/"
```

---

## Dependency Graph

```
RED4ext (foundation)
  └─► RED4ext.SDK (foundation)
        ├─► TweakXL (plugin)
        ├─► ArchiveXL (plugin)
        ├─► ModMenu (plugin)
        └─► MetalFX Denoiser (plugin)
              │
              ▼
        CyberMod Studio (umbrella app — manages all of the above)
```

## Execution Order Rationale

Everything depends on RED4ext + SDK being rock-solid. Plugins are ordered by
completeness (finish what's closest first, unblock integration testing early).
CyberMod Studio comes last because it manages the entire stack and benefits
from every plugin being testable.

---

## Phase 1 — Foundation Hardening (COMPLETED 2026-02-08)

### Critical lessons learned

1. **Always build with `-DRED4EXT_USE_FRIDA_GUM=OFF`**. Embedding Frida Gum alongside external FridaGadget.dylib causes a fatal crash.
2. **Game binary re-signing is required** after every Steam "Verify integrity" operation. The hardened runtime flag blocks DYLD_INSERT_LIBRARIES. Sign outside the bundle: `cp "$GAME_BIN" /tmp/sign && codesign -f -s - --entitlements scripts/red4ext_entitlements.plist --options runtime /tmp/sign && cp /tmp/sign "$GAME_BIN"`
3. **Image base fix**: Both the loader (`Addresses.cpp`) and SDK (`Relocation-inl.hpp`) were using `_dyld_get_image_header(0)` which returns RED4ext.dylib (not the game) when DYLD injection is active. Fixed to iterate `_dyld_image_count()` and find the image matching `_NSGetExecutablePath()`.
4. **Address formula fix**: The loader's address calculation was `base + slide + segmentOffset + offset` which double-counted ASLR slide. Fixed to store runtime segment bases (vmaddr + slide) and use `segmentBase + offset`.

### 1.1 RED4ext — Results

| # | Task | Result |
|---|------|--------|
| 1 | Runtime-verify 126 addresses | 28 PASS, 0 read failures, 87 fail (NULL or wrong offset). All resolved addresses point to valid memory. |
| 2 | Fix bad addresses | Deferred — requires regenerating address DB with corrected segment handling |
| 3 | Stress-test hook stack | 3 plugins loaded simultaneously, no hook collisions, game stable |
| 4 | Harden plugin error paths | Broken dylib logged as error ("slice is not valid mach-o"), other plugins still loaded |
| 5 | Code-sign automation | `scripts/sign_all.sh` works |
| 6 | CI build validation | `scripts/ci_validate.sh` works |
| 7 | Documentation | STATUS.md updated |

### 1.2 RED4ext.SDK — Results

| # | Task | Result |
|---|------|--------|
| 1 | Smoke test | `missing=0 dup=0` — all 126 hashes resolve at runtime |
| 2 | RTTI type sizes | `CName=8, TweakDBID=8, CString=32` — all correct |
| 3 | Critical getters | `CRTTISystem_Get` and `TweakDB_Get` resolve to valid addresses |
| 4 | TLS | `TLS::IsInitialized=true`, `TLS::Get` returns valid pointer |
| 5 | Type alignment | No issues found |
| 6 | Examples | All SDK examples build on macOS |
| 7 | Documentation | STATUS.md updated |

---

## Phase 2 — Core Plugins

### 2.1 TweakXL

**Current:** 85% — all 6 required addresses confirmed, 5 stats addresses discovered
**Goal:** 100% — full runtime validation, stats hooks verified, in-game tweak loading confirmed

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | Execute smoke test plan | Follow `docs/MACOS_SMOKE_TEST.md`. Build TweakXL, install `TweakXL.dylib` to plugins dir. Launch game via `launch_red4ext.sh` (human progresses to gameplay). Read `red4ext.log` + `TweakXL.log` — confirm initialization, tweak directory registration, tweak file loading. | 1h |
| 2 | Runtime-verify 5 stats addresses | Add logging to `StatService` that dumps resolved address + first 4 bytes at each stats function address. Rebuild, reinstall, relaunch game (human progresses to gameplay). Read logs — verify ARM64 prologues at each address. | 1h |
| 3 | Fix any stats address failures | If any stats address is wrong: use function clustering (0x3A93xxx–0x3A94xxx range), string refs, or proximity search to find correct offset. Update `AddressResolverOverride.hpp`. Rebuild, reinstall, relaunch, re-check logs. | 2h |
| 4 | Test tweak file loading | Create test `.tweak` YAML files in `r6/tweaks/` (e.g., change a weapon stat). Launch game (human loads save, checks weapon stats in-game, reports result). Read logs for tweak load confirmation. | 1h |
| 5 | Test record creation | Create a new TweakDB record via tweak file. Launch game (human progresses to gameplay). Read logs — verify `TweakDB_CreateRecord` hook fires and record is accessible. | 1h |
| 6 | Test TweakDBID derivation | Verify derived IDs (e.g., `Items.Preset_Katana_Default.damage`) resolve correctly. Check logs after game launch. | 30m |
| 7 | Clean up double-init guard | Investigate why double-init guard exists. If root cause is fixed, remove guard; if still needed, document why. | 30m |
| 8 | Final build + package | Clean build, produce `TweakXL-1.11.3-macos-arm64.zip` with correct directory layout. Update STATUS.md. | 30m |

**Exit criteria:** TweakXL loads, hooks attach, tweak files are read and applied
in-game, stats hooks either work or degrade gracefully with clear logging.

---

### 2.2 ArchiveXL

**Current:** 70% — 113/130 addresses, 17 unresolved, 2 services disabled
**Goal:** 100% — all 130 addresses resolved, all services enabled, runtime-verified

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | Triage the 17 unresolved addresses | Categorize each into: (a) discoverable via vtable, (b) discoverable via string ref, (c) discoverable via caller-chasing, (d) requires manual RE. | 1h |
| 2 | Expand discovery tool — ADRP+LDR support | Current tool only scans `ADRP+ADD`. Add `ADRP+LDR` pattern matching to `macos_discover_archivexl_offsets.py`. Re-run. | 3h |
| 3 | Vtable extraction for ResourceDepot | Parse `__DATA_CONST` segment, extract vtable for `ResourceDepot` class, map virtual methods to hash IDs (`ResourceDepot_InitializeArchives`, `ResourceDepot_LoadArchives`). | 3h |
| 4 | Caller-chasing for assert stubs | For addresses that resolved to `brk`/assert stubs: walk call graph backwards to find the real calling function. Update resolver. | 2h |
| 5 | Resolve remaining addresses manually | For any still unresolved: use Ghidra/IDA, cross-reference with Windows build, pattern match against known struct offsets. | 4h |
| 6 | Validate duplicate offset mappings | Runtime-test the ~4 groups of duplicate offsets. Confirm they are legitimate overloads/wrappers or fix false positives. | 2h |
| 7 | Re-enable ExtensionService | Un-guard `ExtensionService` in `Application.cpp`. Build, install to plugins dir. Launch game via `launch_red4ext.sh` (human progresses to gameplay). Read logs — hooks for `InitResourceDepot`, `LoadGatheredResources`, `LoadTweakDB` must attach without NULL errors. | 2h |
| 8 | Re-enable EntitySpawnerPatch | Verify ARM64 struct layout for entity request structs. Un-guard patch. Rebuild, install, relaunch game. Human confirms entity spawning works (e.g., NPCs, vehicles appear). Read logs for errors. | 2h |
| 9 | Integration test | Install ArchiveXL alongside RED4ext + TweakXL. Install a mod that adds custom archives (e.g., custom appearance mod). Launch game via `launch_red4ext.sh` (human loads save, equips custom item). Human confirms resources load visually. Read logs. | 2h |
| 10 | Final build + documentation | Clean build, update `ArchiveXLAddressResolver.cpp` with all 130 addresses, update STATUS.md. | 1h |

**Exit criteria:** 130/130 addresses resolved, all services enabled, plugin loads
without NULL address errors, archive mods load in-game.

---

### 2.3 ModMenu

**Current:** 25% — native backend works, UI is placeholder, RTTI unverified
**Goal:** 100% — functional in-game mod settings menu

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | Verify RTTI registration on macOS | Add RTTI validation logging to ModMenu plugin. Build, install to plugins dir. Launch game via `launch_red4ext.sh` (human progresses to gameplay). Read logs — confirm `CRTTISystem::Get()` returns valid pointer. | 2h |
| 2 | Fix RTTI registration if broken | If `CRTTISystem` address is wrong or registration fails, debug with SDK resolution. May need address override. Rebuild, reinstall, relaunch, re-check logs. | 2h |
| 3 | Design menu UI layout | Spec out the menu: mod list sidebar, settings panel (toggles, sliders, dropdowns, buttons), header with mod name/version. | 1h |
| 4 | Implement REDscript menu UI | Replace placeholder `streaming_spinner.inkwidget` with real inkWidget hierarchy: `inkCanvas` root, `inkVerticalPanel` for mod list, `inkScrollArea` for settings. Install scripts to `r6/scripts/`. | 6h |
| 5 | Wire native → REDscript bridge | Register native functions (`GetRegisteredMods`, `GetModSettings`, `SetModSetting`, `GetLogTail`) and call them from REDscript UI. | 3h |
| 6 | Implement settings persistence | Extend JSON persistence to handle nested objects, arrays, enum values. Write tests for serialization round-trip. | 2h |
| 7 | Test with external plugins | Create a test plugin that registers settings via `ModMenu_Register` callback. Install both plugins. Launch game via `launch_red4ext.sh` (human presses F10 in-game, reports what they see). Read logs. | 2h |
| 8 | Input system validation | Run `tools/patch_input.sh`. Launch game (human presses F10 in-game, confirms overlay toggles). Read logs for input events. | 1h |
| 9 | Polish and edge cases | Handle: no mods registered (empty state), mod with many settings (scrolling), very long mod names (truncation), settings validation. Relaunch + human visual verification. | 2h |
| 10 | Package release | Build, create `ModMenu-v0.2.0-macos-arm64.zip` with dylib + scripts + input config. Update docs. | 1h |

**Exit criteria:** F10 opens a real settings menu, mods can register settings pages,
settings persist to disk, native↔REDscript bridge is functional.

---

## Phase 3 — Advanced Plugin

### 3.1 MetalFX Denoiser

**Current:** 30% — infrastructure built, blocked on buffer RE
**Goal:** 100% — NRD replaced by MetalFX, measurable FPS improvement

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | Buffer structure reverse engineering | Write a Frida hook script that intercepts NRD functions and logs arguments (pointer, size, first N bytes of struct). Launch game via `launch_red4ext.sh` with RT enabled (human enables RT in graphics settings, enters gameplay). Read Frida logs to map `struct NRDDispatchDesc` fields. | 8h |
| 2 | Identify MTLTexture pointers | Extend Frida hook to dump pointer fields within NRD buffer struct. Launch game with RT enabled (human enters gameplay). Read logs — locate `id<MTLTexture>` objects by checking Objective-C class names at pointer targets. | 4h |
| 3 | Determine motion vector format | Capture motion vector data via Frida hook. Launch game (human moves camera in-game to generate motion). Analyze logged data: NDC vs pixel space, half-res vs full-res, 2-channel vs 3-channel. | 2h |
| 4 | Implement buffer extraction | Fill in `BufferInterceptor::ExtractBuffer()` with real struct offsets. Extract all required textures from game buffer. | 3h |
| 5 | Implement buffer conversion | Complete `BufferConverter.mm` — convert game textures to MTLTexture format expected by MetalFX Temporal Scaler (pixel format, size matching). | 3h |
| 6 | Wire hooks to MetalFX pipeline | In `NRDHooks.cpp`: intercept NRD dispatch, extract buffers, run through MetalFX temporal scaler, write output back to game's output texture. | 4h |
| 7 | Integrate Frida hook installation | Automate hook installation via RED4ext plugin lifecycle (not manual Frida attachment). Use RED4ext hooking API or embed Frida script. | 3h |
| 8 | Configuration system | Implement TOML config: enable/disable per-feature (diffuse GI, specular, shadows), quality presets, debug overlays. | 2h |
| 9 | Performance benchmarking | A/B test: NRD vs MetalFX. Launch game twice — once with plugin disabled, once enabled. Human sets RT medium/ultra at 1080p, 1440p, 4K and reports FPS from in-game overlay. Target: 20–40% improvement. | 2h |
| 10 | Visual quality validation | Launch game with MetalFX active (human enters same scene with and without plugin). Human screenshots for comparison — check ghosting, temporal artifacts, shadow quality, specular accuracy. | 2h |
| 11 | Edge case handling | Handle: RT disabled (no-op), resolution changes mid-session, HDR vs SDR, sleep/wake recovery. Each requires a game launch + human toggling settings. | 2h |
| 12 | Final packaging | Clean build, release zip with both dylibs + config template + README. Update STATUS.md. | 1h |

**Exit criteria:** MetalFX replaces NRD at runtime, visual quality is acceptable,
measurable FPS improvement, no crashes or artifacts.

---

## Phase 4 — CyberMod Studio (Umbrella App)

### 4.1 Complete Phase 1 — Mod Manager Module

**Current:** 70% of Mod Manager module
**Goal:** Fully functional mod manager replacing the Python version

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | Complete ModManager actor | Finish install/uninstall/enable/disable flows. Wire up to ModDatabase for persistence. Test CRUD cycle. | 3h |
| 2 | Complete FOMOD parser integration | End-to-end test: download FOMOD mod → parse `ModuleConfig.xml` → present wizard → install selected files. | 3h |
| 3 | Complete NexusAPIClient | Finish download-to-install flow. Handle: auth (Keychain), rate limiting, download progress, file hash verification. | 3h |
| 4 | Finish ModManagerView | Complete list view (sorting, filtering, bulk operations), detail view (file list, dependencies, conflicts), install sheet, uninstall confirmation. | 4h |
| 5 | Finish NexusBrowserSheet | Search → browse → select files → download → install. Wire up to NexusAPIClient + ModManager. | 3h |
| 6 | Load order management | Implement drag-to-reorder in UI, persist order to database, apply order during game launch. | 2h |
| 7 | Profile system | Create/switch/delete profiles. Each profile stores its own enabled mods + load order. | 2h |
| 8 | Compatibility checking | Port logic from Python mod manager: scan for DLLs, check framework dependencies, warn on incompatible mods. | 2h |
| 9 | Framework management | Detect/install/update RED4ext, TweakXL, ArchiveXL. Show status in sidebar. One-click setup wizard. | 3h |

**Exit criteria:** Can browse Nexus, download, install (including FOMOD), manage
load order, switch profiles, detect/install frameworks — all from SwiftUI.

---

### 4.2 Complete Phase 1 — Game Runner Module

**Current:** 40%
**Goal:** Launch game with full mod stack, monitor process, stream logs

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | GameRunnerView UI | Build: launch button, status indicator (not running / launching / running), uptime, active mods count. | 2h |
| 2 | Launch configuration | UI for: selecting game path, choosing DYLD_INSERT_LIBRARIES list, environment variables, launch arguments. | 2h |
| 3 | Log viewer | Real-time log streaming from `red4ext/logs/red4ext.log` + plugin logs. Filterable by level, searchable. | 3h |
| 4 | Process health monitoring | Monitor game process: CPU/memory usage via `proc_pid_rusage`, crash detection, auto-capture crash logs. | 2h |
| 5 | Session history | Record each launch: timestamp, duration, active mods, crash status. Display in history list. | 1h |

**Exit criteria:** Can launch game from Studio, see real-time logs, detect crashes,
view session history.

---

### 4.3 Phase 2 — CyberModDaemon

**Current:** 5% (stub)
**Goal:** Privileged helper for operations requiring elevation

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | XPC service skeleton | Create launchd plist, XPC interface protocol, basic client/server handshake. | 3h |
| 2 | Privileged file operations | Move files to protected game directories, modify game configs, manage code signatures. | 2h |
| 3 | Dylib injection management | Manage `DYLD_INSERT_LIBRARIES` setup, sign dylibs on behalf of user. | 2h |
| 4 | Security model | Implement authorization rights, user approval prompts, audit logging. | 2h |
| 5 | Integration with Studio | Wire daemon calls into GameLauncher + ModManager. Fall back gracefully if daemon not installed. | 2h |

**Exit criteria:** Daemon installs via helper tool, handles privileged ops,
Studio uses it transparently for file operations and game launching.

---

### 4.4 Phase 2 — Debug Studio

**Current:** 5% (placeholder)
**Goal:** Runtime game inspection from Studio

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | DebugAgent dylib | Build a thin RED4ext plugin that opens a Unix domain socket and accepts commands from Studio. | 4h |
| 2 | IPC protocol implementation | Implement the protocol from `docs/IPC_PROTOCOL.md`: handshake, heartbeat, request/response, streaming events. | 3h |
| 3 | TweakDB browser | Query TweakDB records from running game. Display tree view with search, show flat values, allow live edits. | 4h |
| 4 | Hook monitor | List active hooks (from RED4ext), show status, hit counts, timing. Allow enable/disable. | 3h |
| 5 | Memory inspector | Read game memory at arbitrary addresses. Display hex view + decoded struct overlay for known types. | 3h |
| 6 | Log aggregator | Aggregate logs from RED4ext + all plugins into a single timeline view. Color-coded by source and level. | 2h |
| 7 | Performance overlay | Show frame time, hook overhead, memory usage in real-time charts. | 2h |

**Exit criteria:** Can connect to running game, browse TweakDB, monitor hooks,
inspect memory, view aggregated logs — all live from Studio.

---

### 4.5 Phase 2 — Creation Studio

**Current:** 5% (placeholder)
**Goal:** Create new mods from within Studio

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | Project scaffolding | "New Mod" wizard: choose type (tweak, archive, RED4ext plugin, redscript), generate template project. | 3h |
| 2 | YAML/RED tweak editor | Syntax-highlighted editor for `.tweak` files with schema validation and autocomplete for TweakDB IDs. | 4h |
| 3 | Redscript editor | Syntax highlighting for `.reds` files, basic error detection, class/function browser. | 3h |
| 4 | Build system integration | For C++ plugins: invoke CMake from Studio, show build output, capture errors, build-on-save option. | 3h |
| 5 | Asset browser | Browse game archives: list resources by type, preview textures, view mesh metadata. (Read-only.) | 4h |
| 6 | Packaging | Export mod as distributable archive: select files, set metadata (name, version, description), generate Nexus-compatible structure. | 2h |
| 7 | Schema validation | Validate tweak files against TweakDB schema (type checking, ID existence, value ranges). | 2h |

**Exit criteria:** Can create a new tweak mod from scratch, edit it with validation,
build if needed, package for distribution.

---

### 4.6 Phase 2 — Porting Studio

**Current:** 5% (placeholder)
**Goal:** Assist porting Windows mods to macOS

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | Windows mod analyzer | Given a Windows mod zip: scan for DLLs, identify dependencies (MinHook, Detours, Address Library), list required address hashes, report compatibility. | 3h |
| 2 | Address mapping tool | Show Windows→macOS address mapping. For each hash used by the mod, show: resolved on macOS? offset known? | 2h |
| 3 | Scaffold generator | Generate macOS project from Windows mod: create CMakeLists.txt, stub `AddressResolverOverride.hpp`, replace `#include <windows.h>` with macOS equivalents. | 3h |
| 4 | API migration guide | Built-in reference: Windows API → macOS equivalent. MinHook → RED4ext hooks, Detours → Frida, VirtualAlloc → mmap, etc. | 2h |
| 5 | Guided porting workflow | Step-by-step wizard: analyze → map addresses → scaffold → build → test. Track progress per mod. | 3h |

**Exit criteria:** Can analyze a Windows mod, identify porting requirements,
generate a macOS project scaffold, guide user through address mapping.

---

## Phase 5 — Polish & Release

| # | Task | Detail | Est. |
|---|------|--------|------|
| 1 | End-to-end integration test | Install full stack: RED4ext + TweakXL + ArchiveXL + ModMenu + MetalFX. Launch game via `launch_red4ext.sh` (human progresses to gameplay, presses F10 for ModMenu, equips custom item for ArchiveXL, enables RT for MetalFX). Read all logs. Confirm zero errors. | 4h |
| 2 | Game update resilience | Document and test the full "game updated" workflow: re-run address scripts, rebuild plugins, update Studio framework management. | 2h |
| 3 | Error recovery testing | Test every failure mode: missing addresses, corrupt dylib, Frida not signed, game crash during load, database corruption. Verify graceful recovery. | 3h |
| 4 | Performance audit | Profile Studio memory usage, plugin hook overhead, MetalFX latency. Optimize any hot paths. | 2h |
| 5 | Documentation sweep | Every project: ensure README, STATUS.md, build instructions are current. Remove stale TODOs. | 3h |
| 6 | Release packaging | Create distributable packages for each project. Write install guide. Create a "quick start" that gets a user from zero to modded game. | 3h |
| 7 | CyberMod Studio v1.0 release | Final UI polish, app icon, About screen, first-run onboarding, DMG packaging with notarization. | 4h |

---

## Time Estimates Summary

| Phase | Description | Est. Hours |
|-------|-------------|-----------|
| 1.1 | RED4ext hardening | 8.5h |
| 1.2 | RED4ext.SDK verification | 8.5h |
| 2.1 | TweakXL completion | 7.5h |
| 2.2 | ArchiveXL completion | 22h |
| 2.3 | ModMenu completion | 22h |
| 3.1 | MetalFX Denoiser completion | 36h |
| 4.1 | Studio — Mod Manager | 25h |
| 4.2 | Studio — Game Runner | 10h |
| 4.3 | Studio — Daemon | 11h |
| 4.4 | Studio — Debug Studio | 21h |
| 4.5 | Studio — Creation Studio | 21h |
| 4.6 | Studio — Porting Studio | 13h |
| 5 | Polish & Release | 21h |
| | **Total** | **~227h** |

## Critical Path

```
RED4ext ──► RED4ext.SDK ──► TweakXL ──► ArchiveXL ──► ModMenu
                                                         │
                                                         ▼
                                              MetalFX Denoiser
                                                         │
                                                         ▼
                                              CyberMod Studio
                                              (Phase 1 → Phase 2)
                                                         │
                                                         ▼
                                              Integration & Release
```

The fastest path to a working mod stack is: **Phase 1 → Phase 2 → Phase 3**.
CyberMod Studio (Phase 4) can proceed once the plugin stack is proven.
Phase 5 is the final convergence.

## Principles

1. **Verify before extending.** Runtime-verify addresses before building features on top of them.
2. **Fail loudly.** Every hook must use `.OrThrow()` or equivalent. Silent failures are the enemy.
3. **Test incrementally.** After each sub-task, build and verify. Don't accumulate untested changes.
4. **Document as you go.** Update STATUS.md after completing each phase. Future-you will thank present-you.
5. **One project at a time.** Finish a project before moving to the next. Context-switching is expensive.
6. **Launch the game yourself.** The agent must launch the game via `launch_red4ext.sh` in the game directory. Never ask the human to launch — just do it. The human will always navigate past the main menu into gameplay.
7. **CLI, not GUI.** The agent works in a terminal. It builds, installs, launches, and reads logs. All visual/in-game verification is done by the human — ask them what they see, don't guess.
8. **Logs are ground truth.** After every game launch, read `red4ext/logs/red4ext.log` and any plugin-specific logs. This is how the agent knows what happened at runtime.
