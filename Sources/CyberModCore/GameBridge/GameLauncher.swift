// GameLauncher.swift - Launch and monitor Cyberpunk 2077

import Foundation
import Logging

/// Launches and monitors the game process
public actor GameLauncher {
    
    // MARK: - Properties
    
    private let logger: Logger
    private var activeSession: GameSession?
    private var processMonitor: ProcessMonitor?
    
    // MARK: - Singleton
    
    public static let shared = GameLauncher()
    
    // MARK: - Initialization
    
    public init() {
        self.logger = Logger(label: "com.cybermod.gamelauncher")
    }
    
    // MARK: - Launch
    
    /// Launch the game with the given profile by running RED4ext's `launch_red4ext.sh` from the game folder.
    /// The script owns every pre-launch step, so the app never diverges from it: it refuses a game binary whose UUID
    /// does not match the address DB or that lost RED4ext's signature, stages only plugin Scripts that pass
    /// `red4ext_plugin_check`, compiles with scc, merges r6/input key bindings (inputloader.pl, run from the game
    /// folder), starts the game with RED4ext and unstages the plugin Scripts once the game exits.
    /// A refusal shows up as a non-zero exit; `exitReport` then includes the launcher's output.
    public func launch(
        profile: ModProfile,
        options: LaunchOptions = .default
    ) async throws -> GameSession {
        if let session = activeSession, session.isRunning {
            throw GameLaunchError.alreadyRunning
        }
        
        let gamePath = profile.gamePath
        let executablePath = gamePath.appendingPathComponent("Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077")
        guard FileManager.default.fileExists(atPath: executablePath.path) else {
            throw GameLaunchError.gameNotFound(expectedPath: executablePath)
        }
        let script = gamePath.appendingPathComponent("launch_red4ext.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw GameLaunchError.launcherNotFound(expectedPath: script)
        }
        
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in profile.settings.environmentVariables {
            environment[key] = value
        }
        var arguments = options.launchArguments
        if profile.settings.skipIntroVideos {
            arguments.append("-skipStartScreen")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.environment = environment
        process.currentDirectoryURL = gamePath
        
        // stdout/stderr go to a file: an undrained pipe blocks the game once its buffer fills.
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CyberModStudio/game.log")
        let log: FileHandle
        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            log = try FileHandle(forWritingTo: logURL)
        } catch {
            throw GameLaunchError.launchFailed(reason: "Cannot open \(logURL.path): \(error.localizedDescription)")
        }
        defer { try? log.close() }
        process.standardOutput = log
        process.standardError = log
        
        logger.info("Running \(script.path)")
        do {
            try process.run()
        } catch {
            throw GameLaunchError.launchFailed(reason: error.localizedDescription)
        }
        
        let session = GameSession(
            id: UUID(),
            pid: process.processIdentifier,
            profile: profile,
            startedAt: Date(),
            process: process,
            logURL: logURL
        )
        activeSession = session
        
        processMonitor = ProcessMonitor(session: session)
        Task {
            await processMonitor?.startMonitoring()
        }
        
        logger.info("Launcher started with PID: \(session.pid)")
        return session
    }
    
    /// Terminate the running game
    public func terminate() async throws {
        guard let session = activeSession else {
            throw GameLaunchError.notRunning
        }
        
        logger.info("Terminating game (PID: \(session.pid))")
        
        // Stop the game, the launcher script's child; the script then unstages plugin Scripts and exits.
        _ = try? Self.run(URL(fileURLWithPath: "/usr/bin/pkill"), ["-TERM", "-P", String(session.pid)])
        session.process.waitUntilExit()
        
        activeSession = nil
        processMonitor = nil
        
        logger.info("Game terminated")
    }
    
    /// Check if the game is currently running
    public var isRunning: Bool {
        activeSession?.isRunning ?? false
    }
    
    /// Get the current game session
    public func getActiveSession() -> GameSession? {
        activeSession
    }
    
    private static func run(_ executable: URL, _ arguments: [String], mergeStderr: Bool = true) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = mergeStderr ? pipe : FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
    
    // MARK: - Post-exit report
    
    /// Crash reports written since the session started, plus the tail of the newest red4ext log.
    public func exitReport(for session: GameSession, tailLines: Int = 40) async -> String {
        let fm = FileManager.default
        let reportsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        func newFiles(in dir: URL, where match: (String) -> Bool) -> [URL] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return files
                .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
                .filter { match($0.0.lastPathComponent) && $0.1 >= session.startedAt }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        let isCrash = { (name: String) in name.hasPrefix("Cyberpunk2077") && name.hasSuffix(".ips") }
        
        var crashes = newFiles(in: reportsDir, where: isCrash)
        // ReportCrash can take a few seconds to write the .ips after an abnormal exit.
        if crashes.isEmpty, let code = session.exitCode, code != 0 {
            for _ in 0..<15 where crashes.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                crashes = newFiles(in: reportsDir, where: isCrash)
            }
        }
        
        var report = "Game output: \(session.logURL.path)\n"
        let output = (try? String(contentsOf: session.logURL, encoding: .utf8)) ?? ""
        let skipped = output.split(separator: "\n").filter { $0.hasPrefix("Not compiling") }
        if !skipped.isEmpty {
            report += skipped.joined(separator: "\n") + "\n"
        }
        // A non-zero exit can be the launcher refusing to start (game updated, binary not re-signed, scc errors).
        if let code = session.exitCode, code != 0 {
            let tail = output.split(separator: "\n", omittingEmptySubsequences: false).suffix(tailLines)
            report += "Launcher/game output (last \(tailLines) lines):\n" + tail.joined(separator: "\n") + "\n"
        }
        report += crashes.isEmpty
            ? "No new crash reports."
            : "New crash reports:\n" + crashes.map { "  \($0.path)" }.joined(separator: "\n")
        
        let logsDir = session.profile.gamePath.appendingPathComponent("red4ext/logs")
        if let log = newFiles(in: logsDir, where: { $0.hasPrefix("red4ext") && $0.hasSuffix(".log") }).first,
           let text = try? String(contentsOf: log, encoding: .utf8) {
            let tail = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(tailLines)
            report += "\n\n\(log.lastPathComponent) (last \(tailLines) lines):\n" + tail.joined(separator: "\n")
        } else {
            report += "\n\nNo red4ext log written this session."
        }
        return report
    }
}

