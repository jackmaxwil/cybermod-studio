// Sources.swift - what `cybermod mod add` accepts, and turning it into an unpacked mod folder.

import Foundation

public enum ModSource: Equatable, CustomStringConvertible {
    case local(URL)
    case url(URL)
    /// `repo` is "owner/name".
    case github(repo: String, tag: String?)
    case nexus(mod: Int, file: Int?)
    /// A "Mod Manager Download" link from the Nexus Mods website (works without Premium).
    case nxm(mod: Int, file: Int, key: String, expires: Int)
    case registry(String)

    static let usage = "Use a file or folder path, an https:// URL, github:owner/repo[@tag], nexus:<mod id>[/<file id>], "
        + "an nxm:// link or registry:<name>."

    public static func parse(_ input: String) throws -> ModSource {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        func bad(_ what: String) -> KitError { KitError("Not a valid mod source: \(what)", hint: usage) }

        if lower.hasPrefix("github:") {
            let parts = text.dropFirst(7).split(separator: "@", maxSplits: 1).map(String.init)
            guard let repo = parts.first, repo.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
            else { throw bad(text) }
            return .github(repo: repo, tag: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
        }
        if lower.hasPrefix("nexus:") {
            let parts = text.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), let mod = Int(parts[0]), mod > 0 else { throw bad(text) }
            guard parts.count == 1 else {
                guard let file = Int(parts[1]), file > 0 else { throw bad(text) }
                return .nexus(mod: mod, file: file)
            }
            return .nexus(mod: mod, file: nil)
        }
        if lower.hasPrefix("nxm://") {
            guard let url = URLComponents(string: text) else { throw bad("the nxm:// link (put it in quotes)") }
            guard url.host?.lowercased() == "cyberpunk2077" else {
                throw KitError("This nxm:// link is for another game (\(url.host ?? "?")).", hint: "Use a Cyberpunk 2077 mod link.")
            }
            let path = url.path.split(separator: "/")
            let query = Dictionary((url.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard path.count == 4, path[0] == "mods", path[2] == "files", let mod = Int(path[1]), let file = Int(path[3]),
                  let key = query["key"], !key.isEmpty, let expires = query["expires"].flatMap(Int.init) else {
                throw KitError("Incomplete nxm:// link.",
                               hint: "Copy the whole link, including ?key=...&expires=..., and put it in single quotes.")
            }
            return .nxm(mod: mod, file: file, key: key, expires: expires)
        }
        if lower.hasPrefix("registry:") {
            let name = String(text.dropFirst(9))
            guard !name.isEmpty else { throw bad(text) }
            return .registry(name)
        }
        if lower.hasPrefix("http://") {
            throw KitError("Plain http:// downloads are not allowed.", hint: "Use the https:// address of the file.")
        }
        if lower.hasPrefix("https://") {
            guard let url = URL(string: text), let host = url.host?.lowercased() else { throw bad(text) }
            let path = url.path.split(separator: "/").map(String.init)
            // Mod pages pasted from the browser.
            if host.hasSuffix("nexusmods.com"), path.count >= 3, path[0].lowercased() == "cyberpunk2077", path[1] == "mods",
               let mod = Int(path[2]) {
                let file = URLComponents(string: text)?.queryItems?.first { $0.name == "file_id" }?.value.flatMap(Int.init)
                return .nexus(mod: mod, file: file)
            }
            if host == "github.com", path.count == 2 || (path.count == 5 && path[2] == "releases" && path[3] == "tag") {
                return .github(repo: "\(path[0])/\(path[1])", tag: path.count == 5 ? path[4] : nil)
            }
            return .url(url)
        }
        let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KitError("No such file or folder: \(text)", hint: usage)
        }
        return .local(url)
    }

    /// How the source is recorded in the manifest (never includes an nxm key).
    public var description: String {
        switch self {
        case .local(let url): return url.path
        case .url(let url): return url.absoluteString
        case .github(let repo, let tag): return "github:\(repo)" + (tag.map { "@\($0)" } ?? "")
        case .nexus(let mod, let file): return "nexus:\(mod)" + (file.map { "/\($0)" } ?? "")
        case .nxm(let mod, let file, _, _): return "nexus:\(mod)/\(file)"
        case .registry(let name): return "registry:\(name)"
        }
    }
}

/// A mod unpacked and ready for `ModStore.install`.
public struct Fetched {
    public var stage: URL
    public var name: String
    public var id: String?
    public var version: String?
    public var source: String
    public var requires: [String] = []
    var temp: URL?

