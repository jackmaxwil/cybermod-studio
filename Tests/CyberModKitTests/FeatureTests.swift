import XCTest
@testable import CyberModKit

/// Adopt, load order, doctor fixes, FOMOD refusal, cancellation, play sessions and network flows over stubs.
final class FeatureTests: XCTestCase {
    var fake: FakeGame!
    var store: ModStore { ModStore(kit: fake.kit) }

    override func setUpWithError() throws { fake = try FakeGame() }
    override func tearDown() { fake.cleanup() }

    func testRoundTripLeavesGameFolderIdentical() throws {
        try fake.write("archive/pc/mod/hand.archive", "by hand")
        try fake.write("r6/scripts/Other/other.reds", "other")
        let before = fake.snapshot()
        let mod = try makeTree(["M/archive/pc/mod/m.archive": "m", "M/r6/scripts/M/m.reds": "s", "M/r6/tweaks/t.yaml": "t"])
        defer { try? FileManager.default.removeItem(at: mod) }

        try store.install(from: mod, name: "M", source: "x")
        try store.setEnabled("m", false)
        try store.setEnabled("m", true)
        try store.remove("m")
        XCTAssertEqual(fake.snapshot(), before)
    }

    func testAdoptGroupsHandInstalledFiles() throws {
        try fake.write("archive/pc/mod/SilentSilencers.archive")
        try fake.write("archive/pc/mod/SilentSilencers.archive.xl")
        try fake.write("archive/pc/mod/Other.archive")
        try fake.write("r6/scripts/ImmersiveTimeskip/a.reds")
        try fake.write("r6/scripts/ImmersiveTimeskip/b.reds")
        try fake.write("r6/tweaks/silent.yaml")
        let before = fake.snapshot()

        let mods = try store.adopt()
        XCTAssertEqual(mods.map(\.id), ["immersivetimeskip", "other", "silent", "silentsilencers"])
        XCTAssertEqual(mods.first { $0.id == "silentsilencers" }?.files.count, 2)
        XCTAssertTrue(store.unmanagedFiles().isEmpty)
        XCTAssertEqual(fake.snapshot(), before, "adopting moves nothing")

        try store.setEnabled("immersivetimeskip", false)
        XCTAssertFalse(fake.exists("r6/scripts/ImmersiveTimeskip/a.reds"))
    }

    func testLoadOrderPriorityIsTrackedAndUndoneByUpdate() throws {
        let a = try makeTree(["zeta.archive": "z"])
        defer { try? FileManager.default.removeItem(at: a) }
        try store.install(from: a, name: "Zeta", source: "x")
        try fake.write("archive/pc/mod/#first.archive")
        try fake.write("archive/pc/mod/alpha.archive")
        XCTAssertEqual(LoadOrder.list(kit: fake.kit).map(\.file), ["#first.archive", "alpha.archive", "zeta.archive"])

        let rename = try LoadOrder.prioritize(kit: fake.kit, archive: "zeta.archive", before: "#first.archive")
        XCTAssertEqual(rename, Rename(from: "archive/pc/mod/zeta.archive", to: "archive/pc/mod/!zeta.archive"))
        XCTAssertEqual(LoadOrder.list(kit: fake.kit).first, ArchiveEntry(rank: 1, file: "!zeta.archive", mod: "zeta"))
        XCTAssertNil(try LoadOrder.prioritize(kit: fake.kit, archive: "!zeta.archive", before: "alpha.archive"), "already first")
        XCTAssertThrowsError(try LoadOrder.prioritize(kit: fake.kit, archive: "alpha.archive", before: "#first.archive"),
                             "hand-installed archives must be adopted first")

        try store.setEnabled("zeta", false)
        XCTAssertFalse(fake.exists("archive/pc/mod/!zeta.archive"))
        try store.setEnabled("zeta", true)
        try store.install(from: a, name: "Zeta", source: "x")  // update restores the original name
        XCTAssertTrue(fake.exists("archive/pc/mod/zeta.archive"))
        XCTAssertFalse(fake.exists("archive/pc/mod/!zeta.archive"))
    }

