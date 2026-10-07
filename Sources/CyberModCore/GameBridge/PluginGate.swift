// PluginGate.swift - Which red4ext plugins the loader will refuse, so their Scripts are not compiled in

import Foundation
import TOMLKit

/// Mirrors RED4ext's macOS plugin gate (src/dll/Systems/PluginSystem.cpp, src/dll/Platform/PluginRequirements.cpp,
/// RED4ext.SDK/scripts/plugin_requirements.py). Compiling the Scripts of a refused plugin makes the game fail with
/// "Failed to initialize scripts data!", because the natives they declare are never registered.
public enum PluginGate {

    public struct Result: Sendable {
        /// Plugin folders whose Scripts are safe to stage.
        public var allowed: [URL] = []
        /// Plugin folder name -> why its Scripts were not staged.
        public var skipped: [(name: String, reason: String)] = []
    }

    /// Splits red4ext/plugins/* folders that have a Scripts directory into allowed and skipped.
    public static func evaluate(gamePath: URL) -> Result {
        let fm = FileManager.default
        let red4ext = gamePath.appendingPathComponent("red4ext")
        let (enabled, ignored) = loadConfig(red4ext.appendingPathComponent("config.ini"))
        let db = try? loadAddressDB(red4ext.appendingPathComponent("bin/x64/cyberpunk2077_addresses.json"))

        var result = Result()
        let folders = (try? fm.contentsOfDirectory(at: red4ext.appendingPathComponent("plugins"),
                                                   includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.appendingPathComponent("Scripts").path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let name = folder.lastPathComponent
            if let reason = refusal(folder: folder, enabled: enabled, ignored: ignored, db: db) {
                result.skipped.append((name, reason))
            } else {
                result.allowed.append(folder)
            }
        }
        return result
    }

    private static func refusal(folder: URL, enabled: Bool, ignored: Set<String>, db: [UInt32: Bool]?) -> String? {
        guard enabled else { return "plugins are disabled in red4ext/config.ini" }
        let dylibs = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "dylib" }
        guard !dylibs.isEmpty else { return "no plugin dylib in the folder" }
        let names = [folder.lastPathComponent] + dylibs.map { $0.deletingPathExtension().lastPathComponent }
        if let name = names.first(where: ignored.contains) { return "'\(name)' is ignored in red4ext/config.ini" }
        guard let db else { return "address DB red4ext/bin/x64/cyberpunk2077_addresses.json is missing or unreadable" }
        for dylib in dylibs {
            let file = dylib.lastPathComponent
            guard let data = try? Data(contentsOf: dylib), let constants = collectConstants(data) else {
                return "\(file) is not a thin 64-bit Mach-O"
            }
            let unverified = constants.filter { db[$0] == false }.sorted()
            if !unverified.isEmpty {
                return "\(file) uses \(unverified.count) unverified address(es): "
                    + unverified.map(String.init).joined(separator: ", ")
            }
        }
        return nil
    }

    // MARK: - red4ext/config.ini

