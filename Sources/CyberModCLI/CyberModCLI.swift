// cybermod - command-line front end for CyberModKit. Parsing and printing only; the work happens in CyberModKit.

import ArgumentParser
import CyberModKit
import Foundation

@main
struct CyberMod: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cybermod",
        abstract: "Install RED4ext for macOS and Cyberpunk 2077 mods, check the setup, and play.",
        discussion: "Start with `cybermod install`, then `cybermod mod add <mod>` and `cybermod play`. Details: "
            + "https://github.com/jackmaxwil/cybermod-studio",
        version: cybermodVersion,
        subcommands: [Install.self, Update.self, Uninstall.self, Doctor.self, Play.self, ModGroup.self, Search.self, ConfigGroup.self]
    )
}

// MARK: - Shared options and output

struct Global: ParsableArguments {
    @Option(help: "Cyberpunk 2077 folder (default: $CP2077_GAME_DIR, `config set game-dir`, or the Steam folder).")
    var gameDir: String?
    @Flag(help: "Print machine-readable JSON.") var json = false
    @Flag(name: .shortAndLong, help: "Answer yes to confirmations.") var yes = false
    @Flag(help: "Show what would change without changing anything.") var dryRun = false

    func kit() -> Kit {
        setlinebuf(stdout)  // keep progress lines in order with errors on stderr
        let quiet = json
        var kit = Kit(game: gameDir, dryRun: dryRun, log: { line in if !quiet { print(line) } })
        if !json { kit.openURL = { (url: URL) in _ = try? Process.capture("/usr/bin/open", [url.absoluteString]) } }
        return kit
    }

    func emit<T: Encodable>(_ value: T, human: () -> Void) {
        if json { print(String(decoding: try! JSON.encoder.encode(value), as: UTF8.self)) } else { human() }
    }

    /// Asks on the terminal unless --yes; without a terminal, --yes is required.
    func confirm(_ question: String) throws {
        if yes || dryRun { return }
        guard !json, isatty(STDIN_FILENO) == 1 else {
            throw KitError(question, hint: "Run again with --yes to confirm.")
        }
        print("\(question) [y/N] ", terminator: "")
        guard ["y", "yes"].contains(readLine()?.lowercased() ?? "") else { throw ExitCode.failure }
    }
}

/// Every command: run `execute`, turn a KitError into "Error: ... / Next: ..." (or JSON) and exit status 1.
protocol KitCommand: AsyncParsableCommand {
    var global: Global { get }
    func execute(_ kit: Kit) async throws
}

extension KitCommand {
    mutating func run() async throws {
        do {
            try await execute(global.kit())
        } catch let error as ExitCode {
            throw error
        } catch {
            let error = error as? KitError
                ?? KitError(error.localizedDescription, hint: "Run the command again; if it keeps failing, run `cybermod doctor`.")
            if global.json {
                print(String(decoding: try! JSON.encoder.encode(error), as: UTF8.self))
            } else {
                var text = "Error: \(error.message)\n"
                error.details.forEach { text += "  \($0)\n" }
                text += "Next: \(error.hint)\n"
                FileHandle.standardError.write(Data(text.utf8))
            }
            throw ExitCode.failure
        }
    }
}

func printList(_ lines: [String], limit: Int = .max) {
    lines.prefix(limit).forEach { print("    \($0)") }
    if lines.count > limit { print("    ... and \(lines.count - limit) more (--json lists all)") }
}

// MARK: - Mod loader

func printLoader(_ report: LoaderReport) {
    let verb = report.dryRun ? "Would \(report.action)" : report.action == "uninstall" ? "Uninstalled" : "Installed"
    if report.files > 0 || report.action == "uninstall" {
        print("\(verb) RED4ext for macOS\(report.version.map { " \($0)" } ?? "") (\(report.files) files).")
    }
    report.warnings.forEach { print("Warning: \($0)") }
    print("Next: \(report.nextStep)")
}

