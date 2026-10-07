import XCTest
@testable import CyberModKit

final class PlacementTests: XCTestCase {
    func destinations(_ plan: Placement) -> [String: String] {
        Dictionary(uniqueKeysWithValues: plan.files.map { ($0.source, $0.destination) })
    }

    func testWindowsStyleTree() {
        let plan = Placement.plan([
            "MyMod/archive/pc/mod/MyMod.archive",
            "MyMod/archive/pc/mod/sub/Extra.archive.xl",
            "MyMod/archive/pc/mod/readme.txt",
            "MyMod/r6/scripts/MyMod/main.reds",
            "MyMod/r6/tweaks/MyMod/items.yaml",
            "MyMod/r6/input/mymod.xml",
            "MyMod/red4ext/plugins/MyPlugin/MyPlugin.dylib",
            "MyMod/red4ext/plugins/MyPlugin/Scripts/natives.reds",
            "MyMod/r6/config/settings/platform/pc/options.json",
            "MyMod/README.md",
        ], modName: "My Mod")
        XCTAssertTrue(plan.windowsOnly.isEmpty)
        XCTAssertEqual(destinations(plan), [
            "MyMod/archive/pc/mod/MyMod.archive": "archive/pc/mod/MyMod.archive",
            "MyMod/archive/pc/mod/sub/Extra.archive.xl": "archive/pc/mod/Extra.archive.xl",
            "MyMod/r6/scripts/MyMod/main.reds": "r6/scripts/MyMod/main.reds",
            "MyMod/r6/tweaks/MyMod/items.yaml": "r6/tweaks/MyMod/items.yaml",
            "MyMod/r6/input/mymod.xml": "r6/input/mymod.xml",
            "MyMod/red4ext/plugins/MyPlugin/MyPlugin.dylib": "red4ext/plugins/MyPlugin/MyPlugin.dylib",
            "MyMod/red4ext/plugins/MyPlugin/Scripts/natives.reds": "red4ext/plugins/MyPlugin/Scripts/natives.reds",
        ])
        XCTAssertEqual(Set(plan.ignored), ["MyMod/archive/pc/mod/readme.txt", "MyMod/r6/config/settings/platform/pc/options.json", "MyMod/README.md"])
    }

    func testLooseFilesByExtension() {
        let plan = Placement.plan([
            "Lights.archive", "Lights.archive.xl", "extra.xl", "tweak.yml", "data/more.tweak", "Script.reds",
            "Native.dylib", "keys.xml", "fomod/ModuleConfig.xml", "Mods\\Win.archive", "preview.png",
        ], modName: "Better Lights")
        XCTAssertEqual(destinations(plan), [
            "Lights.archive": "archive/pc/mod/Lights.archive",
            "Lights.archive.xl": "archive/pc/mod/Lights.archive.xl",
            "extra.xl": "archive/pc/mod/extra.xl",
            "tweak.yml": "r6/tweaks/tweak.yml",
            "data/more.tweak": "r6/tweaks/more.tweak",
            "Script.reds": "r6/scripts/Better Lights/Script.reds",
            "Native.dylib": "red4ext/plugins/Native/Native.dylib",
            "keys.xml": "r6/input/keys.xml",
            "Mods\\Win.archive": "archive/pc/mod/Win.archive",
        ])
        XCTAssertEqual(Set(plan.ignored), ["fomod/ModuleConfig.xml", "preview.png"])
    }

    func testRefusesWindowsOnlyContent() {
        let plan = Placement.plan([
            "archive/pc/mod/a.archive",
            "red4ext/plugins/Thing/Thing.dll",
            "bin/x64/plugins/cyber_engine_tweaks/mods/Thing/init.lua",
            "bin/x64/plugins/thing.asi",
            "bin/x64/global.ini",
        ], modName: "Thing")
        XCTAssertEqual(plan.windowsOnly.count, 4)
        XCTAssertEqual(plan.files.count, 1)
    }

    func testDuplicateDestinationsKeepTheFirst() {
        let plan = Placement.plan(["a/x.archive", "b/X.archive"], modName: "m")
        XCTAssertEqual(plan.files.map(\.source), ["a/x.archive"])
        XCTAssertEqual(plan.ignored.count, 1)
    }
}

final class ModStoreTests: XCTestCase {
    var fake: FakeGame!
    var store: ModStore { ModStore(kit: fake.kit) }

    override func setUpWithError() throws { fake = try FakeGame() }
    override func tearDown() { fake.cleanup() }

    func testAddRemoveEnableDisable() throws {
        let mod = try makeTree([
            "Cool/archive/pc/mod/cool.archive": "archive",
            "Cool/r6/scripts/Cool/cool.reds": "script",
            "Cool/r6/tweaks/cool.yaml": "tweak",
            "Cool/readme.txt": "hi",
        ])
        defer { try? FileManager.default.removeItem(at: mod) }

        let report = try store.install(from: mod, name: "Cool Mod", version: "1.0", source: mod.path)
        XCTAssertEqual(report.mod.id, "cool-mod")
        XCTAssertEqual(report.ignored, ["Cool/readme.txt"])
        XCTAssertTrue(report.mod.warnings.contains { $0.contains("ArchiveXL") })
        for path in ["archive/pc/mod/cool.archive", "r6/scripts/Cool/cool.reds", "r6/tweaks/cool.yaml"] { XCTAssertTrue(fake.exists(path), path) }
        XCTAssertEqual(store.list().map(\.id), ["cool-mod"])
        XCTAssertEqual(try store.get("Cool Mod").files.count, 3)

        // A file someone added next to the mod survives everything below.
        try Data("mine".utf8).write(to: fake.game.appendingPathComponent("r6/scripts/Cool/user.reds"))

        try store.setEnabled("cool-mod", false)
        XCTAssertFalse(fake.exists("archive/pc/mod/cool.archive"))
        XCTAssertFalse(fake.exists("r6/tweaks/cool.yaml"))
        XCTAssertTrue(fake.exists("r6/scripts/Cool/user.reds"))
        XCTAssertFalse(try store.get("cool-mod").enabled)

        try store.setEnabled("cool-mod", true)
        XCTAssertTrue(fake.exists("archive/pc/mod/cool.archive"))
        XCTAssertEqual(try String(contentsOf: fake.game.appendingPathComponent("r6/tweaks/cool.yaml"), encoding: .utf8), "tweak")

        try store.remove("cool-mod")
        XCTAssertFalse(fake.exists("archive/pc/mod/cool.archive"))
        XCTAssertFalse(fake.exists("r6/scripts/Cool/cool.reds"))
        XCTAssertTrue(fake.exists("r6/scripts/Cool/user.reds"))
        XCTAssertTrue(fake.exists("archive/pc/mod"), "mod folders stay even when empty")
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertThrowsError(try store.get("cool-mod"))
    }