    /// ([plugins] enabled, [plugins] ignored). A missing or unparsable file gives the loader's defaults.
    static func loadConfig(_ url: URL) -> (enabled: Bool, ignored: Set<String>) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let plugins = (try? TOMLTable(string: text))?["plugins"] else { return (true, []) }
        let ignored = plugins["ignored"]?.array?.compactMap { $0.string } ?? []
        return (plugins["enabled"]?.bool ?? true, Set(ignored))
    }

    // MARK: - Address DB

    /// hash -> verified, from cyberpunk2077_addresses.json (`{"Addresses": [{"hash": "123", "verified": true}]}`).
    static func loadAddressDB(_ url: URL) throws -> [UInt32: Bool] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        guard let entries = json?["Addresses"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }
        var db: [UInt32: Bool] = [:]
        for entry in entries {
            let hash: UInt32?
            switch entry["hash"] {
            case let s as String: hash = UInt32(s)
            case let n as NSNumber: hash = UInt32(exactly: n.int64Value)
            default: hash = nil
            }
            if let hash { db[hash] = entry["verified"] as? Bool == true }
        }
        return db
    }

    // MARK: - Mach-O constants

    /// 32-bit constants a thin arm64 Mach-O can materialize (MOVZ hw0 + MOVK hw1 pairs, MOVZ hw0, MOVN hw0) or
    /// holds as aligned words in __TEXT,__const/__literal4, __DATA_CONST,__const and __DATA,__data.
    /// Returns nil if the data is not a thin 64-bit Mach-O whose load commands parse within bounds.
    public static func collectConstants(_ data: Data) -> Set<UInt32>? {
        let bytes = [UInt8](data)
        guard u32(bytes, 0) == 0xFEED_FACF, let ncmds = u32(bytes, 16) else { return nil }

        var constants = Set<UInt32>()
        var offset = 32  // sizeof(mach_header_64)
        for _ in 0..<ncmds {
            guard let cmd = u32(bytes, offset), let cmdsize = u32(bytes, offset + 4), cmdsize >= 8 else { return nil }
            if cmd == 0x19 {  // LC_SEGMENT_64
                guard offset + 72 <= bytes.count, let nsects = u32(bytes, offset + 64) else { return nil }
                for s in 0..<Int(nsects) {
                    let sect = offset + 72 + s * 80  // sizeof(segment_command_64), sizeof(section_64)
                    guard sect + 80 <= bytes.count, let size64 = u64(bytes, sect + 40),
                          let fileOffset = u32(bytes, sect + 48) else { return nil }
                    // Zerofill or out of file.
                    guard let size = Int(exactly: size64), Int(fileOffset) <= bytes.count,
                          bytes.count - Int(fileOffset) >= size else { continue }
                    let range = Int(fileOffset)..<(Int(fileOffset) + size)
                    switch (name(bytes, sect + 16), name(bytes, sect)) {
                    case ("__TEXT", "__text"):
                        scanCode(bytes, range, into: &constants)
                    case ("__TEXT", "__const"), ("__TEXT", "__literal4"), ("__DATA_CONST", "__const"),
                         ("__DATA", "__data"):
                        for i in stride(from: range.lowerBound, through: range.upperBound - 4, by: 4) {
                            constants.insert(u32(bytes, i)!)
                        }
                    default:
                        break
                    }
                }
            }
            offset += Int(cmdsize)
        }
        return constants
    }

    private static func scanCode(_ bytes: [UInt8], _ range: Range<Int>, into out: inout Set<UInt32>) {
        var pending = [UInt32?](repeating: nil, count: 32)  // register -> low half from MOVZ
        for i in stride(from: range.lowerBound, through: range.upperBound - 4, by: 4) {
            let w = u32(bytes, i)!
            let rd = Int(w & 31), imm = (w >> 5) & 0xFFFF, hw = (w >> 21) & 3
            switch w & 0x7F80_0000 {
            case 0x5280_0000 where hw == 0:  // MOVZ
                pending[rd] = imm
                out.insert(imm)
            case 0x7280_0000 where hw == 1:  // MOVK
                if let low = pending[rd] {
                    out.insert(low | imm << 16)
                    pending[rd] = nil
                }
            case 0x1280_0000 where hw == 0:  // MOVN
                out.insert(~imm)
            default:
                break
            }
        }
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32? {
        guard o >= 0, o <= b.count - 4 else { return nil }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    private static func u64(_ b: [UInt8], _ o: Int) -> UInt64? {
        guard let lo = u32(b, o), let hi = u32(b, o + 4) else { return nil }
        return UInt64(lo) | UInt64(hi) << 32
    }

    /// NUL-padded 16-byte name; caller has bounds-checked the section header.
    private static func name(_ b: [UInt8], _ o: Int) -> String {
        String(decoding: b[o..<o + 16].prefix { $0 != 0 }, as: UTF8.self)
    }
}
