// Doctor.swift - read-only health check of the game folder, RED4ext and installed mods.

import Foundation

public struct Finding: Codable, Equatable, Sendable {
    public enum Level: String, Codable, Sendable { case ok, info, warning, error }
    public var level: Level
    /// Stable id of the check, e.g. "signature", "misplaced-xl" ("missing-files:<mod id>" per mod).
    public var id: String
    public var message: String
    public var hint: String?
    public var details: [String]?
    /// Pass to `Doctor.fix` (`cybermod doctor --fix <id>`) to repair this automatically.
    public var fix: String?
}

/// `winner` and `loser` both contain `files` of the same game files; `winner` loads first, so its copies are used.
public struct ArchiveConflict: Codable, Equatable, Sendable {
    public var winner: String
    public var loser: String
    public var files: Int
}

public struct DoctorReport: Codable, Sendable {
    public var game: String
    public var findings: [Finding]
    public var conflicts: [ArchiveConflict]
    public var healthy: Bool { !findings.contains { $0.level == .error } }
}

/// RDAR (.archive) file tables. Header `<4sIQI>` magic/version/indexPos/indexSize; at indexPos the index `<IIQIII>`
/// (tableOffset, tableSize, crc, fileCount, segmentCount, depCount), then 56-byte entries that start with the
/// FNV-1a-64 hash of the file's path.
public enum RDAR {
    /// Path hashes of the files in an archive, or nil when it is not a readable RDAR file.
    public static func fileHashes(_ url: URL) -> [UInt64]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 20), header.count == 20, header.prefix(4) == Data("RDAR".utf8),
              (try? handle.seek(toOffset: header.u64(8))) != nil,
              let index = try? handle.read(upToCount: 28), index.count == 28 else { return nil }
        let count = Int(index.u32(16))
        guard count < 1_000_000 else { return nil }
        let entries = count == 0 ? Data() : (try? handle.read(upToCount: count * 56)) ?? Data()
        guard entries.count == count * 56 else { return nil }
        return (0..<count).map { entries.u64($0 * 56) }
    }

    public static func fnv1a64(_ path: String) -> UInt64 {
        path.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }

    /// ArchiveXL's load order: names compared upper-cased byte by byte (as Windows lists a folder).
    public static func loadsBefore(_ a: String, _ b: String) -> Bool {
        let upper = { (s: String) in s.utf8.map { (97...122).contains($0) ? $0 - 32 : $0 } }
        let (ua, ub) = (upper(a), upper(b))
        return ua == ub ? a < b : ua.lexicographicallyPrecedes(ub)
    }

    /// For archives in load order: which earlier archive wins each shared file, counted per pair.
    public static func conflicts(_ tables: [(name: String, hashes: [UInt64])]) -> [ArchiveConflict] {
        var owner: [UInt64: Int] = [:]
        var counts: [Int: [Int: Int]] = [:]  // loser -> winner -> files
        for (i, table) in tables.enumerated() {
            for hash in Set(table.hashes) {
                if let first = owner[hash] { counts[i, default: [:]][first, default: 0] += 1 } else { owner[hash] = i }
            }
        }
        return counts.keys.sorted().flatMap { loser in
            counts[loser]!.keys.sorted().map { winner in
                ArchiveConflict(winner: tables[winner].name, loser: tables[loser].name, files: counts[loser]![winner]!)
            }
        }
    }
}

public enum Doctor {
    /// Ids `fix` accepts.
    public static let fixes = ["install-loader", "rerun-setup", "move-nested-archives", "move-misplaced-xl",
                               "remove-duplicate-archives", "adopt"]

