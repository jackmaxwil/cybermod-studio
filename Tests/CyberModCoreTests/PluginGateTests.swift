import XCTest
@testable import CyberModCore

final class PluginGateTests: XCTestCase {

    // MARK: - Synthetic Mach-O

    private func le(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
    private func le(_ v: UInt64) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
    private func name16(_ s: String) -> [UInt8] { Array(s.utf8) + [UInt8](repeating: 0, count: 16 - s.utf8.count) }

    private func movz(_ rd: UInt32, _ imm: UInt32, hw: UInt32 = 0) -> UInt32 { 0x5280_0000 | hw << 21 | imm << 5 | rd }
    private func movk(_ rd: UInt32, _ imm: UInt32, hw: UInt32 = 1) -> UInt32 { 0x7280_0000 | hw << 21 | imm << 5 | rd }
    private func movn(_ rd: UInt32, _ imm: UInt32) -> UInt32 { 0x1280_0000 | imm << 5 | rd }

    /// Thin 64-bit Mach-O with one LC_SEGMENT_64 holding the given (segment, section, words) sections.
    private func machO(_ sections: [(String, String, [UInt32])], sectionOffsetOverride: UInt32? = nil) -> Data {
        let headerSize = 32, segSize = 72 + 80 * sections.count
        var payload: [UInt8] = []
        var sects: [UInt8] = []
        for (seg, sect, words) in sections {
            let offset = sectionOffsetOverride ?? UInt32(headerSize + segSize + payload.count)
            sects += name16(sect) + name16(seg) + le(UInt64(0)) + le(UInt64(words.count * 4)) + le(offset)
            sects += [UInt8](repeating: 0, count: 80 - 52)
            payload += words.flatMap { le($0) }
        }
        var out = le(UInt32(0xFEED_FACF)) + le(UInt32(0x0100_000C)) + le(UInt32(0)) + le(UInt32(6))
        out += le(UInt32(1)) + le(UInt32(segSize)) + le(UInt32(0)) + le(UInt32(0))
        out += le(UInt32(0x19)) + le(UInt32(segSize)) + name16("") + [UInt8](repeating: 0, count: 64 - 24)
        out += le(UInt32(sections.count)) + le(UInt32(0))
        return Data(out + sects + payload)
    }

    func testCollectsMovPairsMovnAndDataWords() throws {
        let data = machO([
            ("__TEXT", "__text", [
                movz(1, 0x5678), movz(2, 0xAAAA), movk(1, 0x1234),  // x1 = 0x12345678, interleaved
                movk(3, 0xBEEF),                                    // no pending MOVZ on x3
                movz(4, 0x1111, hw: 1),                             // MOVZ hw1 is not a low half
                movn(5, 0x0001),                                    // ~1
            ]),
            ("__DATA_CONST", "__const", [0xCAFE_BABE]),
            ("__DATA", "__bss", [0x0BAD_F00D]),                     // not scanned
        ])
        let c = try XCTUnwrap(PluginGate.collectConstants(data))
        XCTAssertTrue(c.isSuperset(of: [0x1234_5678, 0x5678, 0xAAAA, 0xFFFF_FFFE, 0xCAFE_BABE]))
        XCTAssertFalse(c.contains(0xBEEF_0000))
        XCTAssertFalse(c.contains(0x0BAD_F00D))
        XCTAssertFalse(c.contains(0x1111))
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(PluginGate.collectConstants(Data()))
        XCTAssertNil(PluginGate.collectConstants(Data([0xCA, 0xFE, 0xBA, 0xBE] + [UInt8](repeating: 0, count: 60))))
        let good = machO([("__TEXT", "__text", [movz(0, 1)])])
        XCTAssertNil(PluginGate.collectConstants(good.prefix(40)))   // truncated load command
        // A section pointing past the end of the file is skipped, not read.
        let outOfFile = machO([("__DATA", "__data", [0x1234_5678])], sectionOffsetOverride: 0xFFFF_FF00)
        XCTAssertEqual(PluginGate.collectConstants(outOfFile), [])
    }

    // MARK: - Gate

    func testEvaluateSkipsRefusedPlugins() throws {
        let fm = FileManager.default
        let game = fm.temporaryDirectory.appendingPathComponent("PluginGateTests-\(UUID())")
        defer { try? fm.removeItem(at: game) }
        let red4ext = game.appendingPathComponent("red4ext")

        func plugin(_ name: String, _ code: [UInt32], dylib: Bool = true) throws {
            let dir = red4ext.appendingPathComponent("plugins/\(name)")
            try fm.createDirectory(at: dir.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
            if dylib { try machO([("__TEXT", "__text", code)]).write(to: dir.appendingPathComponent("\(name).dylib")) }
        }
        // 0x00100001 = 1048577 (verified), 0x00200002 = 2097154 (unverified)
        try plugin("Good", [movz(0, 0x0001), movk(0, 0x0010)])
        try plugin("Unverified", [movz(0, 0x0002), movk(0, 0x0020)])
        try plugin("Ignored", [])
        try plugin("NoDylib", [], dylib: false)
        try fm.createDirectory(at: red4ext.appendingPathComponent("bin/x64"), withIntermediateDirectories: true)
        try #"{"Addresses": [{"hash": "1048577", "verified": true}, {"hash": "2097154"}]}"#
            .write(to: red4ext.appendingPathComponent("bin/x64/cyberpunk2077_addresses.json"), atomically: true, encoding: .utf8)
        try "[plugins]\nignored = [\"Ignored\"]\n"
            .write(to: red4ext.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)

        let result = PluginGate.evaluate(gamePath: game)
        XCTAssertEqual(result.allowed.map(\.lastPathComponent), ["Good"])
        let skipped = Dictionary(uniqueKeysWithValues: result.skipped)
        XCTAssertEqual(Set(skipped.keys), ["Unverified", "Ignored", "NoDylib"])
        XCTAssertTrue(skipped["Unverified"]!.contains("2097154"))
        XCTAssertTrue(skipped["Ignored"]!.contains("ignored"))

        // Without the address DB nothing is staged.
        try fm.removeItem(at: red4ext.appendingPathComponent("bin"))
        XCTAssertEqual(PluginGate.evaluate(gamePath: game).allowed, [])
    }
}

final class GameLauncherTests: XCTestCase {
    func testErrorBlocksKeepErrorLinesAndThreeAfter() {
        let out = "[INFO] start\n[ERROR - x.reds:1] bad\n a\n b\n c\n d\n[WARNING] w\n[ERROR - y.reds:2] worse\n e\nCompilation failed"
        XCTAssertEqual(GameLauncher.errorBlocks(out),
                       "[ERROR - x.reds:1] bad\n a\n b\n c\n[ERROR - y.reds:2] worse\n e\nCompilation failed")
        XCTAssertEqual(GameLauncher.errorBlocks("Compilation failed"), "")
    }
}
