// ModStore.swift - installed mods, one manifest per mod, so remove/disable touch exactly the files a mod installed.

import Foundation

public struct InstalledFile: Codable, Equatable {
    /// Path relative to the game folder.
    public var path: String
    public var sha256: String
    /// The path it was installed at, when `LoadOrder.prioritize` renamed it since.
    public var original: String?
}

public struct ModRecord: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var version: String?
    /// Where it came from, as `cybermod mod add` accepts it (a path, URL, github:..., nexus:..., registry:...).
    public var source: String
    public var installedAt: Date
    public var enabled: Bool
    public var files: [InstalledFile]
    public var warnings: [String]
}

/// A file a mod wants that is already there. `owner` is a mod id, or nil for a file cybermod did not install.
public struct Conflict: Codable, Equatable {
    public var path: String
    public var owner: String?
}

public struct InstallReport: Codable {
    public var mod: ModRecord
    public var ignored: [String]
    public var overwritten: [Conflict]
    public var dryRun: Bool
}

/// Manifests live in `<state>/mods/<id>.json`; a disabled mod's files wait in `<state>/disabled/<id>/`.
public struct ModStore {
    public let kit: Kit
    var fm: FileManager { .default }
    var manifests: URL { kit.stateDir.appendingPathComponent("mods") }
    func held(_ id: String) -> URL { kit.stateDir.appendingPathComponent("disabled/\(id)") }

    public init(kit: Kit) { self.kit = kit }

    /// "Cool Mod v2!" -> "cool-mod-v2"
    public static func slug(_ text: String) -> String {
        let chars = text.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
        let slug = String(chars).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? "mod" : slug
    }

