// Files.swift - checksums, unpacking, and all-or-nothing file moves.

import CryptoKit
import Foundation

public enum Checksum {
    /// SHA-256 of a file as lowercase hex.
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try checkCancelled()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Parses `shasum -a 256` output ("<hex>  <name>", or "<hex> *<name>" in binary mode) into name -> hex.
    public static func parseSums(_ text: String) -> [String: String] {
        var sums: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, parts[0].count == 64, parts[0].allSatisfy(\.isHexDigit) else { continue }
            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            sums[name] = parts[0].lowercased()
        }
        return sums
    }

    /// Throws unless the file's SHA-256 is `expected`.
    public static func verify(_ file: URL, expected: String) throws {
        let actual = try sha256(of: file)
        guard actual == expected.lowercased() else {
            throw KitError("Checksum mismatch for \(file.lastPathComponent): expected \(expected), got \(actual).",
                           hint: "The download is damaged or was changed. Run the command again; if it keeps failing, "
                               + "tell the publisher. Nothing was installed.")
        }
    }
}

enum FileOps {
    static let fm = FileManager.default

    /// Regular files under `dir` as sorted relative paths, without macOS metadata (__MACOSX, .DS_Store, ._*).
    static func files(in dir: URL) -> [String] {
        guard let walker = fm.enumerator(atPath: dir.path) else { return [] }
        var out: [String] = []
        while let rel = walker.nextObject() as? String {
            guard walker.fileAttributes?[.type] as? FileAttributeType == .typeRegular else { continue }
            let parts = rel.split(separator: "/")
            if parts.contains("__MACOSX") || parts.last == ".DS_Store" || parts.last!.hasPrefix("._") { continue }
            out.append(rel)
        }
        return out.sorted()
    }

    /// Copies every pair or none: each source is first copied next to its destination under a temporary name, then
    /// renamed over it (rename(2) replaces atomically). A failed copy removes the temporaries and created folders.
    // ponytail: a failure between two renames (disk vanished) leaves the earlier ones in place; journal if that matters.
    static func install(_ pairs: [(from: URL, to: URL)]) throws {
        var temps: [(URL, URL)] = []
        var created: [URL] = []
        do {
            for (from, to) in pairs {
                try checkCancelled()
                var dir = to.deletingLastPathComponent()
                while !fm.fileExists(atPath: dir.path) {
                    created.append(dir)
                    dir.deleteLastPathComponent()
                }
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                let tmp = to.deletingLastPathComponent().appendingPathComponent(".\(to.lastPathComponent).cybermod-\(UUID().uuidString)")
                try fm.copyItem(at: from, to: tmp)
                temps.append((tmp, to))
            }
        } catch {
            temps.forEach { try? fm.removeItem(at: $0.0) }
            created.sorted { $0.path.count > $1.path.count }.forEach { rmdir($0.path) }
            if let error = error as? KitError { throw error }
            throw KitError("Could not copy files: \(error.localizedDescription)",
                           hint: "Check free disk space and that you can write to the game folder. Nothing was changed.")
        }
        for (tmp, to) in temps {
            guard rename(tmp.path, to.path) == 0 else {
                throw KitError("Could not move \(to.lastPathComponent) into place: \(String(cString: strerror(errno)))",
                               hint: "Check that \(to.path) is not a folder and is writable, then run the command again.")
            }
            // Downloaded files can carry the quarantine flag; macOS then refuses to load plugin dylibs.
            removexattr(to.path, "com.apple.quarantine", 0)
        }
    }

    /// Moves every pair or none (moves already done are undone on failure).
    static func move(_ pairs: [(from: URL, to: URL)]) throws {
        var done: [(URL, URL)] = []
        do {
            for (from, to) in pairs {
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: from, to: to)
                done.append((from, to))
            }
        } catch {
            for (from, to) in done.reversed() { try? fm.moveItem(at: to, to: from) }
            throw KitError("Could not move files: \(error.localizedDescription)",
                           hint: "Nothing was changed. Check that the game folder is writable and the game is not running.")
        }
    }

    /// Mod folders that stay even when empty.
    static let keptFolders = ["archive/pc/mod", "r6/scripts", "r6/tweaks", "r6/input", "red4ext/plugins", "red4ext"]

    /// Removes empty folders from `dir` upward, stopping at `root` and at the kept mod folders.
    static func pruneEmpty(_ dir: URL, below root: URL) {
        let rootPath = root.standardizedFileURL.path
        var dir = dir.standardizedFileURL
        while dir.path.hasPrefix(rootPath + "/"),
              !keptFolders.contains(String(dir.path.dropFirst(rootPath.count + 1))),
              rmdir(dir.path) == 0 {
            dir.deleteLastPathComponent()
        }
    }

    /// Unpacks a .zip, .7z or .rar (recognised by content, not name) into `dir`. Any other file is copied into
    /// `dir` as-is, so a single loose .archive or .reds works too.
    static func unpack(_ file: URL, into dir: URL) throws {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let handle = try FileHandle(forReadingFrom: file)
        let magic = [UInt8]((try? handle.read(upToCount: 6)) ?? Data())
        try? handle.close()
        let name = file.lastPathComponent
        if magic.starts(with: [0x50, 0x4B, 0x03, 0x04]) || magic.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            let result = try Process.capture("/usr/bin/ditto", ["-x", "-k", file.path, dir.path])
            guard result.status == 0 else {
                throw KitError("Could not unpack \(name): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))",
                               hint: "The zip may be damaged. Download it again.")
            }
            return
        }
        let isSevenZip = magic.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
        let isRar = magic.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])
        guard isSevenZip || isRar else {
            try fm.copyItem(at: file, to: dir.appendingPathComponent(name))
            return
        }
        // Third-party unpackers first (they handle RAR5), then macOS's bsdtar (7z and older RAR).
        var tools: [(String, [String])] = []
        for tool in ["7zz", "7z", "7za"] { if let path = which(tool) { tools.append((path, ["x", "-y", "-o\(dir.path)", file.path])) } }
        if let path = which("unar") { tools.append((path, ["-q", "-f", "-o", dir.path, file.path])) }
        if isRar, let path = which("unrar") { tools.append((path, ["x", "-o+", "-idq", file.path, dir.path + "/"])) }
        tools.append(("/usr/bin/tar", ["-xf", file.path, "-C", dir.path]))
        for (tool, args) in tools where (try? Process.capture(tool, args).status) == 0 {
            return
        }
        throw KitError("Could not unpack \(name): no installed tool can read this \(isRar ? "RAR" : "7z") file.",
                       hint: "Install 7-Zip (`brew install sevenzip`) and run the command again, or unpack it in Finder "
                           + "and run `cybermod mod add <folder>`.")
    }

    static func which(_ tool: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"])
            .map { "\($0)/\(tool)" }
            .first { fm.isExecutableFile(atPath: $0) }
    }

    /// A fresh folder under the system temporary directory.
    static func tempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("cybermod-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSON.encoder.encode(value).write(to: url, options: .atomic)
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = fm.contents(atPath: url.path) else { return nil }
        return try? JSON.decoder.decode(type, from: data)
    }
}

public enum JSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