struct Install: KitCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install RED4ext for macOS (with TweakXL, ArchiveXL, ModMenu) into the game folder.",
        discussion: "Downloads the release from GitHub, verifies it against SHA256SUMS, copies it into the game folder and "
            + "runs install_macos.sh (checks the game build, backs up and re-signs the game binary).")
    @Option(help: "Release to install, e.g. 0.1.0 or 0.1.0-rc3 (default: newest).") var version: String?
    @Option(help: "Install a RED4ext-macOS-arm64-<version>.zip you already downloaded (not verified).") var zip: String?
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let report = try await Loader.install(kit: kit, version: version, zip: zip.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
        global.emit(report) { printLoader(report) }
    }
}

struct Update: KitCommand {
    static let configuration = CommandConfiguration(abstract: "Update RED4ext for macOS to the newest release.")
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let report = try await Loader.install(kit: kit, onlyIfNewer: true)
        global.emit(report) { printLoader(report) }
    }
}

struct Uninstall: KitCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove RED4ext for macOS and restore the original game binary. Your mods stay.")
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        try global.confirm("Remove RED4ext for macOS from \(kit.game.path)?")
        let report = try Loader.uninstall(kit: kit)
        global.emit(report) { printLoader(report) }
    }
}

struct Play: KitCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start Cyberpunk 2077 with mods (runs launch_red4ext.sh in the game folder).",
        discussion: "Start Steam and sign in first. Steam's Play button starts the game without mods. Output also goes to "
            + "~/Library/Logs/CyberModStudio/game.log.")
    @Argument(parsing: .captureForPassthrough, help: "Extra arguments for the game.") var arguments: [String] = []
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        if kit.dryRun {
            try PlaySession.preflight(kit: kit)
            print("Would run: \(kit.launcher.path)")
            return
        }
        let session = try PlaySession.start(kit: kit, arguments: arguments)
        for await event in session.events {
            switch event {
            case .output(let line): if !global.json { print(line) }
            case .compileFailed: break  // the launcher prints the errors itself
            case .gameStarted(let pid): if !global.json { print("Game running (pid \(pid)).") }
            case .exited(let code, let report):
                struct Exit: Encodable { var code: Int32; var report: String }
                global.emit(Exit(code: code, report: report)) { if code != 0 { print(report) } }
                if code != 0 {
                    throw KitError("launch_red4ext.sh stopped with status \(code).", hint: "Read the messages above. `cybermod doctor` checks the setup.")
                }
            }
        }
    }
}

struct Doctor: KitCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check the game, RED4ext and your mods (changes nothing unless --fix).",
        discussion: "Fixes: install-loader, rerun-setup, move-nested-archives, move-misplaced-xl, remove-duplicate-archives, adopt.")
    @Option(help: "Apply the fix with this id (shown after a problem as `--fix <id>`).") var fix: String?
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        if let fix {
            let done = try await CyberModKit.Doctor.fix(fix, kit: kit)
            global.emit(done) { done.forEach { print(kit.dryRun ? "Would: \($0)" : $0) } }
            return
        }
        let report = CyberModKit.Doctor.run(kit: kit)
        global.emit(report) {
            for finding in report.findings {
                print("[\(finding.level.rawValue)] \(finding.message)")
                printList(finding.details ?? [], limit: finding.id == "conflicts" ? .max : 15)
                if let hint = finding.hint, finding.level != .ok { print("    -> \(hint)") }
            }
        }
        if !report.healthy { throw ExitCode.failure }
    }
}

// MARK: - Mods

struct ModGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mod", abstract: "Add, list, remove, enable and disable mods.",
        subcommands: [ModAdd.self, ModList.self, ModRemove.self, ModEnable.self, ModDisable.self, ModInfo.self,
                      ModAdopt.self, ModOutdated.self, ModUpdate.self, ModOrder.self])
}

