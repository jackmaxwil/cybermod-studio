// Loader.swift - the RED4ext macOS bundle (RED4ext, TweakXL, ArchiveXL, ModMenu): install, update, uninstall, play.

import Foundation

/// `X.Y.Z` or `X.Y.Z-rcN`, with or without a leading "v". A release candidate sorts before its final release.
public struct ReleaseVersion: Comparable, CustomStringConvertible {
    public var major: Int, minor: Int, patch: Int
    public var rc: Int?

    public init?(_ text: String) {
        let text = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard let match = text.wholeMatch(of: #/(\d+)\.(\d+)\.(\d+)(?:-rc(\d+))?/#) else { return nil }
        major = Int(match.1)!
        minor = Int(match.2)!
        patch = Int(match.3)!
        rc = match.4.map { Int($0)! }
    }

    public var description: String { "\(major).\(minor).\(patch)" + (rc.map { "-rc\($0)" } ?? "") }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) { return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch) }
        return (a.rc ?? .max) < (b.rc ?? .max)
    }
}

/// What `cybermod install` copied, so uninstall and updates remove exactly those files.
public struct BundleRecord: Codable {
    public var version: String
    public var files: [String]
    public var installedAt: Date
}

public struct LoaderReport: Codable, Sendable {
    public var action: String
    public var version: String?
    public var files: Int
    public var output: String?
    public var warnings: [String]
    public var nextStep: String
    public var dryRun: Bool
}

public enum Loader {
    public static let repo = "jackmaxwil/RED4ext-macos"

    /// The release to install: `version` if given; otherwise the newest `vX.Y.Z[-rcN]` release, counting release
    /// candidates only until a 1.0 or later final release exists.
    public static func pick(_ releases: [GitHubRelease], version: String?) -> (GitHubRelease, ReleaseVersion)? {
        let versioned = releases.compactMap { release in ReleaseVersion(release.tag_name).map { (release, $0) } }
        if let version {
            let wanted = ReleaseVersion(version)
            return versioned.first { $0.1 == wanted }
        }
        let finals = versioned.filter { $0.1.rc == nil && $0.1.major >= 1 }
        return (finals.isEmpty ? versioned : finals).max { $0.1 < $1.1 }
    }

    static func recordURL(_ kit: Kit) -> URL { kit.stateDir.appendingPathComponent("red4ext.json") }

    public static func record(_ kit: Kit) -> BundleRecord? { FileOps.readJSON(BundleRecord.self, from: recordURL(kit)) }

