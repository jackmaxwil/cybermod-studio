# Phase 1 Agent Prompt — Foundation Hardening

> Copy everything below the line into a new agent session.

---

## MISSION

You are executing **Phase 1 — Foundation Hardening** of the Cyberpunk 2077 macOS modding ecosystem. Your job is to complete ALL tasks for both RED4ext (1.1) and RED4ext.SDK (1.2), then verify the foundation is production-stable.

Work sequentially through each task. Do not skip tasks. After each task, verify your work before moving on. Update STATUS.md files as you go.

---

## ENVIRONMENT

- **OS:** macOS ARM64 (Apple Silicon)
- **Shell:** zsh
- **Human present:** YES — a human operator is always at the keyboard. After you launch the game, they will navigate from main menu into gameplay. You never need to ask them to launch — just launch it yourself. Ask them for visual confirmations when needed (e.g., "what do you see in-game?").
- **You are CLI-only.** You build, install, launch, and read logs. You cannot interact with GUI.

## KEY PATHS

```
RED4EXT_ROOT="/Users/jackmazac/Development/RED4ext"
SDK_ROOT="/Users/jackmazac/Development/RED4ext.SDK"
GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
GAME_BINARY="$GAME_DIR/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077"
RED4EXT_LOG="$GAME_DIR/red4ext/logs/red4ext.log"
SMOKE_TEST_LOG="/tmp/RED4ext.SDK_smoke_test.log"
PLUGINS_DIR="$GAME_DIR/red4ext/plugins"
ADDRESS_DB="$GAME_DIR/red4ext/bin/x64/cyberpunk2077_addresses.json"
```

## HOW TO LAUNCH THE GAME

Always use the installed launcher:

```bash
cd "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
./launch_red4ext.sh
```

This script:
1. Sets `DYLD_INSERT_LIBRARIES` to inject `RED4ext.dylib` + `FridaGadget.dylib`
2. Compiles REDscript if compiler exists
3. Launches the game binary

Background the launch command (`block_until_ms: 0`) since the game runs indefinitely. After launching, wait ~15 seconds, then read logs.

## HOW TO READ LOGS AFTER LAUNCH

```bash
# RED4ext loader log
cat "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/red4ext/logs/red4ext.log"

# SDK smoke test log
cat /tmp/RED4ext.SDK_smoke_test.log

# Plugin-specific logs
cat "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/red4ext/plugins/TweakXL/TweakXL.log" 2>/dev/null
```

## HOW TO KILL THE GAME

```bash
pkill -f Cyberpunk2077 || true
```

Always kill the game before relaunching.

---

## PROJECT CONTEXT

### RED4ext (at /Users/jackmazac/Development/RED4ext)

Script extender / mod loader for Cyberpunk 2077, ported from Windows to macOS ARM64.

**Current state:**
- 126/126 SDK addresses in `scripts/cyberpunk2077_addresses.json`
- 9/9 hooks working via Frida Gadget
- Plugin loading works (`.dylib` from `red4ext/plugins/<Name>/`)
- Builds via CMake (C++20, `build/` or `build-macos/` directory exists)
- Uses Frida Gadget + fishhook for hooking (no Detours)

**Build command:**
```bash
cd /Users/jackmazac/Development/RED4ext
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(sysctl -n hw.ncpu)
# Output: build/libs/RED4ext.dylib
```

**Install command:**
```bash
cd /Users/jackmazac/Development/RED4ext
./scripts/macos_install.sh --build
```

**Key source files:**
- `src/dll/Main.cpp` — Entry point (`__attribute__((constructor))` on macOS)
- `src/dll/Platform/Hooking.cpp` — Hook backends (FridaGadget, NativeInline, FridaGum)
- `src/dll/Platform/MacOS.cpp` — macOS platform abstraction
- `src/dll/Systems/PluginSystem.cpp` — Plugin discovery and loading
- `src/dll/Platform/RuntimeValidation.cpp` — Runtime address validation
- `scripts/cyberpunk2077_addresses.json` — Address database (126 entries)
- `scripts/generate_addresses.py` — Address regeneration after game updates

**Address database format:**
```json
{
  "version": "1.0",
  "game_version": "2.3.1",
  "stats": { "total": 126, "resolved": 126, "unresolved": 0 },
  "Addresses": [
    { "hash": "1518151849", "offset": "1:0x6E50000" }
  ]
}
```
Where `1:0xOFFSET` means segment 1 (__TEXT) + hex offset.