    func testDoctorFixes() async throws {
        try writeRDAR([1, 2], to: fake.game.appendingPathComponent("archive/pc/mod/a.archive"))
        try writeRDAR([2, 1], to: fake.game.appendingPathComponent("archive/pc/mod/b.archive"))
        try writeRDAR([7], to: fake.game.appendingPathComponent("archive/pc/mod/folder/nested.archive"))
        try fake.write("archive/pc/content/stray.xl")

        let report = Doctor.run(kit: fake.kit)
        XCTAssertEqual(Set(report.findings.compactMap(\.fix)),
                       ["install-loader", "move-nested-archives", "move-misplaced-xl", "remove-duplicate-archives", "adopt"])

        _ = try await Doctor.fix("move-nested-archives", kit: fake.kit)
        _ = try await Doctor.fix("move-misplaced-xl", kit: fake.kit)
        _ = try await Doctor.fix("remove-duplicate-archives", kit: fake.kit)
        XCTAssertTrue(fake.exists("archive/pc/mod/nested.archive"))
        XCTAssertFalse(fake.exists("archive/pc/mod/folder"))
        XCTAssertTrue(fake.exists("archive/pc/mod/stray.xl"))
        XCTAssertFalse(fake.exists("archive/pc/mod/b.archive"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fake.kit.stateDir.appendingPathComponent("removed/b.archive").path))

        let after = Set(Doctor.run(kit: fake.kit).findings.map(\.id))
        XCTAssertTrue(after.isDisjoint(with: ["nested-archives", "misplaced-xl", "identical-archives"]), "\(after)")
        do { _ = try await Doctor.fix("nope", kit: fake.kit); XCTFail() } catch {}
    }

    func testRefusesFomodInstallers() throws {
        let mod = try makeTree(["fomod/ModuleConfig.xml": "<config/>", "Option A/x.archive": "a", "Option B/x.archive": "b"])
        defer { try? FileManager.default.removeItem(at: mod) }
        XCTAssertThrowsError(try store.install(from: mod, name: "Choices", source: "x")) { error in
            XCTAssertTrue((error as? KitError)?.message.contains("FOMOD") ?? false)
        }
        XCTAssertFalse(fake.exists("archive/pc/mod/x.archive"))
    }