    public func cleanup() {
        if let temp { try? FileManager.default.removeItem(at: temp) }
    }

    /// "Cool Mod-1234-1-2-1699999999.zip" -> "Cool Mod" (Nexus download names end in -<mod id>-<version>-<time>).
    public static func modName(fromFile file: String) -> String {
        var base = file
        for ext in [".zip", ".7z", ".rar", ".archive.xl", ".archive", ".xl", ".reds", ".yaml", ".yml", ".tweak"]
        where base.lowercased().hasSuffix(ext) {
            base = String(base.dropLast(ext.count))
            break
        }
        if let range = base.range(of: #"-\d+(-[0-9A-Za-z]+)*-\d{9,}$"#, options: .regularExpression) {
            base = String(base[..<range.lowerBound])
        }
        return base.isEmpty ? file : base
    }
}

extension ModSource {
    /// Downloads (if needed), verifies `sha256` when given, and unpacks.
    public func fetch(kit: Kit, sha256: String? = nil) async throws -> Fetched {
        switch self {
        case .local(let url):
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { return Fetched(stage: url, name: url.lastPathComponent, source: description) }
            let temp = try FileOps.tempDir()
            do {
                if let sha256 { try Checksum.verify(url, expected: sha256) }
                try FileOps.unpack(url, into: temp.appendingPathComponent("unpacked"))
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw error
            }
            return Fetched(stage: temp.appendingPathComponent("unpacked"), name: Fetched.modName(fromFile: url.lastPathComponent),
                           source: description, temp: temp)

        case .url(let url):
            return try await Self.download(url, kit: kit, sha256: sha256, source: description)

        case .github(let repo, let tag):
            let releases = try await GitHub.releases(repo, session: kit.session)
            let release = tag == nil ? releases.first : releases.first { $0.tag_name == tag }
            if let tag, release == nil {
                throw KitError("\(repo) has no release \(tag).", hint: "See the releases at https://github.com/\(repo)/releases")
            }
            // No release, or no mod-looking asset: the source zip.
            let url = release.flatMap(GitHub.modAsset)?.browser_download_url ?? release?.zipball_url ?? GitHub.api("\(repo)/zipball")
            var fetched = try await Self.download(url, kit: kit, sha256: sha256, source: description)
            fetched.name = String(repo.split(separator: "/").last!)
            fetched.version = release?.tag_name
            return fetched

        case .nexus(let mod, let file):
            let key = try Nexus.key()
            let user = try await Nexus.validate(key: key, session: kit.session)
            let info = try await Nexus.mod(mod, key: key, session: kit.session)
            var fileID = file ?? 0
            if file == nil { fileID = try await Nexus.mainFile(mod, key: key, session: kit.session).file_id }
            guard user.is_premium else {
                let page = Nexus.filesPage(mod: mod, file: fileID)
                if !kit.dryRun { kit.openURL(page) }
                throw KitError(Nexus.premiumOnly,
                               hint: "Open \(page.absoluteString) (cybermod opened it in your browser), click \"Mod Manager "
                                   + "Download\", then \"Slow download\". When the browser offers to open an nxm:// link, "
                                   + "copy the link instead and run: cybermod mod add 'nxm://...'",
                               details: [page.absoluteString])
            }
            let link = try await Nexus.downloadLink(mod: mod, file: fileID, key: key, session: kit.session)
            var fetched = try await Self.download(link, kit: kit, sha256: sha256, source: "nexus:\(mod)/\(fileID)")
            fetched.name = info.name ?? fetched.name
            fetched.version = info.version
            return fetched

        case .nxm(let mod, let file, let linkKey, let expires):
            guard Date(timeIntervalSince1970: TimeInterval(expires)) > Date() else {
                throw KitError("This nxm:// link has expired.", hint: "Click \"Mod Manager Download\" on Nexus Mods again for a fresh link.")
            }
            let key = try Nexus.key()
            let info = try await Nexus.mod(mod, key: key, session: kit.session)
            let link = try await Nexus.downloadLink(mod: mod, file: file, key: key, nxm: (linkKey, expires), session: kit.session)
            var fetched = try await Self.download(link, kit: kit, sha256: sha256, source: description)
            fetched.name = info.name ?? fetched.name
            fetched.version = info.version
            return fetched

        case .registry(let id):
            let index = try await Registry.load(kit: kit)
            guard let entry = index.entry(id) else {
                throw KitError("\"\(id)\" is not in the mod registry.", hint: "Search it: cybermod search \(id)")
            }
            var fetched = try await ModSource.parse(entry.source).fetch(kit: kit, sha256: entry.sha256)
            fetched.name = entry.name
            fetched.id = entry.id
            fetched.version = entry.version
            fetched.source = description
            fetched.requires = entry.requires ?? []
            return fetched
        }
    }

