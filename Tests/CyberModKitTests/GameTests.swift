import XCTest
@testable import CyberModKit

final class RDARTests: XCTestCase {
    func testReadsFileTable() throws {
        let dir = try makeTree([:])
        defer { try? FileManager.default.removeItem(at: dir) }
        let hashes = [RDAR.fnv1a64("base\\a.mesh"), RDAR.fnv1a64("base\\b.xbm")]
        try writeRDAR(hashes, to: dir.appendingPathComponent("a.archive"))
        XCTAssertEqual(RDAR.fileHashes(dir.appendingPathComponent("a.archive")), hashes)
        try Data("not an archive".utf8).write(to: dir.appendingPathComponent("b.archive"))
        XCTAssertNil(RDAR.fileHashes(dir.appendingPathComponent("b.archive")))
        XCTAssertEqual(RDAR.fnv1a64(""), 0xCBF2_9CE4_8422_2325)
    }

    func testLoadOrderAndWinners() {
        // Upper-cased byte order, like Windows: "#" < digits < letters < "_".
        let names = ["zz.archive", "_last.archive", "Beta.archive", "alpha.archive", "#first.archive", "00.archive"]
        XCTAssertEqual(names.sorted(by: RDAR.loadsBefore),
                       ["#first.archive", "00.archive", "alpha.archive", "Beta.archive", "zz.archive", "_last.archive"])

        let conflicts = RDAR.conflicts([("a.archive", [1, 2, 3]), ("b.archive", [2, 3, 4]), ("c.archive", [3, 4, 5])])
        XCTAssertEqual(conflicts, [
            ArchiveConflict(winner: "a.archive", loser: "b.archive", files: 2),
            ArchiveConflict(winner: "a.archive", loser: "c.archive", files: 1),
            ArchiveConflict(winner: "b.archive", loser: "c.archive", files: 1),
        ])
    }

    func testDoctorFindsModProblems() throws {
        let fake = try FakeGame()
        defer { fake.cleanup() }
        let mod = fake.game.appendingPathComponent("archive/pc/mod")
        try writeRDAR([1, 2], to: mod.appendingPathComponent("Alpha.archive"))
        try writeRDAR([2, 3], to: mod.appendingPathComponent("beta.archive"))
        try writeRDAR([3, 2], to: mod.appendingPathComponent("Copy of beta.archive"))
        try writeRDAR([9], to: mod.appendingPathComponent("sub/beta.archive"))
        for path in ["archive/pc/content/wrong.xl", "r6/scripts/stray.archive.xl", "red4ext/plugins/WinThing/WinThing.dll",
                     "bin/x64/plugins/cyber_engine_tweaks/mods/m/init.lua"] {
            let url = fake.game.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }

        let report = Doctor.run(kit: fake.kit)
        let byCheck = Dictionary(grouping: report.findings, by: \.id)
        XCTAssertEqual(byCheck["red4ext"]?.first?.level, .error)
        XCTAssertEqual(byCheck["nested-archives"]?.first?.details, ["archive/pc/mod/sub/beta.archive"])
        XCTAssertEqual(byCheck["nested-archives"]?.first?.fix, "move-nested-archives")
        XCTAssertEqual(Set(byCheck["misplaced-xl"]?.first?.details ?? []), ["archive/pc/content/wrong.xl", "r6/scripts/stray.archive.xl"])
        XCTAssertEqual(byCheck["windows-mods"]?.first?.details?.count, 2)
        let duplicates = (byCheck["identical-archives"]?.first?.details ?? []) + (byCheck["duplicate-names"]?.first?.details ?? [])
        XCTAssertTrue(duplicates.contains("beta.archive = Copy of beta.archive"), "\(duplicates)")
        XCTAssertTrue(duplicates.contains("beta.archive = sub/beta.archive"), "\(duplicates)")
        XCTAssertNotNil(byCheck["archivexl"])
        // Load order: Alpha, beta, Copy of beta. Alpha wins file 2; beta wins file 3 over its copy.
        XCTAssertEqual(report.conflicts, [
            ArchiveConflict(winner: "Alpha.archive", loser: "beta.archive", files: 1),
            ArchiveConflict(winner: "Alpha.archive", loser: "Copy of beta.archive", files: 1),
            ArchiveConflict(winner: "beta.archive", loser: "Copy of beta.archive", files: 1),
        ])
        XCTAssertFalse(report.healthy)
    }
}

final class LoaderTests: XCTestCase {
    let uuid: [UInt8] = Array(100..<116)