func printRecord(_ mod: ModRecord) {
    print("\(mod.id)  \(mod.enabled ? "enabled" : "disabled")  \(mod.version ?? "-")  \(mod.files.count) files  \(mod.source)")
}

struct ModAdd: KitCommand {
    static let configuration = CommandConfiguration(
        commandName: "add", abstract: "Install a mod.",
        discussion: """
        <source> is one of:
          ~/Downloads/SomeMod.zip      a downloaded .zip/.7z/.rar, a folder, or a single mod file
          https://example.com/mod.zip  a direct download link
          github:owner/repo[@tag]      the newest (or tagged) GitHub release
          nexus:<mod id>[/<file id>]   Nexus Mods (needs `cybermod config set nexus.api-key`)
          'nxm://cyberpunk2077/...'    a "Mod Manager Download" link from Nexus Mods
          registry:<name>              the community mod registry (see `cybermod search`)
        """)
    @Argument(help: "Where to get the mod.") var source: String
    @Option(help: "Name to install it under (default: from the source).") var name: String?
    @Flag(help: "Overwrite files that belong to other mods.") var force = false
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let reports = try await ModStore(kit: kit).add(try ModSource.parse(source), name: name, force: force)
        printReports(reports, global)
    }
}

func printReports(_ reports: [InstallReport], _ global: Global) {
    global.emit(reports) {
        for report in reports {
            let mod = report.mod
            print("\(report.dryRun ? "Would install" : "Installed") \(mod.name)\(mod.version.map { " \($0)" } ?? "") as \(mod.id) (\(mod.files.count) files):")
            printList(mod.files.map(\.path), limit: 20)
            if !report.ignored.isEmpty { print("  Skipped \(report.ignored.count) file(s) that are not mod files (readmes, images).") }
            if !report.overwritten.isEmpty { print("  Overwrote \(report.overwritten.count) file(s) of other mods (--force).") }
            mod.warnings.forEach { print("Warning: \($0)") }
        }
        if !(reports.first?.dryRun ?? true) { print("Next: cybermod play") }
    }
}

struct ModList: KitCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List installed mods.")
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let store = ModStore(kit: kit)
        struct Listing: Encodable { var mods: [ModRecord]; var unmanaged: [String] }
        let listing = Listing(mods: store.list(), unmanaged: store.unmanagedFiles())
        global.emit(listing) {
            if listing.mods.isEmpty { print("No mods installed with cybermod yet. Add one: cybermod mod add <source>") }
            listing.mods.forEach(printRecord)
            if !listing.unmanaged.isEmpty {
                print("\(listing.unmanaged.count) mod file(s) in the game folder were installed by hand (not managed by cybermod).")
            }
        }
    }
}

struct ModRemove: KitCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Delete exactly the files a mod installed.")
    @Argument(help: "Mod id (see `cybermod mod list`).") var id: String
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        try kit.requireGameStopped()
        let mod = try ModStore(kit: kit).remove(id)
        global.emit(mod) { print("\(kit.dryRun ? "Would remove" : "Removed") \(mod.id) (\(mod.files.count) files).") }
    }
}

struct ModEnable: KitCommand {
    static let configuration = CommandConfiguration(commandName: "enable", abstract: "Put a disabled mod's files back.")
    @Argument(help: "Mod id.") var id: String
    @Flag(help: "Overwrite files that appeared in their place.") var force = false
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        try kit.requireGameStopped()
        let mod = try ModStore(kit: kit).setEnabled(id, true, force: force)
        global.emit(mod) { print("\(kit.dryRun ? "Would enable" : "Enabled") \(mod.id).") }
    }
}

struct ModDisable: KitCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable", abstract: "Move a mod's files out of the game folder until you enable it again.")
    @Argument(help: "Mod id.") var id: String
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        try kit.requireGameStopped()
        let mod = try ModStore(kit: kit).setEnabled(id, false)
        global.emit(mod) { print("\(kit.dryRun ? "Would disable" : "Disabled") \(mod.id).") }
    }
}