**Test infrastructure:**
- `tests/` directory with unit, integration, and performance tests
- Build with: `cmake .. -DRED4EXT_ENABLE_TESTS=ON`

### RED4ext.SDK (at /Users/jackmazac/Development/RED4ext.SDK)

Header-only SDK for building Cyberpunk 2077 plugins.

**Current state:**
- 126/126 addresses in `cyberpunk2077_addresses.json`
- 134 loader addresses in `cyberpunk2077_addresses.loader.json`
- Platform compat layer (`WinCompat.hpp`) maps Windows types to macOS
- Validation scripts exist and pass
- Smoke test plugin exists at `examples/macos_smoke_test/Main.cpp`

**Validation commands:**
```bash
cd /Users/jackmazac/Development/RED4ext.SDK
python3 scripts/check_addresses.py --strict
python3 scripts/check_loader_addresses.py --strict
```

**Build smoke test:**
```bash
cd /Users/jackmazac/Development/RED4ext.SDK
mkdir -p build && cd build
cmake .. -DRED4EXT_BUILD_EXAMPLES=ON
cmake --build . --target macos_smoke_test
# Output: build/examples/libmacos_smoke_test.dylib (or similar)
```

**Install smoke test:**
```bash
GAME_DIR="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
mkdir -p "$GAME_DIR/red4ext/plugins/smoke_test"
cp build/examples/libmacos_smoke_test.dylib "$GAME_DIR/red4ext/plugins/smoke_test/"
```

**Smoke test log location:** `/tmp/RED4ext.SDK_smoke_test.log`

**Key SDK files:**
- `include/RED4ext/Detail/AddressHashes.hpp` — 126 hash constants (see full list below)
- `include/RED4ext/Relocation-inl.hpp` — Address resolution (JSON parsing, segment resolution)
- `include/RED4ext/Detail/WinCompat.hpp` — Windows API compatibility layer
- `include/RED4ext/Common.hpp` — Platform macros, export macros
- `include/RED4ext/TLS-inl.hpp` — Thread-local storage (pthread on macOS)
- `cyberpunk2077_addresses.json` — SDK address database

**Address hashes (all 126, from AddressHashes.hpp):**
```
CBaseFunction: Handlers(0x5A7D28A9), ExecuteScripted(0xE1F920D6), ExecuteNative(0xE1321AEB), InternalExecute(0x1817231D)
CBaseRTTIType: sub_80(0xE46F169E), sub_88(0x15BE1744), sub_90(0xA45935A1), sub_98(0xAEA91F1D), sub_A0(0x8ED61BC2)
CBitfield: Unserialize(0xA6981914), ToString(0x54231404), FromString(0xA09B15A8)
CClass: 15 hashes (Unserialize, ToString, sub_80..sub_D0, CreateInstance, GetProperty, GetProperties, ClearScriptedData, InitializeProperties, AssignDefaultValuesToProperties)
CClassFunction: ctor(0x602D29F3)
CClassStaticFunction: ctor(2920426135)
CEnum: Unserialize(0x40D317A6), ToString(0x41A1296), FromString(0x21CA1EC1)
CGameEngine: (0x97F209D6)
CGlobalFunction: ctor(0xFA6B24D0)
CNamePool: AddCstr(0xA00C9B), AddCString(0xFFD61709), AddPair(0xD9840BD8), Get(0x68DF07DC)
CommandListContext: 5 hashes
CRTTIRegistrator: RTTIAsyncId(0xDDBD19E8)
CRTTIScriptReferenceType: ctor(0xCB8A115C), Set(0x22EE172F)
CRTTISystem: Get(0x4A610F64)
CStack: vtbl(0x349A0EE1)
CString: 4 hashes
DeviceData: g_DeviceData(1239944840)
DynArray: Realloc(0x7AA013D2)
D3D12MA: Allocator_CreateResource(2508272872)
Handle: ctor(0xBA0C115D), DecWeakRef(0x333B1404)
IRenderProxy: 12 hashes
IScriptable: sub_D8(0xF8E41DDF), DestructValueHolder(0x3521331)
ISerializable: 6 hashes
JobDispatcher: 2 hashes, JobHandle: 2 hashes, JobInternalHandle: 1 hash, JobQueue: 5 hashes
Memory: 8 hashes
OpcodeHandlers: (0x39532858)
ObjectPackageExtractor: 3 hashes, ObjectPackageReader: 3 hashes, BasePackageReader: 1 hash
ResourceDepot: (0x659A0FC7)
ResourceLoader: 4 hashes, ResourceReference: 3 hashes, ResourceToken: 5 hashes
TTypedClass: IsEqual(0x58630EE8)
TweakDB: Get(0x36800DE4), CreateRecord(0x3201127A)
UpdateRegistrar: 2 hashes
DeferredDataBuffer: 2 hashes
LaunchParameters: (677908004)
```

