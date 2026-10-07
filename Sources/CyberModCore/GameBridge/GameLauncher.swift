// GameLauncher.swift - Launch and monitor Cyberpunk 2077

import Foundation
import Logging

/// Launches and monitors the game process
public actor GameLauncher {
    
    // MARK: - Properties
    
    private let logger: Logger
    private var activeSession: GameSession?
    private var processMonitor: ProcessMonitor?
    
    // MARK: - Configuration
    
    private var gamePath: URL?
    private var red4extPath: URL?
    private var debugAgentPath: URL?
    
    // MARK: - Singleton
    
    public static let shared = GameLauncher()
    
    // MARK: - Initialization
    
    public init() {
        self.logger = Logger(label: "com.cybermod.gamelauncher")
    }
    
    // MARK: - Configuration
    
    /// Configure game paths
    public func configure(
        gamePath: URL,
        red4extPath: URL? = nil,
        debugAgentPath: URL? = nil
    ) {
        self.gamePath = gamePath
        self.red4extPath = red4extPath ?? gamePath.appendingPathComponent("red4ext/RED4ext.dylib")
        self.debugAgentPath = debugAgentPath ?? gamePath.appendingPathComponent("red4ext/DebugAgent.dylib")
    }
    
    // MARK: - Launch
    
    /// Launch the game with the given profile
    public func launch(
        profile: ModProfile,
        options: LaunchOptions = .default
    ) async throws -> GameSession {
        // Check if already running
        if let session = activeSession, session.isRunning {
            throw GameLaunchError.alreadyRunning
        }
        
        // Verify game path
        let executablePath = profile.gamePath
            .appendingPathComponent("Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077")
        
        guard FileManager.default.fileExists(atPath: executablePath.path) else {
            throw GameLaunchError.gameNotFound(expectedPath: executablePath)
        }
        
        let red4ext = red4extPath ?? profile.gamePath.appendingPathComponent("red4ext/RED4ext.dylib")
        guard FileManager.default.fileExists(atPath: red4ext.path) else {
            throw GameLaunchError.injectionFailed(dylib: red4ext, reason: "RED4ext.dylib is not installed")
        }
        
        try verifyEntitlements(executablePath)
        let skippedScripts = try compileScripts(gamePath: profile.gamePath)
        
        logger.info("Launching Cyberpunk 2077 from \(executablePath.path)")
        
        // Build environment
        var environment = ProcessInfo.processInfo.environment
        
        // Collect dylibs to inject
        var dylibsToInject = [red4ext]
        
        if options.enableDebugAgent, let debugAgent = debugAgentPath,
           FileManager.default.fileExists(atPath: debugAgent.path) {
            dylibsToInject.append(debugAgent)
        }
        
        // Set DYLD environment variables (same as launch_red4ext.sh)
        environment["DYLD_INSERT_LIBRARIES"] = dylibsToInject.map(\.path).joined(separator: ":")
        logger.debug("Injecting dylibs: \(dylibsToInject.map(\.lastPathComponent))")
        
        // Apply profile environment variables
        for (key, value) in profile.settings.environmentVariables {
            environment[key] = value
        }
        
        // Build arguments
        var arguments = options.launchArguments
        
        if profile.settings.skipIntroVideos {
            arguments.append("-skipStartScreen")
        }
        
        // Create and configure process
        let process = Process()
        process.executableURL = executablePath
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = profile.gamePath
        
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
        
        // Launch process
        do {
            try process.run()
        } catch {
            throw GameLaunchError.launchFailed(reason: error.localizedDescription)
        }
        
        // Create session
        let session = GameSession(
            id: UUID(),
            pid: process.processIdentifier,
            profile: profile,
            startedAt: Date(),
            process: process,
            logURL: logURL,
            skippedScripts: skippedScripts
        )
        
        activeSession = session
        
        // Start monitoring
        processMonitor = ProcessMonitor(session: session)
        Task {
            await processMonitor?.startMonitoring()
        }
        
        logger.info("Game launched with PID: \(session.pid)")
        
        return session
    }
    
    /// Terminate the running game
    public func terminate() async throws {
        guard let session = activeSession else {
            throw GameLaunchError.notRunning
        }
        
        logger.info("Terminating game (PID: \(session.pid))")
        
        session.process.terminate()
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
    
    // MARK: - Pre-launch checks
    
    /// Entitlements RED4ext needs on the game binary (RED4ext scripts/red4ext_entitlements.plist).
    static let requiredEntitlements = [
        "com.apple.security.cs.allow-dyld-environment-variables",
        "com.apple.security.cs.disable-library-validation",
        "com.apple.security.cs.allow-unsigned-executable-memory",
    ]
    
    /// Fails if the binary (e.g. restored by a Steam "Verify integrity") lacks the entitlements. Never re-signs.
    private func verifyEntitlements(_ executable: URL) throws {
        let result = try run(URL(fileURLWithPath: "/usr/bin/codesign"),
                             ["-d", "--entitlements", ":-", executable.path], mergeStderr: false)
        let plist = (try? PropertyListSerialization.propertyList(from: result.output, format: nil)) as? [String: Any] ?? [:]
        let missing = Self.requiredEntitlements.filter { plist[$0] as? Bool != true }
        if !missing.isEmpty {
            throw GameLaunchError.missingEntitlements(executable: executable, missing: missing)
        }
    }
    
    /// Stages the Scripts of plugins RED4ext will load into r6/scripts/zz_red4ext_plugins and compiles with scc,
    /// like launch_red4ext.sh. Returns the plugins whose Scripts were skipped, with the reason.
    private func compileScripts(gamePath: URL) throws -> [String] {
        let fm = FileManager.default
        let stage = gamePath.appendingPathComponent("r6/scripts/zz_red4ext_plugins")
        try? fm.removeItem(at: stage)
        let gate = PluginGate.evaluate(gamePath: gamePath)
        for plugin in gate.allowed {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            try fm.copyItem(at: plugin.appendingPathComponent("Scripts"),
                            to: stage.appendingPathComponent(plugin.lastPathComponent))
        }
        let skipped = gate.skipped.map { "\($0.name): \($0.reason)" }
        for line in skipped {
            logger.warning("Not staging Scripts of \(line)")
        }
        
        let scc = gamePath.appendingPathComponent("engine/tools/scc")
        if fm.isExecutableFile(atPath: scc.path) {
            let result = try run(scc, ["-compile", gamePath.appendingPathComponent("r6/scripts").path])
            guard result.status == 0 else {
                throw GameLaunchError.scriptCompilationFailed(output: String(decoding: result.output, as: UTF8.self))
            }
        }
        
        // Process input mappings (best effort, as in launch_red4ext.sh)
        let inputLoader = gamePath.appendingPathComponent("engine/tools/inputloader.pl")
        if fm.isExecutableFile(atPath: inputLoader.path) {
            _ = try? run(inputLoader, [])
        }
        return skipped
    }
    
    private func run(_ executable: URL, _ arguments: [String], mergeStderr: Bool = true) throws -> (status: Int32, output: Data) {
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
        if !session.skippedScripts.isEmpty {
            report += "Plugin Scripts not staged:\n" + session.skippedScripts.map { "  \($0)" }.joined(separator: "\n") + "\n"
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
    /// "plugin: reason" for each plugin whose Scripts were not staged because RED4ext would refuse it.
    public let skippedScripts: [String]
    
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
        logURL: URL,
        skippedScripts: [String] = []
    ) {
        self.id = id
        self.pid = pid
        self.profile = profile
        self.startedAt = startedAt
        self.process = process
        self.logURL = logURL
        self.skippedScripts = skippedScripts
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
    public var launchArguments: [String]
    public var enableDebugAgent: Bool
    
    public static let `default` = LaunchOptions(
        launchArguments: [],
        enableDebugAgent: false
    )
    
    public init(launchArguments: [String] = [], enableDebugAgent: Bool = false) {
        self.launchArguments = launchArguments
        self.enableDebugAgent = enableDebugAgent
    }
}

// MARK: - Errors

/// Errors thrown by GameLauncher
public enum GameLaunchError: LocalizedError {
    case gameNotFound(expectedPath: URL)
    case alreadyRunning
    case notRunning
    case launchFailed(reason: String)
    case injectionFailed(dylib: URL, reason: String)
    case missingEntitlements(executable: URL, missing: [String])
    case scriptCompilationFailed(output: String)
    
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
        case .injectionFailed(let dylib, let reason):
            return "Failed to inject \(dylib.lastPathComponent): \(reason)"
        case .missingEntitlements(let executable, let missing):
            return """
            The game binary is missing entitlements RED4ext needs (\(missing.joined(separator: ", "))). \
            A Steam "Verify integrity" or update restores the stock binary. Re-sign it with RED4ext's plist:
              codesign -f -s - -o runtime --entitlements RED4ext/scripts/red4ext_entitlements.plist "\(executable.path)"
            (or: RED4ext/scripts/codesign_macos.sh exe "\(executable.path)")
            """
        case .scriptCompilationFailed(let output):
            return "REDscript compilation (scc) failed:\n\(output)"
        }
    }
}