    public func list() -> [ModRecord] {
        let files = (try? fm.contentsOfDirectory(at: manifests, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { FileOps.readJSON(ModRecord.self, from: $0) }
            .sorted { $0.id < $1.id }
    }

    /// A mod by id, or by name ignoring case.
    public func get(_ idOrName: String) throws -> ModRecord {
        let mods = list()
        if let mod = mods.first(where: { $0.id == idOrName })
            ?? mods.first(where: { $0.name.caseInsensitiveCompare(idOrName) == .orderedSame }) {
            return mod
        }
        throw KitError("No installed mod called \"\(idOrName)\".", hint: "Run `cybermod mod list` to see the ids.")
    }

    func save(_ mod: ModRecord) throws {
        try FileOps.writeJSON(mod, to: manifests.appendingPathComponent("\(mod.id).json"))
    }

    /// Lowercased game path -> owning mod id, for every mod except `except`.
    func owners(except: String? = nil) -> [String: String] {
        var owners: [String: String] = [:]
        for mod in list() where mod.id != except {
            for file in mod.files { owners[file.path.lowercased()] = mod.id }
        }
        return owners
    }

    func location(_ mod: ModRecord, _ path: String) -> URL {
        mod.enabled ? kit.game.appendingPathComponent(path) : held(mod.id).appendingPathComponent(path)
    }

    // MARK: Install

    /// Installs the unpacked mod in `stage`. Installing an id that exists replaces that mod (an update).
    /// Refuses Windows-only mods, and files of other mods or files cybermod did not install unless `force`.
    public func install(from stage: URL, id: String? = nil, name: String, version: String? = nil, source: String,
                        force: Bool = false, warnings: [String] = []) throws -> InstallReport {
        try kit.requireGame()
        let paths = FileOps.files(in: stage)
        if let config = paths.first(where: { $0.lowercased() == "fomod/moduleconfig.xml" || $0.lowercased().hasSuffix("/fomod/moduleconfig.xml") }) {
            throw KitError("\(name) has an installer with options (FOMOD), which cybermod does not support yet.",
                           hint: "Unpack it, find the folder of the option you want (its files sit in archive/, r6/ ... or loose) "
                               + "and run `cybermod mod add <that folder>`. Nothing was installed.",
                           details: [config])
        }
        let plan = Placement.plan(paths, modName: name)
        guard plan.windowsOnly.isEmpty else {
            throw KitError("\(name) is a Windows-only mod; it cannot run on macOS.",
                           hint: "Look for a macOS version of the mod. Windows plugins (.dll, .asi) and Cyber Engine Tweaks "
                               + "(Lua) mods do not work with RED4ext for macOS. Nothing was installed.",
                           details: plan.windowsOnly)
        }
        guard !plan.files.isEmpty else {
            throw KitError("No mod files found in \(source).",
                           hint: "cybermod installs .archive, .xl, .reds, .yaml/.yml/.tweak, r6/input .xml and macOS .dylib "
                               + "plugins. Check that you picked the mod's main file.",
                           details: plan.ignored)
        }

        let id = Self.slug(id ?? name)
        let previous = list().first { $0.id == id }
        let owners = owners(except: id)
        let conflicts: [Conflict] = plan.files.compactMap { file in
            if let owner = owners[file.destination.lowercased()] { return Conflict(path: file.destination, owner: owner) }
            let mine = previous?.files.contains { $0.path.lowercased() == file.destination.lowercased() } ?? false
            if !mine, fm.fileExists(atPath: kit.game.appendingPathComponent(file.destination).path) {
                return Conflict(path: file.destination, owner: nil)
            }
            return nil
        }
        if !conflicts.isEmpty && !force {
            throw KitError("\(name) would overwrite \(conflicts.count) file(s) that belong to other mods.",
                           hint: "Remove or disable the other mod first (`cybermod mod remove <id>`), or run again with "
                               + "--force to overwrite them. Nothing was installed.",
                           details: conflicts.map(Self.describe))
        }

        var warnings = warnings
        let plugins = kit.game.appendingPathComponent("red4ext/plugins")
        if plan.files.contains(where: { $0.destination.hasPrefix(Placement.archiveRoot) }),
           !fm.fileExists(atPath: plugins.appendingPathComponent("ArchiveXL").path) {
            warnings.append("Needs ArchiveXL to load .archive files on macOS; run `cybermod install`.")
        }
        if plan.files.contains(where: { $0.destination.hasPrefix("r6/tweaks/") }),
           !fm.fileExists(atPath: plugins.appendingPathComponent("TweakXL").path) {
            warnings.append("Needs TweakXL for r6/tweaks; run `cybermod install`.")
        }

        var mod = ModRecord(id: id, name: name, version: version, source: source, installedAt: Date(), enabled: true,
                            files: [], warnings: warnings)
        for file in plan.files {
            mod.files.append(InstalledFile(path: file.destination,
                                           sha256: try Checksum.sha256(of: stage.appendingPathComponent(file.source)), original: nil))
        }
        let report = InstallReport(mod: mod, ignored: plan.ignored, overwritten: conflicts, dryRun: kit.dryRun)
        if kit.dryRun { return report }
        try checkCancelled()

        try FileOps.install(plan.files.map { (stage.appendingPathComponent($0.source), kit.game.appendingPathComponent($0.destination)) })

        // An update: drop the old version's files that the new one does not have.
        if let previous {
            let keep = Set(mod.files.map { $0.path.lowercased() })
            for file in previous.files where !previous.enabled || !keep.contains(file.path.lowercased()) {
                let url = location(previous, file.path)
                try? fm.removeItem(at: url)
                FileOps.pruneEmpty(url.deletingLastPathComponent(), below: kit.game)
            }
            try? fm.removeItem(at: held(id))
        }
        try takeOver(conflicts, by: id)
        try save(mod)
        return report
    }

    /// Files forced over other mods now belong to `id`: drop them from their old owners' manifests.
    func takeOver(_ conflicts: [Conflict], by id: String) throws {
        for (owner, taken) in Dictionary(grouping: conflicts.filter { $0.owner != nil }, by: { $0.owner! }) {
            guard var other = list().first(where: { $0.id == owner }) else { continue }
            let paths = Set(taken.map { $0.path.lowercased() })
            other.files.removeAll { paths.contains($0.path.lowercased()) }
            other.warnings.append("\(taken.count) file(s) were overwritten by \(id).")
            try save(other)
        }
    }

    static func describe(_ conflict: Conflict) -> String {
        "\(conflict.path) (\(conflict.owner.map { "mod \($0)" } ?? "not installed by cybermod"))"
    }

    // MARK: Remove, enable, disable

    /// Deletes exactly the files the mod installed, then its manifest.
    @discardableResult
    public func remove(_ idOrName: String) throws -> ModRecord {
        let mod = try get(idOrName)
        if kit.dryRun { return mod }
        for file in mod.files {
            let url = location(mod, file.path)
            try? fm.removeItem(at: url)
            FileOps.pruneEmpty(url.deletingLastPathComponent(), below: mod.enabled ? kit.game : held(mod.id))
        }
        try? fm.removeItem(at: held(mod.id))
        try fm.removeItem(at: manifests.appendingPathComponent("\(mod.id).json"))
        return mod
    }

    /// Disable moves the mod's files to the holding folder; enable moves them back (refusing to overwrite files that
    /// appeared there since, unless `force`).
    @discardableResult
    public func setEnabled(_ idOrName: String, _ enabled: Bool, force: Bool = false) throws -> ModRecord {
        var mod = try get(idOrName)
        guard mod.enabled != enabled else { return mod }
        let game = kit.game, hold = held(mod.id)

        if enabled {
            let owners = owners(except: mod.id)
            let conflicts = mod.files.filter { fm.fileExists(atPath: game.appendingPathComponent($0.path).path) }
                .map { Conflict(path: $0.path, owner: owners[$0.path.lowercased()]) }
            if !conflicts.isEmpty && !force {
                throw KitError("Enabling \(mod.id) would overwrite \(conflicts.count) file(s).",
                               hint: "Disable or remove the other mod first, or run again with --force.",
                               details: conflicts.map(Self.describe))
            }
            if kit.dryRun { return mod }
            conflicts.forEach { try? fm.removeItem(at: game.appendingPathComponent($0.path)) }
            try takeOver(conflicts, by: mod.id)
        }
        if kit.dryRun { return mod }

        let (from, to) = enabled ? (hold, game) : (game, hold)
        let present = mod.files.filter { fm.fileExists(atPath: from.appendingPathComponent($0.path).path) }
        let missing = mod.files.count - present.count
        if missing > 0 {
            mod.warnings.append("\(missing) file(s) were already missing when the mod was \(enabled ? "enabled" : "disabled").")
        }
        try FileOps.move(present.map { (from.appendingPathComponent($0.path), to.appendingPathComponent($0.path)) })
        if enabled {
            try? fm.removeItem(at: hold)
        } else {
            present.forEach { FileOps.pruneEmpty(game.appendingPathComponent($0.path).deletingLastPathComponent(), below: game) }
        }
        mod.enabled = enabled
        try save(mod)
        return mod
    }

    /// Mod files in archive/pc/mod, r6/scripts and r6/tweaks that cybermod does not track (installed by hand).
    public func unmanagedFiles() -> [String] {
        let tracked = Set(owners().keys)
        let modExtensions: Set<String> = ["archive", "xl", "reds", "yaml", "yml", "tweak"]
        return ["archive/pc/mod", "r6/scripts", "r6/tweaks"].flatMap { dir in
            FileOps.files(in: kit.game.appendingPathComponent(dir)).map { "\(dir)/\($0)" }
        }.filter { modExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !tracked.contains($0.lowercased()) }
    }

    // MARK: Adopt

    /// Registers mod files installed by hand (`unmanagedFiles`) as mods, without moving anything. Files are grouped by
    /// name: an archive with its .archive.xl, a folder under r6/scripts or r6/tweaks, otherwise one mod per file name.
    public func adopt() throws -> [ModRecord] {
        var groups: [String: (name: String, files: [String])] = [:]
        for path in unmanagedFiles() {
            let name = Self.adoptedName(path)
            groups[Self.slug(name), default: (name, [])].files.append(path)
        }
        var taken = Set(list().map(\.id))
        var mods: [ModRecord] = []
        for key in groups.keys.sorted() {
            var id = key, n = 2
            while taken.contains(id) { id = "\(key)-\(n)"; n += 1 }
            taken.insert(id)
            let group = groups[key]!
            let files = try group.files.map { InstalledFile(path: $0, sha256: try Checksum.sha256(of: kit.game.appendingPathComponent($0)), original: nil) }
            mods.append(ModRecord(id: id, name: group.name, version: nil, source: "adopted", installedAt: Date(), enabled: true,
                                  files: files, warnings: []))
        }
        if !kit.dryRun { try mods.forEach(save) }
        return mods
    }

    static func adoptedName(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        if (path.hasPrefix("r6/scripts/") || path.hasPrefix("r6/tweaks/")) && parts.count > 3 { return parts[2] }
        if path.hasPrefix("archive/pc/mod/") && parts.count > 4 { return parts[3] }
        return Fetched.modName(fromFile: parts.last!)
    }
}