**Known address quirks:**
- `CBaseRTTIType_sub_98` and `CBaseRTTIType_sub_A0` intentionally share the same offset (`0x3228`) — they're stub functions
- Two entries have `offset: "1:0x0"` (hashes 2930319133 and 2396396482) — these are `D3D12MA::Allocator_CreateResource` and `g_DeviceData`, which are GPU-specific and expected to be zero on macOS

**Layout assertion system:**
- `RED4EXT_ASSERT_SIZE` is disabled on macOS by default
- Enable with `#define RED4EXT_ENABLE_MACOS_LAYOUT_ASSERTS` before including SDK headers
- `RED4EXT_ASSERT_OFFSET` is also disabled for Clang

**Smoke test plugin behavior (examples/macos_smoke_test/Main.cpp):**
- Logs to `/tmp/RED4ext.SDK_smoke_test.log`
- Tests TLS initialization (`RED4ext::TLS::Get()`)
- Finds `cyberpunk2077_addresses.json` via standard search paths
- Loads all hashes, resolves each, counts missing and duplicates
- Expected success output: `missing=0 dup=0`

---

## TASK LIST

### Phase 1.1 — RED4ext Hardening

#### Task 1: Runtime-verify all 126 addresses

Build a validation plugin that:
1. Iterates all 126 hashes from `AddressHashes.hpp`
2. Calls `UniversalRelocBase::Resolve(hash)` for each
3. For non-zero results, reads the first 4 bytes at the resolved address
4. Checks if bytes match valid ARM64 function prologues:
   - `STP X29, X30, [SP, #-N]!` → first 4 bytes: `0xFD` in byte 1, `0x7B` pattern
   - `SUB SP, SP, #N` → opcode `0xD1` prefix
   - `STP` variants with different register pairs
   - **Simplest check:** read uint32 at address, mask for known ARM64 instruction patterns
5. Logs PASS/FAIL per hash with the hash name, resolved address, and first instruction bytes

Create this as a RED4ext plugin at `/Users/jackmazac/Development/RED4ext/tests/validation_plugin/`. It should:
- Export `Main`, `Query`, `Supports` functions (standard RED4ext plugin interface)
- Log to its own file: `$GAME_DIR/red4ext/plugins/address_validator/validation_results.log`
- Use `spdlog` or simple `std::ofstream` logging

After building:
1. Install to `$GAME_DIR/red4ext/plugins/address_validator/`
2. Launch game via `launch_red4ext.sh`
3. Wait ~15 seconds, then read the validation log
4. Report results

**Important ARM64 prologue patterns (little-endian uint32):**
```
STP X29, X30, [SP, #-16]!  → 0xA9BF7BFD
STP X29, X30, [SP, #-32]!  → 0xA9BE7BFD  
STP X29, X30, [SP, #-48]!  → 0xA9BD7BFD
STP X29, X30, [SP, #-N]!   → 0xA9??7BFD (mask: 0xFF80FFFF == 0xA9007BFD)
SUB SP, SP, #N              → 0xD100??FF (mask: 0xFF0003FF == 0xD10003FF)
STP X28, X27, [SP, #-N]!   → 0xA9??6FFC  
PACIBSP                     → 0xD503237F (pointer auth)
```

A reasonable validation approach: check if the first instruction is `STP` (most common function prologue) or `PACIBSP` (pointer authentication). Data addresses (vtables, singletons) won't have prologues — log them as "DATA" rather than "FAIL".

Data-type hashes (expect pointers, not prologues):
- `CGameEngine` (singleton pointer)
- `CStack_vtbl` (vtable)
- `DeviceData::g_DeviceData` (data pointer)
- `OpcodeHandlers` (handler table)
- `ResourceDepot` (singleton pointer)
- `ResourceLoader` (singleton pointer)
- `JobDispatcher` (singleton pointer)
- `Memory_Vault` (pointer)
- `CRTTIRegistrator_RTTIAsyncId` (data)
- `CBaseRTTIType_sub_98` / `CBaseRTTIType_sub_A0` (known stubs at 0x3228)
- `D3D12MA::Allocator_CreateResource` (zero on macOS — skip)
- `g_DeviceData` (zero on macOS — skip)
- `LaunchParameters` (data pointer)