struct ModInfo: KitCommand {
    static let configuration = CommandConfiguration(commandName: "info", abstract: "Show a mod's details and files.")
    @Argument(help: "Mod id.") var id: String
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let mod = try ModStore(kit: kit).get(id)
        global.emit(mod) {
            print("""
            \(mod.name) (\(mod.id))
              version:   \(mod.version ?? "-")
              status:    \(mod.enabled ? "enabled" : "disabled")
              source:    \(mod.source)
              installed: \(mod.installedAt.formatted(date: .abbreviated, time: .shortened))
              files:
            """)
            printList(mod.files.map(\.path))
            mod.warnings.forEach { print("Warning: \($0)") }
        }
    }
}

struct ModAdopt: KitCommand {
    static let configuration = CommandConfiguration(
        commandName: "adopt", abstract: "Track mods you installed by hand, without moving them, so disable and remove work.")
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let mods = try ModStore(kit: kit).adopt()
        global.emit(mods) {
            mods.forEach(printRecord)
            print("\(kit.dryRun ? "Would track" : "Now tracking") \(mods.count) mod(s).")
        }
    }
}

struct ModOutdated: KitCommand {
    static let configuration = CommandConfiguration(
        commandName: "outdated", abstract: "List mods with a newer version on GitHub, Nexus Mods or the registry.")
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let updates = await Updates.check(kit: kit)
        global.emit(updates) {
            if updates.isEmpty { print("All mods with a known source are up to date.") }
            for update in updates {
                print("\(update.id)  \(update.installed ?? "-") -> \(update.available ?? "?")\(update.error.map { "  (\($0))" } ?? "")")
            }
            if updates.contains(where: { $0.error == nil }) { print("Next: cybermod mod update <id>   (or --all)") }
        }
    }
}

struct ModUpdate: KitCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Install the newest version of a mod.")
    @Argument(help: "Mod id.") var id: String?
    @Flag(help: "Update every mod `cybermod mod outdated` lists.") var all = false
    @Flag(help: "Overwrite files that belong to other mods.") var force = false
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let store = ModStore(kit: kit)
        let ids = all ? await Updates.check(kit: kit).filter { $0.error == nil }.map(\.id) : id.map { [$0] } ?? []
        guard all || !ids.isEmpty else { throw KitError("Which mod?", hint: "cybermod mod update <id>, or --all") }
        var reports: [InstallReport] = []
        for id in ids { reports += try await store.update(id, force: force) }
        if ids.isEmpty && !global.json { print("Nothing to update.") }
        printReports(reports, global)
    }
}

struct ModOrder: KitCommand {
    static let configuration = CommandConfiguration(
        commandName: "order", abstract: "Show the archive load order, or make an archive load before another.",
        discussion: "Archives in archive/pc/mod load in name order and the first one wins a conflict. "
            + "`cybermod mod order A.archive --before B.archive` renames A with a \"!\" prefix; updating the mod undoes it.")
    @Argument(help: "Archive to move up.") var archive: String?
    @Option(help: "Archive it should load before.") var before: String?
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        if let archive {
            guard let before else { throw KitError("Before which archive?", hint: "cybermod mod order \(archive) --before <other.archive>") }
            let rename = try LoadOrder.prioritize(kit: kit, archive: archive, before: before)
            global.emit(rename) {
                print(rename.map { "\(kit.dryRun ? "Would rename" : "Renamed") \($0.from) to \($0.to)." } ?? "\(archive) already loads before \(before).")
            }
            return
        }
        let order = LoadOrder.list(kit: kit)
        global.emit(order) { order.forEach { print("\(String(format: "%3d", $0.rank))  \($0.file)\($0.mod.map { "  (\($0))" } ?? "")") } }
    }
}

