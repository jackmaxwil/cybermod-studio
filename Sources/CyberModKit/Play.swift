// Play.swift - a game session started through RED4ext's launch_red4ext.sh, reported as events.

import Foundation

public enum PlayEvent: Sendable, Equatable {
    /// One line of launcher or game output (also appended to the session log).
    case output(String)
    /// The launcher refused to start because REDscript compilation failed; carries the [ERROR lines.
    case compileFailed(String)
    /// The game process is running.
    case gameStarted(pid: Int32)
    /// The launcher exited (after the game, or refusing to start). `report` lists new crash reports, plugins whose
    /// scripts were not compiled, and on failure the tail of the output and the red4ext log.
    case exited(code: Int32, report: String)
}

/// Runs `<game>/launch_red4ext.sh`; the script owns every pre-launch step (build check, signature check, scc,
/// key bindings, Steam app id). A test can point a Kit at a temporary game folder with its own stub script.
public final class PlaySession: @unchecked Sendable {
    public static let defaultLog = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/CyberModStudio/game.log")

    public let events: AsyncStream<PlayEvent>
    public let launcherPID: Int32
    public let logURL: URL
    public let startedAt: Date
    private let process: Process

    /// Throws what would stop a launch: no game, RED4ext not installed, game already running.
    public static func preflight(kit: Kit) throws {
        try kit.requireGame()
        guard FileManager.default.fileExists(atPath: kit.launcher.path) else {
            throw KitError("RED4ext is not installed (\(kit.launcher.path) is missing).", hint: "Install it: cybermod install")
        }
        try kit.requireGameStopped()
    }

    public static func start(kit: Kit, arguments: [String] = [], log: URL = defaultLog) throws -> PlaySession {
        try preflight(kit: kit)
        return try PlaySession(kit: kit, arguments: arguments, log: log)
    }

    private init(kit: Kit, arguments: [String], log logURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: logURL.path, contents: nil)
        let logFile = try FileHandle(forWritingTo: logURL)
        self.logURL = logURL
        let startedAt = Date()
        self.startedAt = startedAt

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [kit.launcher.path] + arguments
        process.currentDirectoryURL = kit.game
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process

        let (events, continuation) = AsyncStream.makeStream(of: PlayEvent.self)
        self.events = events
        let lock = NSLock()
        var buffer = Data()
        var errors: [String] = []
        var launcherPID: Int32 = 0

        func handle(_ line: String) {
            continuation.yield(.output(line))
            if line.hasPrefix("[ERROR") { errors.append(line) }
            if line.contains("REDscript compilation failed") { continuation.yield(.compileFailed(errors.joined(separator: "\n"))) }
            if line.hasPrefix("Launching with RED4ext") {
                // The game is the launcher's child; it shows up a moment after this line.
                DispatchQueue.global().async {
                    for _ in 0..<40 {
                        if let pid = try? Process.capture("/usr/bin/pgrep", ["-P", "\(launcherPID)"]).output
                            .split(separator: "\n").first.flatMap({ Int32($0) }) {
                            continuation.yield(.gameStarted(pid: pid))
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.25)
                    }
                }
            }
        }
        func drain(_ data: Data, final: Bool) {
            lock.lock()
            defer { lock.unlock() }
            logFile.write(data)
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                handle(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            if final, !buffer.isEmpty {
                handle(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll()
            }
        }

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { drain(data, final: false) }
        }
        let gameDir = kit.game
        process.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            drain(pipe.fileHandleForReading.readDataToEndOfFile(), final: true)
            try? logFile.close()
            let code = process.terminationStatus
            continuation.yield(.exited(code: code, report: Self.report(code: code, log: logURL, game: gameDir, since: startedAt)))
            continuation.finish()
        }
        try process.run()
        launcherPID = process.processIdentifier
        self.launcherPID = launcherPID
    }

    /// Asks the game to quit (SIGTERM); the launcher then takes its plugin scripts out again and exits. Before the
    /// game started, stops the launcher itself.
    public func stop() {
        let children = try? Process.capture("/usr/bin/pkill", ["-TERM", "-P", "\(launcherPID)"])
        if children?.status != 0, process.isRunning { process.terminate() }
    }

    /// Crash reports written since the session started, "Not compiling X" lines, and for a failed exit the tail of the
    /// output and of the newest red4ext log.
    static func report(code: Int32, log: URL, game: URL, since start: Date, tail: Int = 40) -> String {
        let fm = FileManager.default
        func newFiles(_ dir: URL, _ match: (String) -> Bool) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
                .filter { match($0.0.lastPathComponent) && $0.1 >= start }
                .sorted { $0.1 > $1.1 }.map(\.0)
        }
        let reports = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let isCrash = { (name: String) in name.hasPrefix("Cyberpunk2077") && name.hasSuffix(".ips") }
        var crashes = newFiles(reports, isCrash)
        // After a crash (the launcher exits 128 + signal) ReportCrash can take a few seconds to write the .ips.
        for _ in 0..<5 where crashes.isEmpty && code > 128 {
            Thread.sleep(forTimeInterval: 1)
            crashes = newFiles(reports, isCrash)
        }

        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        var text = "Output: \(log.path)\n"
        let skipped = output.split(separator: "\n").filter { $0.hasPrefix("Not compiling") }
        if !skipped.isEmpty { text += skipped.joined(separator: "\n") + "\n" }
        if code != 0 {
            text += "Last \(tail) lines:\n" + output.split(separator: "\n", omittingEmptySubsequences: false).suffix(tail).joined(separator: "\n") + "\n"
        }
        text += crashes.isEmpty ? "No new crash reports." : "New crash reports:\n" + crashes.map { "  \($0.path)" }.joined(separator: "\n")
        if code != 0, let red4ext = newFiles(game.appendingPathComponent("red4ext/logs"), { $0.hasSuffix(".log") }).first,
           let log = try? String(contentsOf: red4ext, encoding: .utf8) {
            text += "\n\n\(red4ext.lastPathComponent) (last \(tail) lines):\n" + log.split(separator: "\n").suffix(tail).joined(separator: "\n")
        }
        return text
    }
}
