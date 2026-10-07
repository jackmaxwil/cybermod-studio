// Kit.swift - shared context: where the game and cybermod's own state live, errors, config.

import CryptoKit
import Foundation

/// Version of cybermod. The release workflow rewrites this line from the tag.
public let cybermodVersion = "0.1.0"

/// A failure the user can act on: `message` says what happened, `hint` says what to do next.
public struct KitError: LocalizedError, Equatable, Codable {
    enum CodingKeys: String, CodingKey { case message = "error", hint, details }

    public var message: String
    public var hint: String
    public var details: [String]

    public init(_ message: String, hint: String, details: [String] = []) {
        self.message = message
        self.hint = hint
        self.details = details
    }

    public var errorDescription: String? { message }

    /// What a cancelled operation reports.
    public static let cancelled = KitError("Cancelled.", hint: "Nothing was changed.")
}

/// Everything an operation needs: the game folder, cybermod's state folder, how to report progress, and the seams
/// tests (and the app) replace: the URL session, the game-running check and how web pages open.
///
/// Long operations check `Task.isCancelled` before they change anything, so cancelling the task that runs them never
/// leaves a partial install: downloads and unpacking happen in a temporary folder, files are copied next to their
/// destinations and only then renamed into place.
public struct Kit: Sendable {
    public static let defaultGameDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam/steamapps/common/Cyberpunk 2077")
    public static let defaultHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CyberModStudio")

    /// The Cyberpunk 2077 folder (contains Cyberpunk2077.app).
    public let game: URL
    /// cybermod's own folder: config.json, per-game manifests and disabled mods.
    public let home: URL
    /// Report what would change, change nothing.
    public var dryRun: Bool
    /// Progress lines for humans ("Downloading ...", "Copying 56 files ...").
    public var log: @Sendable (String) -> Void
    /// Shows a web page to the user (the CLI uses `open`; tests and --json leave it a no-op).
    public var openURL: @Sendable (URL) -> Void = { _ in }
    /// All network access goes through this session (tests register a URLProtocol stub on their own).
    public var session: URLSession = .shared
    /// Whether Cyberpunk 2077 is running (tests replace the pgrep check).
    public var isGameRunning: @Sendable () -> Bool = { Process.isRunning("Cyberpunk2077") }

    /// Game folder: `game` (the --game-dir flag), else $CP2077_GAME_DIR, else `game-dir` in config, else the Steam
    /// default. State folder: `home`, else $CYBERMOD_HOME, else ~/Library/Application Support/CyberModStudio.
    public init(game: String? = nil, home: URL? = nil, dryRun: Bool = false, log: @escaping @Sendable (String) -> Void = { _ in }) {
        let env = ProcessInfo.processInfo.environment
        let home = home ?? env["CYBERMOD_HOME"].map { URL(fileURLWithPath: $0) } ?? Kit.defaultHome
        self.home = home
        let path = game ?? env["CP2077_GAME_DIR"] ?? Config(home: home).values["game-dir"]
        self.game = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
            ?? Kit.defaultGameDir
        self.dryRun = dryRun
        self.log = log
    }

    // MARK: Game paths

    public var gameBinary: URL { game.appendingPathComponent("Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077") }
    public var launcher: URL { game.appendingPathComponent("launch_red4ext.sh") }
    public var setupScript: URL { game.appendingPathComponent("red4ext/macos/scripts/install_macos.sh") }
    public var addressDB: URL { game.appendingPathComponent("red4ext/bin/x64/cyberpunk2077_addresses.json") }
    public var binaryBackup: URL { game.appendingPathComponent("Cyberpunk2077.orig") }

    /// Per-game state, keyed by the game folder's path so two installs never share manifests.
    public var stateDir: URL {
        let digest = SHA256.hash(data: Data(game.path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return home.appendingPathComponent("games/\(digest)")
    }

    /// Throws unless `game` looks like a Cyberpunk 2077 install.
    public func requireGame() throws {
        guard FileManager.default.fileExists(atPath: gameBinary.path) else {
            throw KitError("Cyberpunk 2077 not found in \(game.path).",
                           hint: "Pass --game-dir \"/path/to/Cyberpunk 2077\", set CP2077_GAME_DIR, or run "
                               + "`cybermod config set game-dir \"/path/to/Cyberpunk 2077\"`.")
        }
    }

    /// Throws while the game is running: files it has open must not change under it.
    public func requireGameStopped() throws {
        if isGameRunning() {
            throw KitError("Cyberpunk 2077 is running.", hint: "Quit the game, then run this command again.")
        }
    }
}

/// Throws `KitError.cancelled` once the surrounding task is cancelled. Called before anything changes.
func checkCancelled() throws {
    if Task.isCancelled { throw KitError.cancelled }
}

// MARK: - Config

/// Settings in `<home>/config.json`. The Nexus API key is not stored here but in the Keychain (see `Secrets`).
public struct Config {
    public static let keys = ["game-dir", "registry.url", "nexus.api-key"]

    public let file: URL
    public var values: [String: String]

    public init(home: URL) {
        file = home.appendingPathComponent("config.json")
        values = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
    }

    public func save() throws {
        try FileOps.writeJSON(values, to: file)
    }

    public static func check(key: String) throws {
        guard keys.contains(key) else {
            throw KitError("Unknown setting \"\(key)\".", hint: "Known settings: \(keys.joined(separator: ", ")).")
        }
    }
}

// MARK: - Processes

extension Process {
    /// Runs a tool and returns its exit status and combined output.
    @discardableResult
    public static func capture(_ path: String, _ arguments: [String], cwd: URL? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Whether a process with exactly this name runs (pgrep -x).
    public static func isRunning(_ name: String) -> Bool {
        (try? capture("/usr/bin/pgrep", ["-x", name]).status) == 0
    }
}
