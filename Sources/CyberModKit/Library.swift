// Library.swift - mod updates and archive load order.

import Foundation

public struct UpdateInfo: Codable, Equatable {
    public var id: String
    public var installed: String?
    /// Newest version at the source, or nil when the check failed (`error` says why).
    public var available: String?
    /// What `ModStore.update` installs from.
    public var source: String
    public var error: String?
}

public enum Updates {
    /// Compares mods from GitHub, Nexus Mods (needs the API key) and the registry with their source. Mods from files,
    /// plain URLs or adopted ones have no version to compare and are skipped. Only mods with a newer version (or a
    /// failed check) are returned.
    public static func check(kit: Kit) async -> [UpdateInfo] {
        var registry: RegistryIndex?
        var results: [UpdateInfo] = []
        for mod in ModStore(kit: kit).list() {
            guard let source = try? ModSource.parse(mod.source) else { continue }
            var info = UpdateInfo(id: mod.id, installed: mod.version, available: nil, source: mod.source)
            do {
                switch source {
                case .github(let repo, _):
                    info.source = "github:\(repo)"
                    info.available = try await GitHub.releases(repo, session: kit.session).first?.tag_name
                case .nexus(let id, _), .nxm(let id, _, _, _):
                    info.source = "nexus:\(id)"
                    info.available = try await Nexus.mod(id, key: try Nexus.key(), session: kit.session).version
                case .registry(let id):
                    if registry == nil { registry = try await Registry.load(kit: kit) }
                    info.available = registry?.entry(id)?.version
                default:
                    continue
                }
            } catch {
                info.error = (error as? KitError)?.message ?? error.localizedDescription
            }
            if info.error != nil || (info.available != nil && info.available != mod.version) { results.append(info) }
        }
        return results
    }
}

extension ModStore {
    /// Reinstalls a mod from its source's newest version (same id; files the new version drops are removed).
    public func update(_ idOrName: String, force: Bool = false) async throws -> [InstallReport] {
        let mod = try get(idOrName)
        var source = try ModSource.parse(mod.source)
        switch source {
        case .github(let repo, _): source = .github(repo: repo, tag: nil)
        case .nexus(let id, _), .nxm(let id, _, _, _): source = .nexus(mod: id, file: nil)
        case .registry: break
        default:
            throw KitError("\(mod.id) came from \(mod.source), which has no newer versions to fetch.",
                           hint: "Download the new version yourself and run `cybermod mod add <file> --name \"\(mod.name)\"`.")
        }
        return try await add(source, name: mod.name, id: mod.id, force: force)
    }
}

// MARK: - Load order

public struct ArchiveEntry: Codable, Equatable {
    /// 1 loads first and wins every file it shares with later archives.
    public var rank: Int
    public var file: String
    /// Owning mod id, nil when installed by hand.
    public var mod: String?
}

public struct Rename: Codable, Equatable {
    public var from: String
    public var to: String
}

public enum LoadOrder {
    /// The archives ArchiveXL loads from archive/pc/mod, in its order (case-insensitive names; first wins).
    public static func list(kit: Kit) -> [ArchiveEntry] {
        let owners = ModStore(kit: kit).owners()
        let dir = kit.game.appendingPathComponent("archive/pc/mod")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".archive") }.sorted(by: RDAR.loadsBefore)
        return names.enumerated().map { ArchiveEntry(rank: $0 + 1, file: $1, mod: owners["archive/pc/mod/\($1)".lowercased()]) }
    }

    /// Makes `archive` load before `other` by prefixing its name with "!" (the smallest prefix that sorts first). The
    /// new name is recorded in the owning mod's manifest, so remove and disable still find it; updating the mod puts
    /// the original name back.
    public static func prioritize(kit: Kit, archive: String, before other: String) throws -> Rename? {
        let fm = FileManager.default
        let dir = kit.game.appendingPathComponent("archive/pc/mod")
        for name in [archive, other] where !fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            throw KitError("archive/pc/mod/\(name) does not exist.", hint: "See the archive names: cybermod mod order")
        }
        if RDAR.loadsBefore(archive, other) { return nil }
        let store = ModStore(kit: kit)
        let path = "archive/pc/mod/\(archive)"
        guard var mod = store.list().first(where: { $0.enabled && $0.files.contains { $0.path.lowercased() == path.lowercased() } }) else {
            throw KitError("\(archive) was not installed with cybermod, so its new name could not be tracked.",
                           hint: "Track your hand-installed mods first: cybermod mod adopt")
        }
        var prefix = "!"
        while !RDAR.loadsBefore(prefix + archive, other) {
            prefix += "!"
            if prefix.count > 32 {
                throw KitError("No \"!\" prefix sorts \(archive) before \(other).", hint: "Rename \(other) instead.")
            }
        }
        let renamed = prefix + archive
        guard !fm.fileExists(atPath: dir.appendingPathComponent(renamed).path) else {
            throw KitError("archive/pc/mod/\(renamed) already exists.", hint: "Rename or remove it first.")
        }
        try kit.requireGameStopped()
        let rename = Rename(from: path, to: "archive/pc/mod/\(renamed)")
        if kit.dryRun { return rename }
        try FileOps.move([(dir.appendingPathComponent(archive), dir.appendingPathComponent(renamed))])
        let index = mod.files.firstIndex { $0.path.lowercased() == path.lowercased() }!
        mod.files[index].original = mod.files[index].original ?? mod.files[index].path
        mod.files[index].path = rename.to
        try store.save(mod)
        return rename
    }
}
