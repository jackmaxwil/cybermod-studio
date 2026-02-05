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
    private var fridaGadgetPath: URL?
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
        fridaGadgetPath: URL? = nil,
        debugAgentPath: URL? = nil
    ) {
        self.gamePath = gamePath
        self.red4extPath = red4extPath ?? gamePath.appendingPathComponent("red4ext/RED4ext.dylib")
        self.fridaGadgetPath = fridaGadgetPath ?? gamePath.appendingPathComponent("red4ext/FridaGadget.dylib")
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
        
        logger.info("Launching Cyberpunk 2077 from \(executablePath.path)")
        
        // Build environment
        var environment = ProcessInfo.processInfo.environment
        
        // Collect dylibs to inject
        var dylibsToInject: [URL] = []
        
        if let red4ext = red4extPath, FileManager.default.fileExists(atPath: red4ext.path) {
            dylibsToInject.append(red4ext)
        }
        
        if let frida = fridaGadgetPath, FileManager.default.fileExists(atPath: frida.path) {
            dylibsToInject.append(frida)
        }
        
        if options.enableDebugAgent, let debugAgent = debugAgentPath,
           FileManager.default.fileExists(atPath: debugAgent.path) {
            dylibsToInject.append(debugAgent)
        }
        
        // Set DYLD environment variables
        if !dylibsToInject.isEmpty {
            environment["DYLD_INSERT_LIBRARIES"] = dylibsToInject.map(\.path).joined(separator: ":")
            environment["DYLD_FORCE_FLAT_NAMESPACE"] = "1"
            logger.debug("Injecting dylibs: \(dylibsToInject.map(\.lastPathComponent))")
        }
        
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
        
        // Set up output capture
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
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
            outputPipe: outputPipe,
            errorPipe: errorPipe
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
}

// MARK: - GameSession

/// Represents an active game session
public class GameSession: @unchecked Sendable {
    public let id: UUID
    public let pid: pid_t
    public let profile: ModProfile
    public let startedAt: Date
    
    internal let process: Process
    internal let outputPipe: Pipe
    internal let errorPipe: Pipe
    
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
        outputPipe: Pipe,
        errorPipe: Pipe
    ) {
        self.id = id
        self.pid = pid
        self.profile = profile
        self.startedAt = startedAt
        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
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
        }
    }
}
