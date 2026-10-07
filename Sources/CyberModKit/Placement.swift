// Placement.swift - where each file of a mod goes in the game folder on macOS.

import Foundation

public struct PlacedFile: Codable, Equatable {
    /// Path inside the unpacked mod.
    public var source: String
    /// Path inside the game folder.
    public var destination: String

    public init(_ source: String, _ destination: String) {
        self.source = source
        self.destination = destination
    }
}

/// The install plan for one unpacked mod.
///
/// - Known game roots anywhere in a path are kept (`MyMod/r6/scripts/X/a.reds` -> `r6/scripts/X/a.reds`), except
///   `archive/pc/mod`, which is flat: ArchiveXL loads only the archives directly in it.
/// - Loose files are placed by extension: `.archive`/`.xl` -> `archive/pc/mod/`, `.yaml`/`.yml`/`.tweak` ->
///   `r6/tweaks/`, `.reds` -> `r6/scripts/<ModName>/`, `.dylib` -> `red4ext/plugins/<Name>/`, `.xml` -> `r6/input/`.
/// - Windows-only content (`.dll`, `.asi`, `.exe`, Cyber Engine Tweaks Lua, anything under `bin/x64/`) is collected in
///   `windowsOnly`; a mod with any of it is refused, because the rest of it would not work without that part.
/// - Everything else (readmes, images, FOMOD metadata, other game folders such as `r6/config`) is `ignored`.
public struct Placement: Equatable {
    public var files: [PlacedFile] = []
    public var ignored: [String] = []
    public var windowsOnly: [String] = []

    static let keptRoots = ["r6/scripts/", "r6/tweaks/", "r6/input/", "red4ext/plugins/"]
    static let archiveRoot = "archive/pc/mod/"
    static let otherRoots = ["r6/", "archive/", "engine/", "red4ext/", "fomod/"]

    public static func plan(_ paths: [String], modName: String) -> Placement {
        var plan = Placement()
        var taken: [String: String] = [:]  // lowercased destination -> source (the Mac file system ignores case)
        let folder = modName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")

        for raw in paths {
            let path = raw.replacingOccurrences(of: "\\", with: "/")
            let lower = path.lowercased()
            let name = (path as NSString).lastPathComponent
            let lname = name.lowercased()
            let ext = (lname as NSString).pathExtension

            if ["dll", "asi", "exe", "lua"].contains(ext) || lower.contains("cyber_engine_tweaks/")
                || remainder(path, after: "bin/x64/") != nil {
                plan.windowsOnly.append(path)
                continue
            }

            let isArchive = ext == "archive" || ext == "xl"
            var destination: String?
            if remainder(path, after: archiveRoot) != nil {
                destination = isArchive ? archiveRoot + name : nil
            } else if let root = keptRoots.first(where: { remainder(path, after: $0) != nil }) {
                destination = root + remainder(path, after: root)!
            } else if otherRoots.contains(where: { remainder(path, after: $0) != nil }) {
                destination = nil  // a game folder macOS mods do not use (r6/config, archive/pc/patch, engine/)
            } else if isArchive {
                destination = archiveRoot + name
            } else if ["yaml", "yml", "tweak"].contains(ext) {
                destination = "r6/tweaks/" + name
            } else if ext == "reds" {
                destination = "r6/scripts/\(folder)/" + name
            } else if ext == "dylib" {
                destination = "red4ext/plugins/\((name as NSString).deletingPathExtension)/" + name
            } else if ext == "xml" {
                destination = "r6/input/" + name
            }

            guard let destination else {
                plan.ignored.append(path)
                continue
            }
            if let other = taken[destination.lowercased()] {
                plan.ignored.append("\(path) (same destination as \(other))")
                continue
            }
            taken[destination.lowercased()] = path
            plan.files.append(PlacedFile(raw, destination))
        }
        return plan
    }

    /// The part of `path` after `root` when `root` starts at a folder boundary (case-insensitive).
    static func remainder(_ path: String, after root: String) -> String? {
        let full = "/" + path
        guard let range = full.range(of: "/" + root, options: .caseInsensitive) else { return nil }
        let rest = String(full[range.upperBound...])
        return rest.isEmpty ? nil : rest
    }
}
