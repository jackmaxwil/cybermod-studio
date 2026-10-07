import Foundation
import XCTest
@testable import CyberModKit

/// A throwaway game folder (with a fake Mach-O game binary) and cybermod state folder. Never the real game.
struct FakeGame {
    let root: URL
    let kit: Kit
    var game: URL { kit.game }

    init(uuid: [UInt8] = Array(0..<16), dryRun: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cybermod-test-\(UUID().uuidString)")
        let game = root.appendingPathComponent("Cyberpunk 2077")
        var kit = Kit(game: game.path, home: root.appendingPathComponent("home"), dryRun: dryRun)
        kit.isGameRunning = { false }
        self.kit = kit
        try FakeGame.writeMachO(uuid: uuid, to: kit.gameBinary)
    }

    func with(dryRun: Bool) -> Kit {
        var kit = self.kit
        kit.dryRun = dryRun
        return kit
    }

    func write(_ path: String, _ contents: String = "") throws {
        let url = game.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    /// Every file under the game folder with its contents, to compare before and after.
    func snapshot() -> [String: Data] {
        Dictionary(uniqueKeysWithValues: FileOps.files(in: game).map { ($0, FileManager.default.contents(atPath: game.appendingPathComponent($0).path)!) })
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    /// A thin arm64 Mach-O header with one LC_UUID load command.
    static func writeMachO(uuid: [UInt8], to url: URL) throws {
        var data = Data()
        for value: UInt32 in [0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0, 0x1B, 24] { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: uuid)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func uuidHex(_ uuid: [UInt8]) -> String { uuid.map { String(format: "%02X", $0) }.joined() }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: game.appendingPathComponent(path).path) }
}

/// Writes files (relative path -> contents) under a fresh folder and returns it.
func makeTree(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cybermod-tree-\(UUID().uuidString)")
    for (path, contents) in files {
        let url = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
    return dir
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

/// Serves canned responses by URL for a Kit's session, so network code runs without the network.
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