    static func download(_ url: URL, kit: Kit, sha256: String?, source: String) async throws -> Fetched {
        let temp = try FileOps.tempDir()
        do {
            let file = try await HTTP.download(url, to: temp, kit: kit)
            if let sha256 { try Checksum.verify(file, expected: sha256) }
            try FileOps.unpack(file, into: temp.appendingPathComponent("unpacked"))
            return Fetched(stage: temp.appendingPathComponent("unpacked"), name: Fetched.modName(fromFile: file.lastPathComponent),
                           source: source, temp: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}

extension ModStore {
    /// Frameworks a registry entry can require; they come with `cybermod install`.
    static let frameworks = ["red4ext": "launch_red4ext.sh", "archivexl": "red4ext/plugins/ArchiveXL",
                             "tweakxl": "red4ext/plugins/TweakXL"]

    /// Fetches and installs a mod, first installing any registry mods it requires that are missing.
    /// `id` replaces that installed mod (an update); by default the id comes from the name.
    public func add(_ source: ModSource, name: String? = nil, id: String? = nil, force: Bool = false) async throws -> [InstallReport] {
        var seen = Set(list().map(\.id))
        return try await add(source, name: name, id: id, force: force, seen: &seen)
    }

    private func add(_ source: ModSource, name: String?, id: String? = nil, force: Bool, seen: inout Set<String>) async throws -> [InstallReport] {
        try kit.requireGame()
        kit.log("Getting \(source) ...")
        let fetched = try await source.fetch(kit: kit)
        defer { fetched.cleanup() }
        var reports: [InstallReport] = []
        var missing: [String] = []
        for requirement in fetched.requires {
            if let path = Self.frameworks[requirement.lowercased()] {
                if !FileManager.default.fileExists(atPath: kit.game.appendingPathComponent(path).path) { missing.append(requirement) }
            } else if seen.insert(requirement).inserted {
                reports += try await add(.registry(requirement), name: nil, force: force, seen: &seen)
            }
        }
        let warnings = missing.isEmpty ? [] : ["Requires \(missing.joined(separator: ", ")); run `cybermod install`."]
        return reports + [try install(from: fetched.stage, id: id ?? fetched.id, name: name ?? fetched.name, version: fetched.version,
                                      source: fetched.source, force: force, warnings: warnings)]
    }
}