// MARK: - Registry and config

struct Search: KitCommand {
    static let configuration = CommandConfiguration(abstract: "Search the community mod registry.")
    @Argument(help: "Words to look for.") var text: [String] = []
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let results = try await Registry.load(kit: kit).search(text.joined(separator: " "))
        global.emit(results) {
            if results.isEmpty { print("Nothing found.") }
            for mod in results {
                print("\(mod.id)  \(mod.version)  \(mod.name)\(mod.author.map { " by \($0)" } ?? "")")
                if let description = mod.description { print("    \(description)") }
            }
            if !results.isEmpty { print("Install one: cybermod mod add registry:<id>") }
        }
    }
}

struct ConfigGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config", abstract: "Settings: game-dir, registry.url, nexus.api-key (kept in the Keychain).",
        subcommands: [ConfigGet.self, ConfigSet.self, ConfigList.self])
}

/// A setting's value for display; the API key is never shown.
func shownValue(_ key: String, _ config: Config) -> String? {
    guard key == Nexus.keyAccount else { return config.values[key] }
    if ProcessInfo.processInfo.environment["NEXUS_API_KEY"]?.isEmpty == false { return "(set by NEXUS_API_KEY)" }
    return Secrets.get(key) == nil ? nil : "(saved in the Keychain)"
}

struct ConfigGet: KitCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show one setting.")
    @Argument(help: "Setting name.") var key: String
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        try Config.check(key: key)
        let value = shownValue(key, Config(home: kit.home))
        global.emit([key: value]) { print(value ?? "(not set)") }
    }
}

struct ConfigList: KitCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "Show all settings.")
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        let config = Config(home: kit.home)
        let values = Dictionary(uniqueKeysWithValues: Config.keys.map { ($0, shownValue($0, config)) })
        global.emit(values) {
            Config.keys.forEach { print("\($0) = \(values[$0]! ?? "(not set)")") }
            print("game folder in use: \(kit.game.path)")
        }
    }
}

struct ConfigSet: KitCommand {
    static let configuration = CommandConfiguration(
        commandName: "set", abstract: "Change a setting (an empty value removes it).",
        discussion: "Leave out the value of nexus.api-key to type it without it showing up in your shell history.")
    @Argument(help: "Setting name.") var key: String
    @Argument(help: "New value.") var value: String?
    @OptionGroup var global: Global

    func execute(_ kit: Kit) async throws {
        try Config.check(key: key)
        if key == Nexus.keyAccount {
            let value = value ?? String(cString: getpass("Nexus Mods API key: "))
            if value.isEmpty {
                Secrets.delete(key)
                global.emit(["removed": key]) { print("Removed the Nexus Mods API key.") }
                return
            }
            let user = try await Nexus.validate(key: value)
            try Secrets.set(key, value)
            global.emit(["user": user.name, "premium": user.is_premium ? "yes" : "no"]) {
                print("Saved the API key for \(user.name) in the Keychain.")
                print(user.is_premium ? "Premium: `cybermod mod add nexus:<id>` downloads directly."
                      : "Not Premium: `cybermod mod add nexus:<id>` opens the download page; then add the nxm:// link it gives you.")
            }
            return
        }
        guard let value else { throw KitError("Missing value for \(key).", hint: "cybermod config set \(key) <value>") }
        if key == "registry.url", !value.isEmpty, !(value.hasPrefix("https://") || value.hasPrefix("file://")) {
            throw KitError("registry.url must start with https:// or file://.", hint: "cybermod config set registry.url https://.../index.json")
        }
        var config = Config(home: kit.home)
        config.values[key] = value.isEmpty ? nil : (key == "game-dir" ? (value as NSString).expandingTildeInPath : value)
        try config.save()
        global.emit(config.values) { print(value.isEmpty ? "Removed \(key)." : "\(key) = \(config.values[key]!)") }
    }
}