    /// A RED4ext-macOS-arm64-<version>.zip whose address DB matches `dbUUID` and whose install_macos.sh only logs.
    func bundleZip(version: String, dbUUID: [UInt8], extra: [String: String] = [:]) throws -> URL {
        let folder = "RED4ext-macOS-arm64-\(version)"
        var files = [
            "\(folder)/VERSION": version,
            "\(folder)/launch_red4ext.sh": "#!/bin/bash\n",
            "\(folder)/red4ext/RED4ext.dylib": "dylib",
            "\(folder)/red4ext/plugins/TweakXL/TweakXL.dylib": "tweakxl",
            "\(folder)/r6/input/tweakxl.xml": "<x/>",
            "\(folder)/red4ext/bin/x64/cyberpunk2077_addresses.json": #"{"uuid": "\#(FakeGame.uuidHex(dbUUID))", "game_version": "2.3.1"}"#,
            "\(folder)/red4ext/macos/scripts/install_macos.sh": "#!/bin/bash\necho setup ran > \"$(dirname \"$0\")/../../../setup.log\"\n",
        ]
        extra.forEach { files["\(folder)/\($0)"] = $1 }
        let tree = try makeTree(files)
        let zip = tree.appendingPathComponent("\(folder).zip")
        XCTAssertEqual(try Process.capture("/usr/bin/ditto", ["-c", "-k", "--keepParent", tree.appendingPathComponent(folder).path, zip.path]).status, 0)
        return zip
    }

    func testInstallUpdateUninstall() throws {
        let fake = try FakeGame(uuid: uuid)
        defer { fake.cleanup() }
        try FakeGame.writeMachO(uuid: uuid, to: fake.game.appendingPathComponent("Cyberpunk2077.orig"))

        // A user mod that must survive uninstall.
        let mod = try makeTree(["mine.archive": "m"])
        try ModStore(kit: fake.kit).install(from: mod, name: "Mine", source: "x")

        let v1 = try Loader.installBundle(zip: try bundleZip(version: "0.1.0-rc1", dbUUID: uuid, extra: ["red4ext/plugins/Old/Old.dylib": "o"]),
                                          version: nil, kit: fake.kit)
        XCTAssertEqual(v1.version, "0.1.0-rc1")
        XCTAssertTrue(fake.exists("setup.log"), "install_macos.sh ran")
        XCTAssertTrue(fake.exists("red4ext/plugins/Old/Old.dylib"))
        XCTAssertEqual(Loader.installedVersion(fake.kit), "0.1.0-rc1")

        // The next version drops a plugin: its files go.
        _ = try Loader.installBundle(zip: try bundleZip(version: "0.1.0", dbUUID: uuid), version: "0.1.0", kit: fake.kit)
        XCTAssertFalse(fake.exists("red4ext/plugins/Old"))
        XCTAssertTrue(fake.exists("red4ext/plugins/TweakXL/TweakXL.dylib"))

        let removed = try Loader.uninstall(kit: fake.kit)
        XCTAssertEqual(removed.version, "0.1.0")
        XCTAssertFalse(fake.exists("launch_red4ext.sh"))
        XCTAssertFalse(fake.exists("red4ext/RED4ext.dylib"))
        XCTAssertFalse(fake.exists("r6/input/tweakxl.xml"))
        XCTAssertFalse(fake.exists("Cyberpunk2077.orig"), "the backup was moved back over the game binary")
        XCTAssertTrue(fake.exists("Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077"))
        XCTAssertTrue(fake.exists("archive/pc/mod/mine.archive"), "user mods stay")
        XCTAssertNil(Loader.installedVersion(fake.kit))
    }

    func testRefusesBundleForAnotherGameBuild() throws {
        let fake = try FakeGame(uuid: uuid)
        defer { fake.cleanup() }
        XCTAssertThrowsError(try Loader.installBundle(zip: try bundleZip(version: "0.2.0", dbUUID: Array(0..<16)), version: nil, kit: fake.kit)) { error in
            XCTAssertTrue((error as? KitError)?.message.contains("supports game build") ?? false)
        }
        XCTAssertFalse(fake.exists("launch_red4ext.sh"), "nothing copied")
    }

    func testRefusesSomethingElse() throws {
        let fake = try FakeGame(uuid: uuid)
        defer { fake.cleanup() }
        let tree = try makeTree(["Other/readme.txt": "x"])
        let zip = tree.appendingPathComponent("other.zip")
        try Process.capture("/usr/bin/ditto", ["-c", "-k", "--keepParent", tree.appendingPathComponent("Other").path, zip.path])
        XCTAssertThrowsError(try Loader.installBundle(zip: zip, version: nil, kit: fake.kit))
    }

    func testDryRunInstallsNothing() throws {
        let fake = try FakeGame(uuid: uuid)
        defer { fake.cleanup() }
        let report = try Loader.installBundle(zip: try bundleZip(version: "0.1.0", dbUUID: uuid), version: nil, kit: fake.with(dryRun: true))
        XCTAssertTrue(report.dryRun)
        XCTAssertEqual(report.files, 7)
        XCTAssertFalse(fake.exists("launch_red4ext.sh"))
    }

    func testMachOUUID() throws {
        let fake = try FakeGame(uuid: uuid)
        defer { fake.cleanup() }
        XCTAssertEqual(MachO.uuid(fake.kit.gameBinary), FakeGame.uuidHex(uuid))
        XCTAssertNil(MachO.uuid(fake.game.appendingPathComponent("missing")))
    }
}
