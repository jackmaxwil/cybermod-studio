# CyberMod Studio

Mods for **Cyberpunk 2077 on Mac** (Steam, Apple silicon). CyberMod Studio installs the mod loader
([RED4ext for macOS](https://github.com/jackmaxwil/RED4ext-macos), with TweakXL, ArchiveXL and ModMenu), puts mods where
the game finds them, and starts the game with mods. It comes as an app and as the `cybermod` command-line tool; both do
the same things and share their settings.

## Install

The app (into `/Applications`):

```bash
curl -fsSL https://raw.githubusercontent.com/jackmaxwil/cybermod-studio/main/install.sh | bash -s -- --app
```

The command-line tool (into `~/.local/bin`):

```bash
curl -fsSL https://raw.githubusercontent.com/jackmaxwil/cybermod-studio/main/install.sh | bash
```

## First steps (app)

1. Start Steam and sign in, then open **CyberMod Studio**. The **Play** screen lists what is left to set up.
2. **Install the mod loader** (one click; downloaded from GitHub and checked against its checksums).
3. Mods you installed by hand? **Track Them**, so you can switch them off and remove them here. Nothing is moved.
4. **Add a mod:** drop its `.zip`, `.7z`, `.rar`, folder or file anywhere in the window, or press ⇧⌘O and paste a Nexus
   Mods page, a GitHub repository or any download link.
5. Press **Play** (⌘R). Steam's own Play button still starts the game *without* mods.

**Nexus Mods:** paste your personal API key from
[nexusmods.com/users/myaccount?tab=api](https://www.nexusmods.com/users/myaccount?tab=api) in Settings (⌘,) > Nexus Mods.
Premium members get direct downloads. Everyone else: click **Mod Manager Download** on the mod's page; the app opens
the `nxm://` link and installs the mod (Settings > Nexus Mods makes CyberMod Studio the handler if another manager is).

**Something wrong?** The **Health** screen checks the game, the loader and your mods and has a Fix button for most
problems. Every error says what to do next. **Load Order** shows which `.archive` wins when two change the same file and
lets you pick the winner.

## First steps (command line)

```bash
cybermod install                                  # install the mod loader into your game (once)
cybermod mod add ~/Downloads/SomeMod.zip          # a mod you downloaded (.zip, .7z, .rar, a folder or a file)
cybermod mod add https://www.nexusmods.com/cyberpunk2077/mods/1234   # Nexus Mods (needs: cybermod config set nexus.api-key)
cybermod mod add github:owner/repo                # newest GitHub release
cybermod mod adopt                                # track mods you installed by hand
cybermod mod list                                 # what is installed; mod disable/enable/remove <id>
cybermod doctor                                   # check everything (changes nothing; --fix <id> repairs)
cybermod play                                     # start the game with mods (start Steam first)
```

Game not in the default Steam folder? Choose it in the app's Settings, or `cybermod config set game-dir "/path/to/Cyberpunk 2077"`.
[docs/CLI.md](docs/CLI.md) has every command, where files go and the JSON output.

## Build from source

```bash
swift build && swift test                                    # library, CLI, app model; tests never touch your game
xcodebuild -project CyberModStudio.xcodeproj -scheme CyberModStudio -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build # build/Build/Products/Release/CyberMod Studio.app
```

Layout and design: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Releases: push a `vX.Y.Z` tag (see
`.github/workflows/release.yml`).