    func testCancelledInstallChangesNothing() async throws {
        let mod = try makeTree(["c.archive": "c"])
        defer { try? FileManager.default.removeItem(at: mod) }
        let kit = fake.kit
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ModStore(kit: kit).install(from: mod, name: "C", source: "x")
        }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? KitError, KitError.cancelled)
        }
        XCTAssertFalse(fake.exists("archive/pc/mod/c.archive"))
        XCTAssertTrue(store.list().isEmpty)
    }

    // MARK: Play

    func stubLauncher(_ body: String) throws {
        try fake.write("launch_red4ext.sh", "#!/bin/bash\n" + body)
    }

    func collect(_ session: PlaySession) async -> [PlayEvent] {
        var events: [PlayEvent] = []
        for await event in session.events { events.append(event) }
        return events
    }

    func testPlaySessionEvents() async throws {
        try stubLauncher("""
        echo "=== RED4ext macOS Launcher ==="
        echo "Launching with RED4ext..."
        sleep 1
        echo "game said bye"
        exit 3
        """)
        let log = fake.root.appendingPathComponent("game.log")
        let session = try PlaySession.start(kit: fake.kit, log: log)
        let events = await collect(session)
        XCTAssertEqual(Array(events.prefix(2)), [.output("=== RED4ext macOS Launcher ==="), .output("Launching with RED4ext...")])
        XCTAssertTrue(events.contains { if case .gameStarted = $0 { return true } else { return false } }, "\(events)")
        XCTAssertTrue(events.contains(.output("game said bye")))
        guard case .exited(let code, let report)? = events.last else { return XCTFail("\(events)") }
        XCTAssertEqual(code, 3)
        XCTAssertTrue(report.contains("game said bye"))
        XCTAssertTrue(try String(contentsOf: log, encoding: .utf8).contains("game said bye"))
    }

    func testPlaySessionCompileFailureAndStop() async throws {
        try stubLauncher("""
        echo "[ERROR - Fri] broken.reds: unexpected token"
        echo "REDscript compilation failed; not launching (the game would stop at the same errors)."
        exit 1
        """)
        let failed = await collect(try PlaySession.start(kit: fake.kit, log: fake.root.appendingPathComponent("1.log")))
        XCTAssertTrue(failed.contains(.compileFailed("[ERROR - Fri] broken.reds: unexpected token")), "\(failed)")

        try stubLauncher("echo Launching with RED4ext...\nsleep 30 & wait\n")
        let session = try PlaySession.start(kit: fake.kit, log: fake.root.appendingPathComponent("2.log"))
        var events: [PlayEvent] = []
        for await event in session.events {
            events.append(event)
            if case .gameStarted = event { session.stop() }
        }
        guard case .exited? = events.last else { return XCTFail("\(events)") }
    }

    func testPlayNeedsTheLauncher() {
        XCTAssertThrowsError(try PlaySession.start(kit: fake.kit)) { error in
            XCTAssertEqual((error as? KitError)?.hint, "Install it: cybermod install")
        }
    }

    // MARK: Network over stubs

    func testGitHubSourceAndUpdateCheck() async throws {
        let zipTree = try makeTree(["Lights/archive/pc/mod/lights.archive": "v2"])
        let zip = zipTree.appendingPathComponent("lights.zip")
        defer { try? FileManager.default.removeItem(at: zipTree) }
        try Process.capture("/usr/bin/ditto", ["-c", "-k", "--keepParent", zipTree.appendingPathComponent("Lights").path, zip.path])
        let releases = """
        [{"tag_name": "v2.0", "prerelease": false, "draft": false, "zipball_url": null,
          "assets": [{"name": "lights-windows.zip", "browser_download_url": "https://dl.test/win.zip"},
                     {"name": "lights.zip", "browser_download_url": "https://dl.test/lights.zip"}]}]
        """
        var kit = fake.kit
        kit.session = StubProtocol.session([
            "https://api.github.com/repos/neon/lights/releases?per_page=100": (200, Data(releases.utf8)),
            "https://dl.test/lights.zip": (200, try Data(contentsOf: zip)),
        ])
        let store = ModStore(kit: kit)
        let reports = try await store.add(try ModSource.parse("github:neon/lights@v2.0"))
        XCTAssertEqual(reports.first?.mod.id, "lights")
        XCTAssertEqual(reports.first?.mod.version, "v2.0")
        XCTAssertTrue(fake.exists("archive/pc/mod/lights.archive"))

        var old = try store.get("lights")
        old.version = "v1.0"
        try store.save(old)
        let updates = await Updates.check(kit: kit)
        XCTAssertEqual(updates, [UpdateInfo(id: "lights", installed: "v1.0", available: "v2.0", source: "github:neon/lights", error: nil)])
        _ = try await store.update("lights")
        XCTAssertEqual(try store.get("lights").version, "v2.0")
        let none = await Updates.check(kit: kit)
        XCTAssertTrue(none.isEmpty)
    }

    func testNexusErrorsAndBadDownloads() async throws {
        var kit = fake.kit
        kit.session = StubProtocol.session(["https://api.nexusmods.com/v1/users/validate.json": (401, Data())])
        do {
            _ = try await Nexus.validate(key: "bad", session: kit.session)
            XCTFail()
        } catch {
            XCTAssertEqual((error as? KitError)?.message, "Nexus Mods rejected the API key.")
        }
        do {
            _ = try await ModSource.url(URL(string: "https://dl.test/missing.zip")!).fetch(kit: kit)
            XCTFail()
        } catch {
            XCTAssertTrue((error as? KitError)?.message.contains("HTTP 404") ?? false, "\(error)")
        }
        kit.session = StubProtocol.session(["https://dl.test/mod.zip": (200, Data("not the expected bytes".utf8))])
        do {
            _ = try await ModSource.url(URL(string: "https://dl.test/mod.zip")!).fetch(kit: kit, sha256: String(repeating: "0", count: 64))
            XCTFail()
        } catch {
            XCTAssertTrue((error as? KitError)?.message.contains("Checksum mismatch") ?? false, "\(error)")
        }
    }
}
