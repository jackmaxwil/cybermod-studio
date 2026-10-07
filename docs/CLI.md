# cybermod reference

All logic is in the `CyberModKit` library (`Sources/CyberModKit`); `cybermod` only parses arguments and prints. The
app uses the same library and the same Codable types that `--json` prints.

## Global options

| Option | Meaning |
|---|---|
| `--game-dir <path>` | Cyberpunk 2077 folder. Default: `$CP2077_GAME_DIR`, else `cybermod config set game-dir`, else `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077` |
| `--json` | Machine-readable output on stdout. Errors are `{"error", "hint", "details"}` with exit status 1 |
| `--yes` | Answer yes to confirmations (`uninstall`) |
| `--dry-run` | Show what would change; change nothing |

Every error prints `Error: <what happened>` and `Next: <what to do>`. Commands that change files refuse while the game
is running.

## Commands

| Command | What it does |
|---|---|
| `install [--version X] [--zip file]` | Picks the newest `vX.Y.Z[-rcN]` release of [RED4ext-macos](https://github.com/jackmaxwil/RED4ext-macos) (release candidates count until a 1.0 exists), downloads `RED4ext-macOS-arm64-<version>.zip` and `SHA256SUMS`, verifies, checks the bundle was made for your game build (Mach-O UUID vs the address database), copies it into the game folder (all files or none) and runs `red4ext/macos/scripts/install_macos.sh` (backup to `Cyberpunk2077.orig`, re-sign). `--zip` installs a zip you downloaded yourself (not verified) |
| `update` | `install`, only if a newer release exists |
| `uninstall` | Removes the files the bundle installed (recorded at install; known bundle paths for installs made by hand), never files of your mods, and moves `Cyberpunk2077.orig` back over the game binary when it is the same game build |
| `doctor [--fix <id>]` | Read-only check: game found, Steam running, RED4ext version, game build vs address database, binary re-signed, plugins, ArchiveXL present for archives, `.archive` in subfolders of `archive/pc/mod`, `.xl` outside it, archives with identical file tables or names, Windows-only mods, archive conflicts (who wins), tracked mods with missing files, files installed by hand. Exit status 1 when something is broken. Findings have stable ids and, where possible, a fix id: `install-loader`, `rerun-setup`, `move-nested-archives`, `move-misplaced-xl`, `remove-duplicate-archives` (moves extra copies to `<state>/removed/`), `adopt` |
| `play [-- args]` | Runs `<game>/launch_red4ext.sh` (which checks the build and signature, compiles scripts, merges key bindings and starts the game). Output also goes to `~/Library/Logs/CyberModStudio/game.log`; a failed exit prints a report (new crash reports, plugins whose scripts were skipped, log tails) |
| `mod add <source> [--name N] [--force]` | Installs a mod (see sources and placement below). Re-adding a mod with the same id updates it: files the new version no longer has are removed. Refuses Windows-only mods, FOMOD installers, and files that belong to another mod or that cybermod did not install (`--force` overwrites them; the overwritten files then belong to the new mod) |
| `mod list` / `mod info <id>` | Installed mods, their files and warnings |
| `mod remove <id>` | Deletes exactly the files the mod installed |
| `mod disable <id>` / `mod enable <id>` | Moves the mod's files to `<state>/disabled/<id>/` and back |
| `mod adopt` | Tracks mod files you installed by hand (archive with its `.archive.xl`, one folder under `r6/scripts` or `r6/tweaks`, otherwise one file) without moving them |
| `mod outdated` / `mod update <id>\|--all` | Compares mods from GitHub, Nexus Mods and the registry with their source; updates them |
| `mod order [<archive> --before <other>]` | Lists archives in the order ArchiveXL loads them, or makes one load first by renaming it with a `!` prefix (recorded in the manifest; updating the mod restores the name) |
| `search <words>` | Searches the mod registry ([REGISTRY.md](REGISTRY.md)) |
| `config get\|set\|list` | `game-dir`, `registry.url`, `nexus.api-key` (Keychain; `config set nexus.api-key` without a value asks for it without echo; never printed) |

## Sources (`mod add`)

| Source | Example |
|---|---|
| Folder, `.zip`, `.7z`, `.rar`, or a single mod file | `~/Downloads/Mod-1234-1-0-1700000000.zip` (`.7z`/`.rar` need `7zz`/`7z`, `unar` or `unrar`, else macOS `tar` is tried; `brew install sevenzip` if none works) |
| `https://` link to a file | `https://example.com/mod.zip` |
| GitHub | `github:owner/repo` (newest release), `github:owner/repo@v1.2`, or the repository URL. Picks the release asset that looks like a mod (`.zip`/`.7z`/`.rar`/`.archive`/`.reds`, macOS build first, never "windows"/"source"); otherwise the source zip. `GITHUB_TOKEN` is used if set |
| Nexus Mods | `nexus:<mod id>[/<file id>]` or the mod page URL. Needs your API key (`NEXUS_API_KEY` or `config set nexus.api-key`). Premium: the primary main file is downloaded via `/v1/games/cyberpunk2077/mods/{id}/files/{file}/download_link.json`. Not Premium: the files page opens in your browser; click **Mod Manager Download**, then pass the `nxm://cyberpunk2077/mods/<id>/files/<file>?key=...&expires=...` link to `cybermod mod add` (in quotes, before it expires) |
| Registry | `registry:<id>`; installs registry mods it `requires` first |

## Where files go

| Mod contains | Installed to |
|---|---|
| `archive/pc/mod/**/X.archive`, `X.archive.xl`, `X.xl`, or loose ones | `archive/pc/mod/X...` (flat: ArchiveXL loads only files directly there, in case-insensitive name order; the first archive wins a conflict) |
| `r6/scripts/...`, `r6/tweaks/...`, `r6/input/...`, `red4ext/plugins/...` | the same path (any wrapper folder before it is dropped) |
| loose `.yaml`/`.yml`/`.tweak` | `r6/tweaks/` |
| loose `.reds` | `r6/scripts/<mod name>/` |
| loose macOS `.dylib` | `red4ext/plugins/<Name>/` |
| loose `.xml` | `r6/input/` |
| `.dll`, `.asi`, `.exe`, Cyber Engine Tweaks (Lua), anything under `bin/x64/` | refused: Windows-only |
| readmes, images, `r6/config`, `engine/`, ... | skipped |

## State

`~/Library/Application Support/CyberModStudio/` (or `$CYBERMOD_HOME`): `config.json`, and per game folder
`games/<hash>/mods/<id>.json` (one manifest per mod: source, version, every file with its SHA-256),
`games/<hash>/disabled/<id>/`, `games/<hash>/red4ext.json` (loader bundle files), `games/<hash>/removed/`.

## Library notes (for the app)

- `Kit` carries the game folder, state folder, `dryRun`, `log` (progress lines), `openURL`, `session` (URLSession; tests
  use a URLProtocol stub) and `isGameRunning`. Long calls are `async`; cancelling the task before files are moved
  leaves nothing behind (downloads and unpacking happen in a temp folder, copies land next to their destination and are
  renamed into place).
- `PlaySession.start(kit:)` returns `events: AsyncStream<PlayEvent>` (`output`, `compileFailed`, `gameStarted(pid)`,
  `exited(code, report)`) and `stop()`. Tests use a stub `launch_red4ext.sh` in a temporary game folder.
- `Doctor.run` returns findings with stable `id` and optional `fix`; `Doctor.fix(id, kit:)` applies it.
- `ModStore.adopt()`, `Updates.check(kit:)`, `ModStore.update(id)`, `LoadOrder.list/prioritize`.
- `Config.set(key, value)` validates and saves a setting (the CLI's `config set` and the app's Settings).
- The app reaches all of this through `CyberModModel.AppModel` (see [ARCHITECTURE.md](ARCHITECTURE.md)).