#### Task 2: Fix any bad addresses

If Task 1 reveals addresses that fail validation:
1. Note which hashes fail
2. Use `scripts/generate_addresses.py` against the game binary to attempt re-discovery
3. Cross-reference with string searches: `strings "$GAME_BINARY" | grep "relevant_string"`
4. Update `scripts/cyberpunk2077_addresses.json` with corrected offsets
5. Reinstall via `scripts/macos_install.sh`
6. Relaunch and re-validate

If all 126 pass (or the only "failures" are expected data/singleton pointers), proceed.

#### Task 3: Stress-test hook stack

1. Ensure TweakXL is installed at `$GAME_DIR/red4ext/plugins/TweakXL/`
   - Build from `/Users/jackmazac/Development/cp2077-tweak-xl` if needed
2. Ensure ModMenu is installed at `$GAME_DIR/red4ext/plugins/ModMenu/`
   - Build from `/Users/jackmazac/Development/cp2077-modmenu` if needed
3. Keep the validation plugin from Task 1 installed
4. Launch game via `launch_red4ext.sh`
5. Read `red4ext.log` — confirm all 3 plugins loaded
6. Check for any hook collision errors, double-free warnings, or trampoline corruption
7. Ask the human: "Did the game reach the main menu without crashing?"

#### Task 4: Harden plugin load error paths

1. Create a deliberately broken plugin:
   - A dylib that exports `Query` and `Supports` but crashes in `Main` (e.g., dereference nullptr)
   - OR a file that isn't a valid Mach-O (just write garbage bytes to a `.dylib`)
2. Install it alongside working plugins
3. Launch game
4. Read `red4ext.log` — confirm:
   - Error is logged for the broken plugin (with plugin name)
   - Other plugins still loaded successfully
   - Game didn't crash
5. Remove the broken plugin after testing

#### Task 5: Code-sign automation

Create a script at `/Users/jackmazac/Development/RED4ext/scripts/sign_all.sh` that:
1. Finds all `.dylib` files in the game's `red4ext/` directory tree
2. Signs each with `codesign -s - --force` (ad-hoc signing)
3. Verifies each with `codesign -v`
4. Reports success/failure per file

#### Task 6: CI build validation

Create a script at `/Users/jackmazac/Development/RED4ext/scripts/ci_validate.sh` that:
1. Builds RED4ext from clean (`rm -rf build && mkdir build && cd build && cmake .. && make`)
2. Runs `check_addresses.py --strict` (from SDK repo)
3. Runs unit tests if available (`RED4EXT_ENABLE_TESTS=ON`)
4. Exits non-zero on any failure
5. Reports a summary

#### Task 7: Update documentation

1. Read `docs/MACOS_PORT.md` and `docs/STATUS.md`
2. Remove any stale TODOs that are now complete
3. Update STATUS.md to reflect Phase 1.1 completion
4. Ensure all file paths and commands are accurate

---

### Phase 1.2 — RED4ext.SDK Verification

#### Task 1: Build + run smoke test plugin

1. Run validation scripts:
   ```bash
   cd /Users/jackmazac/Development/RED4ext.SDK
   python3 scripts/check_addresses.py --strict
   python3 scripts/check_loader_addresses.py --strict
   ```
2. Build the smoke test:
   ```bash
   mkdir -p build && cd build
   cmake .. -DRED4EXT_BUILD_EXAMPLES=ON
   cmake --build . --target macos_smoke_test
   ```
3. Find the output dylib (likely `build/examples/libmacos_smoke_test.dylib` or similar)
4. Install to game:
   ```bash
   mkdir -p "$GAME_DIR/red4ext/plugins/smoke_test"
   cp <output_dylib> "$GAME_DIR/red4ext/plugins/smoke_test/"
   ```
5. Clear old log: `rm -f /tmp/RED4ext.SDK_smoke_test.log`
6. Launch game via `launch_red4ext.sh`
7. Wait ~15 seconds, read `/tmp/RED4ext.SDK_smoke_test.log`
8. Expected: `Loaded 126 hashes`, `missing=0`, `dup=0`

#### Task 2: Verify RTTI type sizes

