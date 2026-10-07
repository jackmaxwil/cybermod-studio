import XCTest
@testable import CyberModKit

final class SourceParsingTests: XCTestCase {
    func testRemoteSources() throws {
        XCTAssertEqual(try ModSource.parse("github:psiberx/cp2077-archive-xl"), .github(repo: "psiberx/cp2077-archive-xl", tag: nil))
        XCTAssertEqual(try ModSource.parse("github:a/b@v1.2.0"), .github(repo: "a/b", tag: "v1.2.0"))
        XCTAssertEqual(try ModSource.parse("https://github.com/a/b/releases/tag/v2"), .github(repo: "a/b", tag: "v2"))
        XCTAssertEqual(try ModSource.parse("nexus:4198"), .nexus(mod: 4198, file: nil))
        XCTAssertEqual(try ModSource.parse("nexus:4198/12345"), .nexus(mod: 4198, file: 12345))
        XCTAssertEqual(try ModSource.parse("https://www.nexusmods.com/cyberpunk2077/mods/107?tab=files&file_id=9"), .nexus(mod: 107, file: 9))
        XCTAssertEqual(try ModSource.parse("registry:better-lights"), .registry("better-lights"))
        XCTAssertEqual(try ModSource.parse("https://example.com/mod.zip"), .url(URL(string: "https://example.com/mod.zip")!))
    }

    func testNXM() throws {
        let source = try ModSource.parse("nxm://cyberpunk2077/mods/107/files/555?key=abc&expires=1999999999&user_id=1")
        XCTAssertEqual(source, .nxm(mod: 107, file: 555, key: "abc", expires: 1_999_999_999))
        XCTAssertEqual(source.description, "nexus:107/555", "the key must never be recorded")
        XCTAssertThrowsError(try ModSource.parse("nxm://skyrimspecialedition/mods/1/files/2?key=a&expires=1"))
        XCTAssertThrowsError(try ModSource.parse("nxm://cyberpunk2077/mods/1/files/2"))
    }

    func testInvalidSources() {
        for bad in ["github:noslash", "nexus:abc", "nexus:1/x", "registry:", "http://example.com/a.zip", "/definitely/not/here.zip"] {
            XCTAssertThrowsError(try ModSource.parse(bad), bad)
        }
    }

    func testLocalPath() throws {
        let dir = try makeTree(["a.archive": "x"])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(try ModSource.parse(dir.path), .local(dir.standardizedFileURL))
    }

    func testNamesAndSlugs() {
        XCTAssertEqual(Fetched.modName(fromFile: "Silent Silencers-1234-1-2a-1699999999.zip"), "Silent Silencers")
        XCTAssertEqual(Fetched.modName(fromFile: "CoolMod.7z"), "CoolMod")
        XCTAssertEqual(Fetched.modName(fromFile: "lights.archive"), "lights")
        XCTAssertEqual(ModStore.slug("Cool Mod v2!"), "cool-mod-v2")
        XCTAssertEqual(ModStore.slug("!!!"), "mod")
    }

    func testReleaseSelection() {
        func release(_ tag: String, pre: Bool = false) -> GitHubRelease {
            GitHubRelease(tag_name: tag, prerelease: pre, draft: false, assets: [], zipball_url: nil)
        }
        XCTAssertLessThan(ReleaseVersion("0.1.0-rc3")!, ReleaseVersion("0.1.0")!)
        XCTAssertLessThan(ReleaseVersion("v0.1.0-rc2")!, ReleaseVersion("0.1.0-rc10")!)
        XCTAssertNil(ReleaseVersion("v1.0.0-macos"))

        // Before 1.0: newest including release candidates; tags outside the scheme are ignored.
        let early = [release("v1.0.0-macos"), release("v0.1.0-rc3", pre: true), release("v0.1.0-rc2", pre: true)]
        XCTAssertEqual(Loader.pick(early, version: nil)?.0.tag_name, "v0.1.0-rc3")
        XCTAssertEqual(Loader.pick(early, version: "0.1.0-rc2")?.0.tag_name, "v0.1.0-rc2")
        XCTAssertNil(Loader.pick(early, version: "9.9.9"))
        // After 1.0: release candidates are only installed on request.
        let later = [release("v1.1.0-rc1", pre: true), release("v1.0.0"), release("v0.9.0")]
        XCTAssertEqual(Loader.pick(later, version: nil)?.0.tag_name, "v1.0.0")
    }