    public static func run(kit: Kit) -> DoctorReport {
        let fm = FileManager.default
        let game = kit.game
        var findings: [Finding] = []
        func add(_ level: Finding.Level, _ id: String, _ message: String, hint: String? = nil, details: [String]? = nil, fix: String? = nil) {
            findings.append(Finding(level: level, id: id, message: message, hint: hint,
                                    details: details?.isEmpty == true ? nil : details, fix: fix))
        }

        guard fm.fileExists(atPath: kit.gameBinary.path) else {
            add(.error, "game", "Cyberpunk 2077 not found in \(game.path).",
                hint: "Pass --game-dir \"/path/to/Cyberpunk 2077\" or run `cybermod config set game-dir \"/path/to/Cyberpunk 2077\"`.")
            return DoctorReport(game: game.path, findings: findings, conflicts: [])
        }
        add(.ok, "game", "Cyberpunk 2077 found in \(game.path).")
        if kit.isGameRunning() { add(.info, "game-running", "The game is running.", hint: "Quit it before changing mods.") }
        if Process.isRunning("steam_osx") {
            add(.ok, "steam", "Steam is running.")
        } else {
            add(.warning, "steam", "Steam is not running.", hint: "Start Steam and sign in before `cybermod play`, or saves are missing.")
        }

        // RED4ext
        let installed = fm.fileExists(atPath: kit.launcher.path) && fm.fileExists(atPath: game.appendingPathComponent("red4ext/RED4ext.dylib").path)
        if installed {
            let version = Loader.installedVersion(kit) ?? "version unknown (installed without cybermod)"
            add(.ok, "red4ext", "RED4ext for macOS is installed (\(version)).")
            let build = MachO.uuid(kit.gameBinary) ?? "unknown"
            if let db = AddressDB(kit.addressDB) {
                if db.uuid == build {
                    add(.ok, "build", "Game build \(build) matches RED4ext's address database\(db.gameVersion.map { " (game \($0))" } ?? "").")
                } else {
                    add(.error, "build", "Game build \(build) does not match RED4ext's address database (\(db.uuid)).",
                        hint: "The game was updated. Wait for a RED4ext release for this game version, then run `cybermod update`. "
                            + "Steam's Play button still starts the game without mods.")
                }
            } else {
                add(.error, "build", "RED4ext's address database is missing.", hint: "Reinstall RED4ext: cybermod install", fix: "install-loader")
            }
            if MachO.isResigned(kit.gameBinary) {
                add(.ok, "signature", "The game binary is re-signed for RED4ext.")
            } else {
                add(.error, "signature", "The game binary is not set up for RED4ext (Steam replaced it).",
                    hint: "Run `cybermod doctor --fix rerun-setup` (runs red4ext/macos/scripts/install_macos.sh once).", fix: "rerun-setup")
            }
        } else {
            add(.error, "red4ext", "RED4ext for macOS is not installed.", hint: "Install it: cybermod install", fix: "install-loader")
        }

        // Plugins
        let pluginsDir = game.appendingPathComponent("red4ext/plugins")
        let plugins = ((try? fm.contentsOfDirectory(atPath: pluginsDir.path)) ?? []).filter {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: pluginsDir.appendingPathComponent($0).path, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
        let macPlugins = plugins.filter { name in FileOps.files(in: pluginsDir.appendingPathComponent(name)).contains { $0.hasSuffix(".dylib") } }
        if !macPlugins.isEmpty { add(.ok, "plugins", "RED4ext plugins: \(macPlugins.joined(separator: ", ")).") }

        // Archives in archive/pc/mod: direct children load (ArchiveXL), nested ones do not.
        let modDir = game.appendingPathComponent("archive/pc/mod")
        let modFiles = FileOps.files(in: modDir)
        let archives = loadedArchives(kit)
        if !archives.isEmpty && !plugins.contains("ArchiveXL") {
            add(.warning, "archivexl", "\(archives.count) .archive mods, but ArchiveXL is not installed; the macOS game does not load archive/pc/mod by itself.",
                hint: "Install it with RED4ext: cybermod install", fix: "install-loader")
        }
        let nested = nestedArchives(kit)
        if !nested.isEmpty {
            add(.warning, "nested-archives", "\(nested.count) .archive file(s) are in subfolders of archive/pc/mod and are not loaded.",
                hint: "Move them directly into archive/pc/mod (`cybermod doctor --fix move-nested-archives`).", details: nested,
                fix: "move-nested-archives")
        }
        let misplaced = misplacedXL(kit)
        if !misplaced.isEmpty {
            add(.warning, "misplaced-xl", "\(misplaced.count) .xl file(s) are outside archive/pc/mod; ArchiveXL does not read them there.",
                hint: "Move them into archive/pc/mod (`cybermod doctor --fix move-misplaced-xl`).", details: misplaced, fix: "move-misplaced-xl")
        }

        // Windows-only mods.
        let windows = plugins.flatMap { name in
            FileOps.files(in: pluginsDir.appendingPathComponent(name)).map { "red4ext/plugins/\(name)/\($0)" }
        }.filter { path in [".dll", ".asi"].contains { path.lowercased().hasSuffix($0) } }
            + FileOps.files(in: game.appendingPathComponent("bin")).map { "bin/\($0)" }
        if !windows.isEmpty {
            add(.warning, "windows-mods", "\(windows.count) Windows-only mod file(s) (.dll/.asi plugins, Cyber Engine Tweaks); they do nothing on macOS.",
                hint: "Remove them and look for macOS versions of those mods.", details: Array(windows.prefix(50)))
        }

        // Archive file tables: unreadable, duplicates, conflicts.
        let tables = archives.compactMap { name in RDAR.fileHashes(modDir.appendingPathComponent(name)).map { (name: name, hashes: $0) } }
        let unreadable = archives.filter { name in !tables.contains { $0.name == name } }
        if !unreadable.isEmpty {
            add(.warning, "invalid-archives", "\(unreadable.count) file(s) in archive/pc/mod are not valid .archive files.",
                hint: "Re-download those mods.", details: unreadable)
        }
        let identical = identicalArchives(tables)
        if !identical.isEmpty {
            add(.warning, "identical-archives", "\(identical.count) set(s) of archives contain exactly the same files (the same mod installed twice?).",
                hint: "Keep the first of each set (`cybermod doctor --fix remove-duplicate-archives` moves the others out).",
                details: identical.map { $0.joined(separator: " = ") }, fix: "remove-duplicate-archives")
        }
        let sameName = Dictionary(grouping: modFiles.filter { $0.lowercased().hasSuffix(".archive") },
                                  by: { ($0 as NSString).lastPathComponent.lowercased() })
            .values.filter { $0.count > 1 }.map { $0.joined(separator: " = ") }.sorted()
        if !sameName.isEmpty {
            add(.warning, "duplicate-names", "\(sameName.count) archive name(s) appear more than once under archive/pc/mod.",
                hint: "Keep one copy of each.", details: sameName)
        }
        let conflicts = RDAR.conflicts(tables)
        if conflicts.isEmpty {
            if !tables.isEmpty { add(.ok, "conflicts", "\(tables.count) archives, no two replace the same file.") }
        } else {
            add(.info, "conflicts", "\(Set(conflicts.map(\.loser)).count) of \(tables.count) archives replace files another archive also replaces; "
                + "the archive first in name order wins.",
                hint: "Usually intended. To let another archive win: cybermod mod order <archive> --before <other>",
                details: conflicts.map { "\($0.winner) wins over \($0.loser) (\($0.files) files)" })
        }

        // Mods installed with cybermod.
        let store = ModStore(kit: kit)
        let mods = store.list()
        for mod in mods where mod.enabled {
            let missing = mod.files.filter { !fm.fileExists(atPath: game.appendingPathComponent($0.path).path) }.map(\.path)
            if !missing.isEmpty {
                add(.warning, "missing-files:\(mod.id)", "\(mod.id): \(missing.count) installed file(s) are missing.",
                    hint: "Reinstall it (cybermod mod add \(mod.source)) or remove it (cybermod mod remove \(mod.id)).", details: missing)
            }
        }
        let unmanaged = store.unmanagedFiles()
        add(.info, "mods", "\(mods.count) mod(s) installed with cybermod; \(unmanaged.count) mod file(s) installed by hand.",
            hint: unmanaged.isEmpty ? nil : "Track them so you can disable and remove them: cybermod mod adopt",
            fix: unmanaged.isEmpty ? nil : "adopt")

        return DoctorReport(game: game.path, findings: findings, conflicts: conflicts)
    }

    // MARK: Shared checks

    /// Archives directly in archive/pc/mod, in ArchiveXL's load order.
    static func loadedArchives(_ kit: Kit) -> [String] {
        FileOps.files(in: kit.game.appendingPathComponent("archive/pc/mod"))
            .filter { !$0.contains("/") && $0.hasSuffix(".archive") }.sorted(by: RDAR.loadsBefore)
    }

    static func nestedArchives(_ kit: Kit) -> [String] {
        FileOps.files(in: kit.game.appendingPathComponent("archive/pc/mod"))
            .filter { $0.contains("/") && $0.lowercased().hasSuffix(".archive") }.map { "archive/pc/mod/\($0)" }
    }

    /// .xl files under archive/ (outside archive/pc/mod), r6/ or loose in the game folder.
    static func misplacedXL(_ kit: Kit) -> [String] {
        let game = kit.game
        let candidates = FileOps.files(in: game.appendingPathComponent("archive")).map { "archive/\($0)" }
            .filter { !$0.lowercased().hasPrefix("archive/pc/mod/") }
            + FileOps.files(in: game.appendingPathComponent("r6")).map { "r6/\($0)" }
            + ((try? FileManager.default.contentsOfDirectory(atPath: game.path)) ?? [])
        return candidates.filter { $0.lowercased().hasSuffix(".xl") }
    }

    /// Sets of archives with the same non-empty file table, each in load order.
    static func identicalArchives(_ tables: [(name: String, hashes: [UInt64])]) -> [[String]] {
        Dictionary(grouping: tables.filter { !$0.hashes.isEmpty }, by: { $0.hashes.sorted() })
            .values.filter { $0.count > 1 }.map { $0.map(\.name) }.sorted { $0[0] < $1[0] }
    }

    // MARK: Fixes

    /// Applies one fix from `fixes`; returns what it did. Moves never overwrite; removed duplicates go to
    /// `<state>/removed/` so they can be put back.
    public static func fix(_ id: String, kit: Kit) async throws -> [String] {
        try kit.requireGame()
        try kit.requireGameStopped()
        let fm = FileManager.default
        let game = kit.game
        let modDir = game.appendingPathComponent("archive/pc/mod")
        var done: [String] = []

        /// Moves each path to `destination(path)`, skipping (and reporting) any that would overwrite.
        func moveAll(_ paths: [String], _ destination: (String) -> URL) throws {
            for path in paths {
                let to = destination(path)
                if fm.fileExists(atPath: to.path) {
                    done.append("Skipped \(path): \(to.lastPathComponent) already exists there.")
                    continue
                }
                if !kit.dryRun {
                    try FileOps.move([(game.appendingPathComponent(path), to)])
                    FileOps.pruneEmpty(game.appendingPathComponent(path).deletingLastPathComponent(), below: game)
                }
                done.append("Moved \(path) to \(to.path.replacingOccurrences(of: game.path + "/", with: "")).")
            }
        }

        switch id {
        case "install-loader":
            let report = try await Loader.install(kit: kit)
            done.append("Installed RED4ext for macOS \(report.version ?? "").")
        case "rerun-setup":
            guard fm.fileExists(atPath: kit.setupScript.path) else {
                throw KitError("install_macos.sh is missing.", hint: "Reinstall RED4ext: cybermod install")
            }
            if !kit.dryRun {
                let result = try Process.capture("/bin/bash", [kit.setupScript.path], cwd: game)
                guard result.status == 0 else {
                    throw KitError("install_macos.sh failed.", hint: "Read its output above.",
                                   details: result.output.split(separator: "\n").map(String.init))
                }
            }
            done.append("Ran install_macos.sh.")
        case "move-nested-archives":
            try moveAll(nestedArchives(kit)) { modDir.appendingPathComponent(($0 as NSString).lastPathComponent) }
        case "move-misplaced-xl":
            try moveAll(misplacedXL(kit)) { modDir.appendingPathComponent(($0 as NSString).lastPathComponent) }
        case "remove-duplicate-archives":
            let owned = ModStore(kit: kit).owners()
            let tables = loadedArchives(kit).compactMap { name in RDAR.fileHashes(modDir.appendingPathComponent(name)).map { (name: name, hashes: $0) } }
            let extras = identicalArchives(tables).flatMap { $0.dropFirst() }.map { "archive/pc/mod/\($0)" }
            for path in extras where owned[path.lowercased()] != nil {
                done.append("Kept \(path): it belongs to mod \(owned[path.lowercased()]!) (remove that mod instead).")
            }
            try moveAll(extras.filter { owned[$0.lowercased()] == nil }) {
                kit.stateDir.appendingPathComponent("removed").appendingPathComponent(($0 as NSString).lastPathComponent)
            }
        case "adopt":
            let mods = try ModStore(kit: kit).adopt()
            done.append("Now tracking \(mods.count) mod(s) installed by hand.")
        default:
            throw KitError("Unknown fix \"\(id)\".", hint: "Fixes: \(fixes.joined(separator: ", ")). `cybermod doctor` shows which apply.")
        }
        return done
    }
}