Add type size logging to the smoke test plugin (`examples/macos_smoke_test/Main.cpp`). After the existing resolution test, add:

```cpp
// Type size verification
log << "[RED4ext.SDK smoke] sizeof(RED4ext::CName)=" << sizeof(RED4ext::CName) << " expected=8\n";
log << "[RED4ext.SDK smoke] sizeof(RED4ext::TweakDBID)=" << sizeof(RED4ext::TweakDBID) << " expected=8\n";
log << "[RED4ext.SDK smoke] sizeof(RED4ext::CString)=" << sizeof(RED4ext::CString) << " expected=32\n";
// Add more types as headers allow
```

Include relevant headers (`CName.hpp`, `TweakDB.hpp`, `CString.hpp`). Rebuild, reinstall, relaunch, check log.

Expected sizes (from Windows SDK — may differ on macOS):
- `CName`: 8 bytes
- `TweakDBID`: 8 bytes
- `CString`: 32 bytes

If sizes differ, log them — we'll fix in Task 5.

#### Task 3: Verify vtable layout

This is harder without a running game engine providing real objects. For now:
1. Add a test that resolves `CRTTISystem_Get` (hash `0x4A610F64`) and logs the resolved address
2. Add a test that resolves `TweakDB_Get` (hash `0x36800DE4`) and logs the resolved address
3. Verify both resolve to non-zero
4. These are the most critical singleton getters — if they resolve correctly, the vtable layout is likely correct

Log the results. If both resolve to non-zero addresses that point to valid ARM64 instructions, mark as passed.

#### Task 4: Test TLS initialization

The smoke test already tests TLS:
```cpp
auto* tls = RED4ext::TLS::Get();
```

Check the existing smoke test log output for:
- `TLS::IsInitialized=true` or `false`
- `TLS::Get=0x...` (non-null means TLS works)

If TLS is not initialized (returns null), that's expected — TLS requires game hooks to set up the TLS pointer. Log the result and note it.

#### Task 5: Fix any type/alignment issues

If Task 2 revealed size mismatches:
1. Enable layout asserts: add `#define RED4EXT_ENABLE_MACOS_LAYOUT_ASSERTS` before includes
2. Identify which structs are wrong
3. Add platform-specific padding where needed
4. Rebuild and verify

If all sizes match, skip this task.

#### Task 6: Mark all examples as tested

1. List all examples in `/Users/jackmazac/Development/RED4ext.SDK/examples/`
2. Try to build each one (they may fail due to missing game headers — that's OK for examples that need runtime game objects)
3. For each that builds: mark as "Builds on macOS"
4. For `macos_smoke_test` and `macos_segment_resolution`: mark as "Tested on macOS"
5. Update any README or status file in the examples directory

#### Task 7: Finalize documentation

1. Update `MACOS_CHANGES.md` if any new changes were made
2. Update `docs/STATUS.md` — mark SDK as stable, update date
3. Ensure `docs/ADDRESS_VALIDATION.md` instructions are accurate
4. Ensure `docs/INTEGRATION_CHECKLIST.md` is up to date

---

## EXIT CRITERIA

Phase 1 is complete when ALL of the following are true:

- [ ] All 126 SDK addresses validated (runtime prologue check or identified as data pointers)
- [ ] Any bad addresses fixed and re-validated
- [ ] 3+ plugins load simultaneously without crashes
- [ ] Broken plugin doesn't crash the loader
- [ ] Code-signing script works
- [ ] CI validation script works
- [ ] `check_addresses.py --strict` passes with `zero_offsets=0` (excluding expected GPU zeros)
- [ ] Smoke test reports `missing=0 dup=0`
- [ ] Type sizes logged (and fixed if wrong)
- [ ] TLS status logged
- [ ] All buildable examples build
- [ ] STATUS.md files updated in both repos

## PRINCIPLES

1. **Launch the game yourself.** Use `launch_red4ext.sh`. Never ask the human to launch.
2. **Logs are ground truth.** After every launch, read the relevant log files.
3. **Kill before relaunch.** Always `pkill -f Cyberpunk2077` before relaunching.
4. **Build incrementally.** Don't rebuild from scratch unless something changed fundamentally.
5. **Fail loudly.** If something doesn't work, log it clearly and fix it — don't skip.
6. **Test one thing at a time.** Don't change 5 things between launches.
7. **Document as you go.** Update STATUS.md after completing each major section.