// MARK: - GameSession

/// Represents an active game session
public class GameSession: @unchecked Sendable {
    public let id: UUID
    public let pid: pid_t
    public let profile: ModProfile
    public let startedAt: Date
    
    /// File receiving the game's stdout and stderr.
    public let logURL: URL
    
    internal let process: Process
    
    private var _status: GameSessionStatus = .running
    public var status: GameSessionStatus {
        get { _status }
        set { _status = newValue }
    }
    
    public init(
        id: UUID,
        pid: pid_t,
        profile: ModProfile,
        startedAt: Date,
        process: Process,
        logURL: URL
    ) {
        self.id = id
        self.pid = pid
        self.profile = profile
        self.startedAt = startedAt
        self.process = process
        self.logURL = logURL
    }
    
    /// Whether the game is still running
    public var isRunning: Bool {
        process.isRunning
    }
    
    /// Duration the game has been running
    public var uptime: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
    
    /// Exit code if terminated
    public var exitCode: Int32? {
        if process.isRunning {
            return nil
        }
        return process.terminationStatus
    }
}

/// Game session status
public enum GameSessionStatus: Sendable {
    case running
    case terminated(exitCode: Int32)
    case crashed(signal: Int32)
}

// MARK: - ProcessMonitor

/// Monitors a game process for status changes
actor ProcessMonitor {
    private let session: GameSession
    private var isMonitoring = false
    
    init(session: GameSession) {
        self.session = session
    }
    
    func startMonitoring() async {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Monitor in background
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            self.session.process.waitUntilExit()
            
            let status = self.session.process.terminationStatus
            let reason = self.session.process.terminationReason
            
            switch reason {
            case .exit:
                await self.updateStatus(.terminated(exitCode: status))
            case .uncaughtSignal:
                await self.updateStatus(.crashed(signal: status))
            @unknown default:
                await self.updateStatus(.terminated(exitCode: status))
            }
        }
    }
    
    private func updateStatus(_ status: GameSessionStatus) {
        session.status = status
    }
}

// MARK: - LaunchOptions

/// Options for launching the game
public struct LaunchOptions: Sendable {
    /// Passed through launch_red4ext.sh to the game.
    public var launchArguments: [String]
    
    public static let `default` = LaunchOptions()
    
    public init(launchArguments: [String] = []) {
        self.launchArguments = launchArguments
    }
}

// MARK: - Errors

/// Errors thrown by GameLauncher
public enum GameLaunchError: LocalizedError {
    case gameNotFound(expectedPath: URL)
    case alreadyRunning
    case notRunning
    case launcherNotFound(expectedPath: URL)
    case launchFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .gameNotFound(let path):
            return "Game not found at \(path.path)"
        case .alreadyRunning:
            return "Game is already running"
        case .notRunning:
            return "Game is not running"
        case .launchFailed(let reason):
            return "Failed to launch game: \(reason)"
        case .launcherNotFound(let path):
            return "RED4ext is not installed: \(path.path) is missing. Install a RED4ext macOS release into the game folder."
        }
    }
}
