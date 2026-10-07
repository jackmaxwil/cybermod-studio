import CyberModKit
import Foundation
import XCTest
@testable import CyberModModel

/// AppModel over a real Kit pointed at a temporary fake game folder and state folder. Never the real game; the
/// "launcher" is a stub launch_red4ext.sh and the network is a URLProtocol stub.
@MainActor
final class AppModelTests: XCTestCase {
    var root: URL!
    var game: URL { root.appendingPathComponent("Cyberpunk 2077") }
    let uuid: [UInt8] = Array(100..<116)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cybermod-model-\(UUID().uuidString)")
        try writeMachO(uuid: uuid, to: game.appendingPathComponent("Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func makeModel(running: Bool = false, session: URLSession? = nil, opened: OpenedURLs? = nil) -> AppModel {
        var kit = Kit(game: game.path, home: root.appendingPathComponent("home"))
        kit.isGameRunning = { running }
        if let session { kit.session = session }
        if let opened { kit.openURL = { url in opened.append(url) } }
        return AppModel(kit: kit, gameLog: root.appendingPathComponent("game.log"))
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: game.appendingPathComponent(path).path) }

    func write(_ path: String, _ data: Data = Data()) throws {
        let url = game.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Polls until `condition` holds (play sessions report through an AsyncStream).
    func waitUntil(_ what: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: First run and loader

    func testFirstRunWithoutGame() async throws {
        var kit = Kit(game: root.appendingPathComponent("nowhere").path, home: root.appendingPathComponent("home"))
        kit.isGameRunning = { false }
        let model = AppModel(kit: kit)
        await model.refresh()
        XCTAssertFalse(model.gameFound)
        XCTAssertEqual(model.setupSteps, [.chooseGame])
        XCTAssertEqual(model.playBlocker, "Choose your Cyberpunk 2077 folder first.")

        // Choosing the folder saves it and re-reads everything.
        await model.setGameFolder(game)
        XCTAssertTrue(model.gameFound)
        XCTAssertEqual(model.kit.game.path, game.standardizedFileURL.path)
        XCTAssertEqual(model.setupSteps, [.installLoader, .addFirstMod])
    }

    func testFirstRunThenInstallLoaderFromZip() async throws {
        let model = makeModel()
        await model.refresh()
        XCTAssertTrue(model.gameFound)
        XCTAssertEqual(model.setupSteps, [.installLoader, .addFirstMod])
        XCTAssertEqual(model.findings.first { $0.id == "red4ext" }?.fix, "install-loader")
        XCTAssertNotNil(model.playBlocker)

        await model.installLoader(zip: try bundleZip(version: "0.1.0"))
        XCTAssertNil(model.failure, "\(model.failure?.error.message ?? "")")
        XCTAssertTrue(exists("launch_red4ext.sh"))
        XCTAssertTrue(exists("setup.log"), "install_macos.sh ran")
        XCTAssertEqual(model.loaderVersion, "0.1.0")
        XCTAssertTrue(model.loaderInstalled)
        XCTAssertEqual(model.setupSteps, [.addFirstMod])
        XCTAssertNil(model.playBlocker)
        XCTAssertEqual(model.activities.last?.status, .succeeded)
        XCTAssertEqual(model.notice?.title, "Installed RED4ext for macOS 0.1.0.")
    }

    // MARK: Mods

    func testAddDisableEnableRemove() async throws {
        let model = makeModel()
        let mod = try makeTree(["Neon/archive/pc/mod/neon.archive": "n", "Neon/readme.txt": "hi"]).appendingPathComponent("Neon")
        await model.add(urls: [mod])
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.mods.map(\.id), ["neon"])
        XCTAssertTrue(exists("archive/pc/mod/neon.archive"))
        XCTAssertEqual(model.notice?.title, "Installed Neon.")

        await model.setEnabled("neon", false)
        XCTAssertFalse(exists("archive/pc/mod/neon.archive"))
        XCTAssertEqual(model.mods.first?.enabled, false)

        await model.setEnabled("neon", true)
        XCTAssertTrue(exists("archive/pc/mod/neon.archive"))
        XCTAssertEqual(model.mods.first?.enabled, true)

        await model.remove(["neon"])
        XCTAssertFalse(exists("archive/pc/mod/neon.archive"))
        XCTAssertTrue(model.mods.isEmpty)
        XCTAssertEqual(model.activities.map(\.status), [.succeeded, .succeeded, .succeeded, .succeeded])
    }

    func testAdoptHandInstalledMods() async throws {
        let model = makeModel()
        try write("archive/pc/mod/hand.archive")
        try write("r6/scripts/Hand/hand.reds")
        await model.refresh()
        XCTAssertEqual(model.unmanaged.count, 2)
        XCTAssertTrue(model.setupSteps.contains(.adopt(files: 2)))

        await model.adopt()
        XCTAssertEqual(Set(model.mods.map(\.id)), ["hand"])
        XCTAssertTrue(model.unmanaged.isEmpty)
        XCTAssertTrue(exists("archive/pc/mod/hand.archive"), "adopting moves nothing")
    }

    func testErrorsSayWhatToDoNext() async throws {
        let model = makeModel()
        let windows = try makeTree(["Win/bin/x64/plugins/thing.dll": "x"]).appendingPathComponent("Win")
        await model.add(urls: [windows])
        XCTAssertTrue(model.failure?.error.message.contains("Windows-only") ?? false)
        XCTAssertFalse(model.failure?.error.hint.isEmpty ?? true)
        XCTAssertNil(model.failure?.retry, "nothing to retry")
        XCTAssertEqual(model.activities.last?.status, .failed)
        XCTAssertEqual(model.activities.last?.lines.last?.hasPrefix("Next: "), true)

        await model.add("github:not a repo")
        XCTAssertTrue(model.failure?.error.message.contains("Not a valid mod source") ?? false)

        // A file installed by hand is in the way: the error offers to overwrite, and the retry does.
        try write("archive/pc/mod/neon.archive", Data("hand".utf8))
        let mod = try makeTree(["neon.archive": "mod"])
        await model.add(urls: [mod.appendingPathComponent("neon.archive")])
        let failure = try XCTUnwrap(model.failure)
        XCTAssertEqual(failure.retryTitle, "Overwrite")
        await failure.retry?()
        XCTAssertNil(model.failure)
        XCTAssertEqual(try String(contentsOf: game.appendingPathComponent("archive/pc/mod/neon.archive"), encoding: .utf8), "mod")
    }

    func testRefusesChangesWhileTheGameRuns() async throws {
        let model = makeModel(running: true)
        await model.add(urls: [try makeTree(["a.archive": "a"]).appendingPathComponent("a.archive")])
        XCTAssertEqual(model.failure?.error.message, "Cyberpunk 2077 is running.")
        XCTAssertFalse(exists("archive/pc/mod/a.archive"))
    }

    func testCancelLeavesNothingBehind() async throws {
        let model = makeModel(session: HangingProtocol.session())
        let adding = Task { await model.add("https://dl.test/slow.zip") }
        try await waitUntil("the download to start") { model.isBusy }
        model.cancel()
        await adding.value
        XCTAssertEqual(model.activities.last?.status, .cancelled)
        XCTAssertNil(model.failure, "cancelling is not an error")
        XCTAssertTrue(model.mods.isEmpty)
        XCTAssertFalse(model.isBusy)
    }

    func testNexusWithoutPremiumWaitsForTheNxmLink() async throws {
        setenv("NEXUS_API_KEY", "test-key", 1)
        defer { unsetenv("NEXUS_API_KEY") }
        let api = "https://api.nexusmods.com/v1/games/cyberpunk2077/mods/42"
        let expires = Int(Date().timeIntervalSince1970) + 600
        let zipTree = try makeTree(["Neon/neon.archive": "n"])
        let zip = zipTree.appendingPathComponent("neon.zip")
        XCTAssertEqual(try Process.capture("/usr/bin/ditto", ["-c", "-k", "--keepParent", zipTree.appendingPathComponent("Neon").path, zip.path]).status, 0)
        let opened = OpenedURLs()
        let model = makeModel(session: StubProtocol.session([
            "https://api.nexusmods.com/v1/users/validate.json": (200, Data(#"{"name": "v", "is_premium": false}"#.utf8)),
            "\(api).json": (200, Data(#"{"name": "Neon Lights", "version": "1.2"}"#.utf8)),
            "\(api)/files.json": (200, Data(#"{"files": [{"file_id": 7, "category_name": "MAIN", "is_primary": true}]}"#.utf8)),
            "\(api)/files/7/download_link.json?key=abc&expires=\(expires)": (200, Data(#"[{"URI": "https://dl.test/neon.zip"}]"#.utf8)),
            "https://dl.test/neon.zip": (200, try Data(contentsOf: zip)),
        ]), opened: opened)

        await model.add("https://www.nexusmods.com/cyberpunk2077/mods/42")
        let page = URL(string: "https://www.nexusmods.com/cyberpunk2077/mods/42?tab=files&file_id=7&nmm=1")!
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.nexusWaiting, page)
        XCTAssertEqual(opened.urls, [page])
        XCTAssertEqual(model.activities.last?.status, .waiting)

        // The browser hands the "Mod Manager Download" link to the app.
        await model.open(URL(string: "nxm://cyberpunk2077/mods/42/files/7?key=abc&expires=\(expires)")!)
        XCTAssertNil(model.failure, "\(model.failure?.error.message ?? "")")
        XCTAssertNil(model.nexusWaiting)
        XCTAssertEqual(model.mods.first?.name, "Neon Lights")
        XCTAssertEqual(model.mods.first?.source, "nexus:42/7")
        XCTAssertTrue(exists("archive/pc/mod/neon.archive"))
    }

    // MARK: Load order and health

    func testLoadOrderChange() async throws {
        let model = makeModel()
        let tree = try makeTree([:])
        try writeRDAR([1, 2], to: tree.appendingPathComponent("A/alpha.archive"))
        try writeRDAR([2, 3], to: tree.appendingPathComponent("B/beta.archive"))
        await model.add(urls: [tree.appendingPathComponent("A"), tree.appendingPathComponent("B")])
        XCTAssertEqual(model.archives.map(\.file), ["alpha.archive", "beta.archive"])
        XCTAssertEqual(model.conflicts.map { "\($0.winner) > \($0.loser): \($0.files)" }, ["alpha.archive > beta.archive: 1"])

        await model.prioritize("beta.archive", over: "alpha.archive")
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.archives.map(\.file), ["!beta.archive", "alpha.archive"])
        XCTAssertEqual(model.archives.first?.mod, "b")
        XCTAssertEqual(model.conflicts.first?.winner, "!beta.archive")
    }

    func testDoctorFix() async throws {
        let model = makeModel()
        try writeRDAR([5], to: game.appendingPathComponent("archive/pc/mod/sub/deep.archive"))
        await model.refresh()
        let finding = try XCTUnwrap(model.findings.first { $0.id == "nested-archives" })
        XCTAssertTrue(model.problems.contains(finding))

        await model.fix(try XCTUnwrap(finding.fix))
        XCTAssertNil(model.failure)
        XCTAssertNil(model.findings.first { $0.id == "nested-archives" })
        XCTAssertTrue(exists("archive/pc/mod/deep.archive"))
        XCTAssertEqual(model.notice?.lines.first?.hasPrefix("Moved"), true)
    }

    // MARK: Play

    func installStubLauncher(_ body: String) throws {
        try write("launch_red4ext.sh", Data(("#!/bin/bash\n" + body).utf8))
    }

    func testPlaySessionWithStubLauncher() async throws {
        try installStubLauncher("""
        echo "Launching with RED4ext..."
        sleep 1
        echo "bye"
        exit 0
        """)
        let model = makeModel()
        model.startGame()
        XCTAssertEqual(model.play, .launching)
        try await waitUntil("the game to start") { if case .running = model.play { return true } else { return false } }
        try await waitUntil("the session to end") { model.lastExit != nil }
        XCTAssertEqual(model.play, .idle)
        XCTAssertEqual(model.lastExit?.code, 0)
        XCTAssertTrue(model.gameOutput.contains("bye"))
        XCTAssertEqual(model.activities.last?.title, "Play")
        XCTAssertEqual(model.activities.last?.status, .succeeded)
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("game.log"), encoding: .utf8).contains("bye"))
    }

    func testStopAndCompileFailure() async throws {
        try installStubLauncher("echo Launching with RED4ext...\nsleep 30 & wait\n")
        let model = makeModel()
        model.startGame()
        try await waitUntil("the game to start") { if case .running = model.play { return true } else { return false } }
        await model.add(urls: [try makeTree(["a.archive": "a"]).appendingPathComponent("a.archive")])
        XCTAssertEqual(model.failure?.error.message, "Cyberpunk 2077 is starting or running.")
        model.failure = nil
        model.stopGame()
        XCTAssertEqual(model.play, .stopping)
        try await waitUntil("the session to end") { model.lastExit != nil }
        XCTAssertEqual(model.lastExit?.stoppedByUser, true)
        XCTAssertEqual(model.activities.last?.status, .succeeded)

        try installStubLauncher("""
        echo "[ERROR - x] broken.reds: unexpected token"
        echo "REDscript compilation failed; not launching."
        exit 1
        """)
        model.startGame()
        try await waitUntil("the launcher to refuse") { model.play == .idle && model.lastExit?.code == 1 }
        XCTAssertEqual(model.lastExit?.compileErrors, "[ERROR - x] broken.reds: unexpected token")
        XCTAssertEqual(model.activities.last?.status, .failed)
    }

    func testPlayWithoutLoaderSaysWhatToDo() async throws {
        let model = makeModel()
        model.startGame()
        XCTAssertEqual(model.play, .idle)
        XCTAssertTrue(model.failure?.error.message.contains("RED4ext is not installed") ?? false)
    }

    // MARK: Fixtures

    /// A RED4ext-macOS-arm64-<version>.zip for this fake game whose install_macos.sh only leaves a mark.
    func bundleZip(version: String) throws -> URL {
        let folder = "RED4ext-macOS-arm64-\(version)"
        let hex = uuid.map { String(format: "%02X", $0) }.joined()
        let tree = try makeTree([
            "\(folder)/VERSION": version,
            "\(folder)/launch_red4ext.sh": "#!/bin/bash\n",
            "\(folder)/red4ext/RED4ext.dylib": "dylib",
            "\(folder)/red4ext/plugins/ArchiveXL/ArchiveXL.dylib": "axl",
            "\(folder)/red4ext/bin/x64/cyberpunk2077_addresses.json": #"{"uuid": "\#(hex)", "game_version": "2.3.1"}"#,
            "\(folder)/red4ext/macos/scripts/install_macos.sh": "#!/bin/bash\necho ran > \"$(dirname \"$0\")/../../../setup.log\"\n",
        ])
        let zip = tree.appendingPathComponent("\(folder).zip")
        XCTAssertEqual(try Process.capture("/usr/bin/ditto", ["-c", "-k", "--keepParent", tree.appendingPathComponent(folder).path, zip.path]).status, 0)
        return zip
    }
}

final class OpenedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [URL] = []
    var urls: [URL] { lock.withLock { opened } }
    func append(_ url: URL) { lock.withLock { opened.append(url) } }
}

func makeTree(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cybermod-tree-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (path, contents) in files {
        let url = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
    return dir
}

/// A thin arm64 Mach-O header with one LC_UUID load command.
func writeMachO(uuid: [UInt8], to url: URL) throws {
    var data = Data()
    for value: UInt32 in [0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0, 0x1B, 24] { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: uuid)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

/// A minimal RDAR archive whose file table holds `hashes`.
func writeRDAR(_ hashes: [UInt64], to url: URL) throws {
    var data = Data()
    func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RDAR".utf8))
    put(UInt32(12)); put(UInt64(40)); put(UInt32(28 + 56 * hashes.count))
    data.append(Data(count: 40 - data.count))
    put(UInt32(8)); put(UInt32(56 * hashes.count)); put(UInt64(0)); put(UInt32(hashes.count)); put(UInt32(0)); put(UInt32(0))
    for hash in hashes {
        put(hash)
        data.append(Data(count: 48))
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

/// Serves canned responses by URL, so network flows run without the network.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (status: Int, body: Data)] = [:]

    static func session(_ responses: [String: (Int, Data)]) -> URLSession {
        self.responses = responses.mapValues { (status: $0.0, body: $0.1) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let (status, body) = Self.responses[url.absoluteString] ?? (404, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Never answers, so a download stays in flight until it is cancelled.
final class HangingProtocol: URLProtocol {
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
