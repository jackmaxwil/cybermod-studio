# CyberMod Studio

Mods for **Cyberpunk 2077 on Mac** (Steam, Apple silicon). `cybermod` installs the mod loader
([RED4ext for macOS](https://github.com/jackmaxwil/RED4ext-macos), with TweakXL, ArchiveXL and ModMenu), puts mods where
the game finds them, and starts the game with mods.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jackmaxwil/cybermod-studio/main/install.sh | bash
```

## Use

```bash
cybermod install                                  # install the mod loader into your game (once)
cybermod mod add github:owner/repo                # a mod from GitHub (newest release)
cybermod mod add ~/Downloads/SomeMod.zip          # a mod you downloaded (.zip, .7z, .rar or a folder)
cybermod mod add https://www.nexusmods.com/cyberpunk2077/mods/1234   # a mod from Nexus Mods (see below)
cybermod mod list                                 # what is installed
cybermod mod disable some-mod                     # switch a mod off (and back on with: mod enable)
cybermod mod remove some-mod                      # delete exactly the files that mod installed
cybermod doctor                                   # check that everything is set up (changes nothing)
cybermod play                                     # start the game with mods (start Steam first)
```

Steam's Play button still starts the game **without** mods.

**Nexus Mods:** copy your personal API key from
[nexusmods.com/users/myaccount?tab=api](https://www.nexusmods.com/users/myaccount?tab=api) and run
`cybermod config set nexus.api-key` once (it is kept in your Keychain). Premium members get direct downloads. Everyone
else: `cybermod mod add nexus:1234` opens the mod's download page; click **Mod Manager Download**, copy the `nxm://`
link the browser offers, and run `cybermod mod add 'nxm://...'`.

**Mods you installed by hand:** `cybermod mod adopt` tracks them so `disable` and `remove` work too.

**Your game is not in the default Steam folder?** `cybermod config set game-dir "/path/to/Cyberpunk 2077"`.

**After a game update** `cybermod doctor` tells you whether to wait for a new loader release (`cybermod update`) or
to re-run the setup (`cybermod doctor --fix rerun-setup`).

Every command explains what to do next when something is wrong. `cybermod help <command>` shows all options;
[docs/CLI.md](docs/CLI.md) has the details (where files go, updates, load order, JSON output).

## Build from source

```bash
swift build -c release && .build/release/cybermod --help     # the command-line tool
swift test                                                   # unit tests (never touch your game folder)
xcodebuild -project CyberModStudio.xcodeproj -scheme CyberModStudio -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build # the CyberMod Studio app
```

Layout: `Sources/CyberModKit` (all logic), `Sources/CyberModCLI` (`cybermod`), `CyberModStudio/` (the app, still on the
older `Sources/CyberModCore`), `docs/`. Releases: push a `vX.Y.Z` tag (see `.github/workflows/release.yml`).