    /// Installed bundle version: from cybermod's record, else the bundle's VERSION file.
    public static func installedVersion(_ kit: Kit) -> String? {
        record(kit)?.version ?? (try? String(contentsOf: kit.game.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Install / update

    /// Downloads the release, verifies it against SHA256SUMS, copies it into the game folder, runs install_macos.sh.
    /// `zip` installs a local bundle zip instead (no download, no checksum). `onlyIfNewer` makes it an update.
    public static func install(kit: Kit, version: String? = nil, zip: URL? = nil, onlyIfNewer: Bool = false) async throws -> LoaderReport {
        try kit.requireGame()
        try kit.requireGameStopped()
        if let zip {
            return try installBundle(zip: zip, version: nil, kit: kit)
        }
        kit.log("Looking up RED4ext for macOS releases ...")
        let releases = try await GitHub.releases(repo, session: kit.session)
        guard let (release, found) = pick(releases, version: version) else {
            throw KitError(version.map { "There is no RED4ext for macOS release \($0)." } ?? "No RED4ext for macOS release found.",
                           hint: "See https://github.com/\(repo)/releases for the available versions.")
        }
        let name = "RED4ext-macOS-arm64-\(found).zip"
        if onlyIfNewer, let installed = installedVersion(kit).flatMap(ReleaseVersion.init), installed >= found {
            return LoaderReport(action: "update", version: installed.description, files: 0, output: nil, warnings: [],
                                nextStep: "Already up to date (\(installed)). Start the game: cybermod play", dryRun: kit.dryRun)
        }
        guard let asset = release.assets.first(where: { $0.name == name }) else {
            throw KitError("Release \(release.tag_name) has no \(name).", hint: "Pick another version: cybermod install --version X.Y.Z")
        }
        // SHA256SUMS; older releases have <zip>.sha256 in the same format.
        guard let sums = release.assets.first(where: { $0.name == "SHA256SUMS" }) ?? release.assets.first(where: { $0.name == name + ".sha256" })
        else {
            throw KitError("Release \(release.tag_name) has no SHA256SUMS, so the download cannot be verified.",
                           hint: "Pick another version (cybermod install --version X.Y.Z) or report it at https://github.com/\(repo)/issues")
        }

        let temp = try FileOps.tempDir()
        defer { try? FileManager.default.removeItem(at: temp) }
        let sumsFile = try await HTTP.download(sums.browser_download_url, to: temp, kit: kit)
        let file = try await HTTP.download(asset.browser_download_url, to: temp, kit: kit)
        guard let expected = Checksum.parseSums(try String(contentsOf: sumsFile, encoding: .utf8))[name] else {
            throw KitError("\(sums.name) does not list \(name).", hint: "Report it at https://github.com/\(repo)/issues. Nothing was installed.")
        }
        try Checksum.verify(file, expected: expected)
        kit.log("Checksum OK.")
        var report = try installBundle(zip: file, version: found.description, kit: kit)
        report.action = onlyIfNewer ? "update" : "install"
        return report
    }

    /// Unpacks a bundle zip (one top-level folder whose contents go into the game folder), checks it was made for
    /// this game build, copies it all-or-nothing, removes files of the previous bundle it no longer has, then runs
    /// `red4ext/macos/scripts/install_macos.sh` (UUID check, backup, re-sign).
    static func installBundle(zip: URL, version: String?, kit: Kit) throws -> LoaderReport {
        let fm = FileManager.default
        let temp = try FileOps.tempDir()
        defer { try? fm.removeItem(at: temp) }
        try FileOps.unpack(zip, into: temp)
        let top = (try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)).filter {
            !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX"
        }
        guard top.count == 1, let root = top.first, fm.fileExists(atPath: root.appendingPathComponent("launch_red4ext.sh").path),
              fm.fileExists(atPath: root.appendingPathComponent("red4ext/macos/scripts/install_macos.sh").path) else {
            throw KitError("\(zip.lastPathComponent) is not a RED4ext for macOS release zip.",
                           hint: "Use a RED4ext-macOS-arm64-<version>.zip from https://github.com/\(repo)/releases")
        }
        let version = version ?? (try? String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? root.lastPathComponent.replacingOccurrences(of: "RED4ext-macOS-arm64-", with: "")

        // install_macos.sh refuses a mismatched build too, but only after the copy; check first so nothing changes.
        let db = AddressDB(root.appendingPathComponent("red4ext/bin/x64/cyberpunk2077_addresses.json"))
        let game = MachO.uuid(kit.gameBinary)
        if let db, db.uuid != game {
            throw KitError("RED4ext \(version) supports game build \(db.uuid)\(db.gameVersion.map { " (\($0))" } ?? ""), "
                           + "but your game is build \(game ?? "unknown").",
                           hint: "Install the release made for your game version (cybermod install --version X.Y.Z, see "
                               + "https://github.com/\(repo)/releases), or wait for one after a game patch. Nothing was changed.")
        }

        let files = FileOps.files(in: root)
        var warnings: [String] = []
        let previous = record(kit)
        if kit.dryRun {
            return LoaderReport(action: "install", version: version, files: files.count, output: nil, warnings: warnings,
                                nextStep: "Run without --dry-run to install.", dryRun: true)
        }
        try checkCancelled()
        kit.log("Copying \(files.count) files into \(kit.game.path) ...")
        try FileOps.install(files.map { (root.appendingPathComponent($0), kit.game.appendingPathComponent($0)) })

        if let previous {
            let current = Set(files.map { $0.lowercased() })
            let owned = Set(ModStore(kit: kit).owners().keys)
            for old in previous.files where !current.contains(old.lowercased()) && !owned.contains(old.lowercased()) {
                let url = kit.game.appendingPathComponent(old)
                try? fm.removeItem(at: url)
                FileOps.pruneEmpty(url.deletingLastPathComponent(), below: kit.game)
            }
        }
        try FileOps.writeJSON(BundleRecord(version: version, files: files, installedAt: Date()), to: recordURL(kit))

        kit.log("Running install_macos.sh (checks the game build, backs up and re-signs the game binary) ...")
        let setup = try Process.capture("/bin/bash", [kit.setupScript.path], cwd: kit.game)
        guard setup.status == 0 else {
            throw KitError("RED4ext \(version) was copied, but install_macos.sh failed.",
                           hint: "Read its output above, fix the cause and run `cybermod install` again; `cybermod doctor` "
                               + "shows the state and `cybermod uninstall` undoes the install.",
                           details: setup.output.split(separator: "\n").map(String.init))
        }
        if !Process.isRunning("steam_osx") { warnings.append("Steam is not running: start it and sign in before playing, or saves are missing.") }
        return LoaderReport(action: "install", version: version, files: files.count, output: setup.output, warnings: warnings,
                            nextStep: "Start the game with mods: cybermod play", dryRun: false)
    }

    // MARK: Uninstall

    /// Files a bundle installs, for installs made without cybermod (no record).
    static let knownBundlePaths = ["launch_red4ext.sh", "VERSION", "BUILD_INFO.json", "INSTALL_MACOS.md", "red4ext/RED4ext.dylib",
                                   "red4ext/bin", "red4ext/macos", "red4ext/plugins/ArchiveXL", "red4ext/plugins/TweakXL",
                                   "red4ext/plugins/ModMenu", "r6/input/tweakxl.xml", "r6/input/modmenu.xml"]

    /// Removes the bundle's files (never files of installed mods) and puts the original game binary back from
    /// Cyberpunk2077.orig when it is the same game build.
    public static func uninstall(kit: Kit) throws -> LoaderReport {
        let fm = FileManager.default
        try kit.requireGame()
        try kit.requireGameStopped()
        let owned = Set(ModStore(kit: kit).owners().keys)
        let paths = record(kit)?.files ?? knownBundlePaths.flatMap { path -> [String] in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: kit.game.appendingPathComponent(path).path, isDirectory: &isDir) else { return [] }
            return isDir.boolValue ? FileOps.files(in: kit.game.appendingPathComponent(path)).map { "\(path)/\($0)" } : [path]
        }
        let files = paths.filter { !owned.contains($0.lowercased()) && fm.fileExists(atPath: kit.game.appendingPathComponent($0).path) }
        guard !files.isEmpty || fm.fileExists(atPath: kit.binaryBackup.path) else {
            throw KitError("RED4ext is not installed in \(kit.game.path).", hint: "Nothing to do. To install it: cybermod install")
        }

        var warnings: [String] = []
        let restore = fm.fileExists(atPath: kit.binaryBackup.path)
        let sameBuild = MachO.uuid(kit.binaryBackup) == MachO.uuid(kit.gameBinary)
        if restore && !sameBuild {
            warnings.append("Cyberpunk2077.orig is from another game build, so it was not restored. Steam > Cyberpunk 2077 > "
                            + "Properties > Installed Files > Verify integrity restores the original game binary.")
        }
        if kit.dryRun {
            return LoaderReport(action: "uninstall", version: installedVersion(kit), files: files.count, output: nil,
                                warnings: warnings, nextStep: "Run without --dry-run to uninstall.", dryRun: true)
        }
        let version = installedVersion(kit)
        for file in files {
            let url = kit.game.appendingPathComponent(file)
            try fm.removeItem(at: url)
            FileOps.pruneEmpty(url.deletingLastPathComponent(), below: kit.game)
        }
        if restore && sameBuild {
            _ = try fm.replaceItemAt(kit.gameBinary, withItemAt: kit.binaryBackup)
            kit.log("Restored the original game binary from Cyberpunk2077.orig.")
        }
        try? fm.removeItem(at: recordURL(kit))
        return LoaderReport(action: "uninstall", version: version, files: files.count, output: nil, warnings: warnings,
                            nextStep: "Start the game from Steam as usual. Your mods were left in place (cybermod mod list).",
                            dryRun: false)
    }
}

// MARK: - Game binary

public enum MachO {
    /// LC_UUID of a thin 64-bit Mach-O as uppercase hex without dashes (as install_macos.sh prints it).
    // ponytail: thin binaries only, like install_macos.sh; the game ships arm64-only.
    public static func uuid(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 32), header.count == 32, header.u32(0) == 0xFEEDFACF else { return nil }
        let count = Int(header.u32(16)), size = Int(header.u32(20))
        guard size < 16 << 20, let commands = try? handle.read(upToCount: size), commands.count == size else { return nil }
        var offset = 0
        for _ in 0..<count where offset + 8 <= size {
            let (cmd, cmdSize) = (commands.u32(offset), Int(commands.u32(offset + 4)))
            if cmd == 0x1B, offset + 24 <= size {
                return commands[commands.startIndex + offset + 8 ..< commands.startIndex + offset + 24]
                    .map { String(format: "%02X", $0) }.joined()
            }
            guard cmdSize > 0 else { return nil }
            offset += cmdSize
        }
        return nil
    }

    /// Whether the binary carries RED4ext's entitlements (install_macos.sh re-signed it).
    public static func isResigned(_ url: URL) -> Bool {
        let result = try? Process.capture("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", url.path])
        return result?.output.contains("allow-unsigned-executable-memory") ?? false
    }
}

/// red4ext/bin/x64/cyberpunk2077_addresses.json: the game build the addresses were verified against.
public struct AddressDB {
    public var uuid: String
    public var gameVersion: String?

    public init?(_ url: URL) {
        struct File: Decodable { var uuid: String; var game_version: String? }
        guard let data = FileManager.default.contents(atPath: url.path), let file = try? JSONDecoder().decode(File.self, from: data)
        else { return nil }
        uuid = file.uuid.replacingOccurrences(of: "-", with: "").uppercased()
        gameVersion = file.game_version
    }
}

extension Data {
    func u32(_ offset: Int) -> UInt32 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) } }
    func u64(_ offset: Int) -> UInt64 { withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) } }
}
