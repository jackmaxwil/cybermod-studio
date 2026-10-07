// Registry.swift - the community mod index (docs/REGISTRY.md): `registry:<id>` sources and `cybermod search`.

import Foundation

public struct RegistryEntry: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var author: String?
    public var description: String?
    /// https://..., github:owner/repo[@tag] or nexus:<mod>[/<file>]
    public var source: String
    /// SHA-256 of the downloaded file. Required for https:// sources.
    public var sha256: String?
    /// Registry ids, or the frameworks "red4ext", "archivexl", "tweakxl".
    public var requires: [String]?
}

public struct RegistryIndex: Codable, Equatable, Sendable {
    public var schema: Int
    public var mods: [RegistryEntry]

    /// Decodes and validates an index; every problem is reported at once.
    public static func parse(_ data: Data) throws -> RegistryIndex {
        let index: RegistryIndex
        do { index = try JSONDecoder().decode(RegistryIndex.self, from: data) } catch {
            throw KitError("The mod registry is not a valid index.", hint: "Check registry.url (`cybermod config get registry.url`).",
                           details: ["\(error)"])
        }
        guard index.schema == 1 else {
            throw KitError("The mod registry uses schema \(index.schema); this cybermod understands schema 1.",
                           hint: "Update cybermod.")
        }
        var problems: [String] = []
        var ids = Set<String>()
        for mod in index.mods {
            if mod.id != ModStore.slug(mod.id) { problems.append("\(mod.id): id must be lowercase letters, digits and dashes") }
            if !ids.insert(mod.id).inserted { problems.append("\(mod.id): duplicate id") }
            if let sha = mod.sha256, sha.count != 64 || !sha.allSatisfy(\.isHexDigit) { problems.append("\(mod.id): sha256 must be 64 hex digits") }
            switch try? ModSource.parse(mod.source) {
            case .url?: if mod.sha256 == nil { problems.append("\(mod.id): https sources need sha256") }
            case .github?, .nexus?: break
            default: problems.append("\(mod.id): source must be https://, github: or nexus:")
            }
        }
        guard problems.isEmpty else {
            throw KitError("The mod registry has invalid entries.", hint: "Tell the registry maintainers.", details: problems)
        }
        return index
    }

    public func entry(_ id: String) -> RegistryEntry? {
        mods.first { $0.id == id.lowercased() }
    }

    /// Entries whose id, name, author or description contain every word of `text` (case-insensitive).
    public func search(_ text: String) -> [RegistryEntry] {
        let words = text.lowercased().split(separator: " ")
        return mods.filter { mod in
            let haystack = [mod.id, mod.name, mod.author ?? "", mod.description ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

public enum Registry {
    /// The index at `registry.url` (https:// or file://).
    public static func load(kit: Kit) async throws -> RegistryIndex {
        guard let value = Config(home: kit.home).values["registry.url"], let url = URL(string: value),
              url.scheme == "https" || url.isFileURL else {
            throw KitError("No mod registry configured.",
                           hint: "Set its address: cybermod config set registry.url https://.../index.json "
                               + "(docs/REGISTRY.md describes the format).")
        }
        let data: Data
        if url.isFileURL {
            guard let local = FileManager.default.contents(atPath: url.path) else {
                throw KitError("Cannot read the registry file \(url.path).", hint: "Check registry.url.")
            }
            data = local
        } else {
            data = try await HTTP.get(url, session: kit.session)
        }
        return try RegistryIndex.parse(data)
    }
}