    func testModAssetChoice() {
        func asset(_ name: String) -> GitHubRelease.Asset { .init(name: name, browser_download_url: URL(string: "https://x/\(name)")!) }
        let release = GitHubRelease(tag_name: "v1", prerelease: false, draft: false,
                                    assets: [asset("notes.txt"), asset("Mod-windows.zip"), asset("Mod-source.zip"), asset("Mod.zip"), asset("Mod-macOS.zip")],
                                    zipball_url: nil)
        XCTAssertEqual(GitHub.modAsset(release)?.name, "Mod-macOS.zip")
    }
}

final class ChecksumTests: XCTestCase {
    func testSumsAndVerification() throws {
        let dir = try makeTree(["file.zip": "hello"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("file.zip")
        let good = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertEqual(try Checksum.sha256(of: file), good)

        let sums = Checksum.parseSums("\(good)  file.zip\n\(String(repeating: "a", count: 64)) *other.zip\ngarbage line\n")
        XCTAssertEqual(sums, ["file.zip": good, "other.zip": String(repeating: "a", count: 64)])

        XCTAssertNoThrow(try Checksum.verify(file, expected: good.uppercased()))
        XCTAssertThrowsError(try Checksum.verify(file, expected: String(repeating: "0", count: 64))) { error in
            XCTAssertTrue((error as? KitError)?.message.contains("Checksum mismatch") ?? false)
        }
    }
}

final class RegistryTests: XCTestCase {
    func testExampleIndexParses() throws {
        let example = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../docs/registry.example.json")
        let index = try RegistryIndex.parse(Data(contentsOf: example))
        XCTAssertEqual(index.schema, 1)
        XCTAssertFalse(index.mods.isEmpty)
        XCTAssertNotNil(index.entry(index.mods[0].id))
    }

    func testSearchAndValidation() throws {
        let json = """
        {"schema": 1, "mods": [
          {"id": "better-lights", "name": "Better Lights", "version": "1.0.0", "author": "Neon", "description": "Brighter city lights",
           "source": "github:neon/better-lights@v1.0.0", "requires": ["archivexl"]},
          {"id": "quiet-guns", "name": "Quiet Guns", "version": "2.1", "source": "https://example.com/quiet.zip",
           "sha256": "\(String(repeating: "b", count: 64))"}
        ]}
        """
        let index = try RegistryIndex.parse(Data(json.utf8))
        XCTAssertEqual(index.search("city LIGHTS").map(\.id), ["better-lights"])
        XCTAssertEqual(index.search("").count, 2)
        XCTAssertEqual(index.entry("better-lights")?.requires, ["archivexl"])

        let bad = """
        {"schema": 1, "mods": [
          {"id": "Bad Id", "name": "x", "version": "1", "source": "github:a/b"},
          {"id": "dup", "name": "x", "version": "1", "source": "github:a/b"},
          {"id": "dup", "name": "x", "version": "1", "source": "nexus:1"},
          {"id": "nosum", "name": "x", "version": "1", "source": "https://example.com/a.zip"},
          {"id": "local", "name": "x", "version": "1", "source": "/tmp"}
        ]}
        """
        XCTAssertThrowsError(try RegistryIndex.parse(Data(bad.utf8))) { error in
            XCTAssertEqual((error as? KitError)?.details.count, 4)
        }
        XCTAssertThrowsError(try RegistryIndex.parse(Data(#"{"schema": 2, "mods": []}"#.utf8)))
    }
}