    func testRefusesOverwritingOtherModsUnlessForced() throws {
        let first = try makeTree(["shared.archive": "first", "first.reds": "1"])
        let second = try makeTree(["shared.archive": "second"])
        defer { [first, second].forEach { try? FileManager.default.removeItem(at: $0) } }

        try store.install(from: first, name: "First", source: "first")
        XCTAssertThrowsError(try store.install(from: second, name: "Second", source: "second")) { error in
            XCTAssertEqual((error as? KitError)?.details, ["archive/pc/mod/shared.archive (mod first)"])
        }
        XCTAssertEqual(try String(contentsOf: fake.game.appendingPathComponent("archive/pc/mod/shared.archive"), encoding: .utf8), "first")

        let forced = try store.install(from: second, name: "Second", source: "second", force: true)
        XCTAssertEqual(forced.overwritten, [Conflict(path: "archive/pc/mod/shared.archive", owner: "first")])
        XCTAssertEqual(try store.get("first").files.map(\.path), ["r6/scripts/First/first.reds"], "ownership moved to the new mod")

        // Removing the first mod leaves the second one's file alone.
        try store.remove("first")
        XCTAssertTrue(fake.exists("archive/pc/mod/shared.archive"))
    }

    func testRefusesUntrackedFilesAndWindowsMods() throws {
        try FileManager.default.createDirectory(at: fake.game.appendingPathComponent("archive/pc/mod"), withIntermediateDirectories: true)
        try Data("by hand".utf8).write(to: fake.game.appendingPathComponent("archive/pc/mod/hand.archive"))
        let mod = try makeTree(["hand.archive": "new"])
        let windows = try makeTree(["bin/x64/plugins/cyber_engine_tweaks/mods/x/init.lua": "", "x.archive": ""])
        defer { [mod, windows].forEach { try? FileManager.default.removeItem(at: $0) } }

        XCTAssertThrowsError(try store.install(from: mod, name: "Hand", source: "x")) { error in
            XCTAssertEqual((error as? KitError)?.details, ["archive/pc/mod/hand.archive (not installed by cybermod)"])
        }
        XCTAssertEqual(store.unmanagedFiles(), ["archive/pc/mod/hand.archive"])
        XCTAssertThrowsError(try store.install(from: windows, name: "Win", source: "x")) { error in
            XCTAssertTrue((error as? KitError)?.message.contains("Windows-only") ?? false)
        }
        XCTAssertFalse(fake.exists("archive/pc/mod/x.archive"), "nothing of a refused mod is installed")
    }

    func testUpdateReplacesOldFiles() throws {
        let v1 = try makeTree(["old.archive": "1", "keep.reds": "1"])
        let v2 = try makeTree(["new.archive": "2", "keep.reds": "2"])
        defer { [v1, v2].forEach { try? FileManager.default.removeItem(at: $0) } }
        try store.install(from: v1, name: "Mod", version: "1", source: "x")
        try store.install(from: v2, name: "Mod", version: "2", source: "x")
        XCTAssertFalse(fake.exists("archive/pc/mod/old.archive"))
        XCTAssertTrue(fake.exists("archive/pc/mod/new.archive"))
        XCTAssertEqual(try store.get("mod").version, "2")
        XCTAssertEqual(store.list().count, 1)
    }

    func testDryRunChangesNothing() throws {
        let mod = try makeTree(["a.archive": "a"])
        defer { try? FileManager.default.removeItem(at: mod) }
        let report = try ModStore(kit: fake.with(dryRun: true)).install(from: mod, name: "A", source: "x")
        XCTAssertTrue(report.dryRun)
        XCTAssertEqual(report.mod.files.map(\.path), ["archive/pc/mod/a.archive"])
        XCTAssertFalse(fake.exists("archive/pc/mod/a.archive"))
        XCTAssertTrue(store.list().isEmpty)
    }

    func testUnpacksZipSources() async throws {
        let tree = try makeTree(["Zipped/archive/pc/mod/z.archive": "z"])
        let zip = tree.deletingLastPathComponent().appendingPathComponent("Zipped Mod-99-1-0-1700000000.zip")
        defer { [tree, zip].forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertEqual(try Process.capture("/usr/bin/ditto", ["-c", "-k", tree.path, zip.path]).status, 0)

        let reports = try await store.add(try ModSource.parse(zip.path))
        XCTAssertEqual(reports.map(\.mod.id), ["zipped-mod"])
        XCTAssertTrue(fake.exists("archive/pc/mod/z.archive"))
    }
}
