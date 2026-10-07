// AppModel.swift - the app's state and actions. Every action is one CyberModKit call run off the main thread; the
// views only read this model and call its methods. No mod logic lives here.

import CyberModKit
import Foundation
import Observation

/// One user action (install, fix, update, play ...) as the Activity screen shows it.
public struct Activity: Identifiable, Sendable {
    public enum Status: Sendable { case running, succeeded, failed, cancelled, waiting }
    public let id = UUID()
    public var title: String
    public var started = Date()
    public var status: Status = .running
    public var lines: [String] = []
    public var error: KitError?
}

/// An error to show, with an optional "do it anyway" retry (overwrite files of other mods).
public struct Failure: Identifiable {
    public let id = UUID()
    public var error: KitError
    public var retryTitle: String?
    public var retry: (@MainActor () async -> Void)?
}

/// A finished action worth telling the user about (what was installed, warnings).
public struct Notice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var lines: [String]
}

public enum PlayState: Equatable, Sendable { case idle, launching, running(pid: Int32), stopping }

public struct GameExit: Equatable, Sendable {
    public var code: Int32
    public var report: String
    public var compileErrors: String?
    public var stoppedByUser: Bool
}

/// What the first-run checklist on the Play screen still needs.
public enum SetupStep: Equatable, Sendable {
    case chooseGame, installLoader, adopt(files: Int), addFirstMod
}

@MainActor @Observable
public final class AppModel {
    public private(set) var kit: Kit
    /// Where play sessions write the game's output (~/Library/Logs/CyberModStudio/game.log).
    public let gameLogURL: URL

    // The game folder as last read by `refresh()`.
    public private(set) var gameFound = false
    public private(set) var mods: [ModRecord] = []
    public private(set) var unmanaged: [String] = []
    public private(set) var doctor: DoctorReport?
    public private(set) var loaderVersion: String?
    public private(set) var archives: [ArchiveEntry] = []
    public private(set) var refreshing = false

    public private(set) var updates: [UpdateInfo] = []
    public private(set) var registryIndex: RegistryIndex?
    public var registry: [RegistryEntry] { registryIndex?.mods ?? [] }
    public private(set) var registryError: KitError?

    public private(set) var activities: [Activity] = []
    public var failure: Failure?
    public var notice: Notice?
    /// The Nexus files page opened for a non-Premium download; cleared when its nxm:// link arrives.
    public var nexusWaiting: URL?

    public private(set) var play: PlayState = .idle
    public private(set) var gameOutput: [String] = []
    public private(set) var lastExit: GameExit?
    public private(set) var playStarted: Date?

    private var cancelCurrent: (() -> Void)?
    private var session: PlaySession?
    private var stopRequested = false

    /// `gameLog` is where play sessions write the game's output (tests use a temporary file).
    public init(kit: Kit, gameLog: URL = PlaySession.defaultLog) {
        self.kit = kit
        self.gameLogURL = gameLog
    }

    // MARK: Derived state

    public var current: Activity? { activities.last { $0.status == .running } }
    public var isBusy: Bool { current != nil }
    public var isPlaying: Bool { play != .idle }
    public var findings: [Finding] { doctor?.findings ?? [] }
    public var problems: [Finding] { findings.filter { $0.level == .error || $0.level == .warning } }
    public var loaderInstalled: Bool { findings.contains { $0.id == "red4ext" && $0.level == .ok } }
    public var conflicts: [ArchiveConflict] { doctor?.conflicts ?? [] }

    public var setupSteps: [SetupStep] {
        guard gameFound else { return [.chooseGame] }
        var steps: [SetupStep] = []
        if !loaderInstalled { steps.append(.installLoader) }
        if !unmanaged.isEmpty { steps.append(.adopt(files: unmanaged.count)) }
        if mods.isEmpty && unmanaged.isEmpty { steps.append(.addFirstMod) }
        return steps
    }

    /// Why Play is unavailable right now, or nil.
    public var playBlocker: String? {
        if !gameFound { return "Choose your Cyberpunk 2077 folder first." }
        if !loaderInstalled { return "Install the mod loader first." }
        if isBusy { return "Wait for \(current?.title ?? "the current task") to finish." }
        return nil
    }

    public func update(for id: String) -> UpdateInfo? { updates.first { $0.id == id && $0.error == nil } }

    // MARK: Refresh

    /// Re-reads mods, the doctor report, loader version and load order (read-only, off the main thread).
    public func refresh() async {
        refreshing = true
        defer { refreshing = false }
        let kit = self.kit
        let snapshot = await Task.detached { Snapshot(kit: kit) }.value
        gameFound = snapshot.gameFound
        mods = snapshot.mods
        unmanaged = snapshot.unmanaged
        doctor = snapshot.doctor
        loaderVersion = snapshot.loaderVersion
        archives = snapshot.archives
        updates.removeAll { info in !mods.contains { $0.id == info.id } }
    }

    struct Snapshot: Sendable {
        var gameFound: Bool, mods: [ModRecord], unmanaged: [String], doctor: DoctorReport, loaderVersion: String?, archives: [ArchiveEntry]
        init(kit: Kit) {
            let store = ModStore(kit: kit)
            gameFound = (try? kit.requireGame()) != nil
            mods = store.list()
            unmanaged = gameFound ? store.unmanagedFiles() : []
            doctor = Doctor.run(kit: kit)
            loaderVersion = Loader.installedVersion(kit)
            archives = LoadOrder.list(kit: kit)
        }
    }

    // MARK: Running library calls

    /// Runs one library call as an Activity: off the main thread, one at a time, refusing file changes while the game
    /// runs, cancellable with `cancel()`. Errors become `failure`; the model refreshes afterwards.
    @discardableResult
    public func run<T: Sendable>(_ title: String, changesFiles: Bool = true, refreshAfter: Bool = true,
                                 _ work: @escaping @Sendable (Kit) async throws -> T) async -> T? {
        if let current {
            failure = Failure(error: KitError("\(current.title) is still running.", hint: "Wait for it to finish, or cancel it in Activity."))
            return nil
        }
        if changesFiles, isPlaying {
            failure = Failure(error: KitError("Cyberpunk 2077 is starting or running.", hint: "Quit the game, then try again."))
            return nil
        }
        failure = nil
        let activity = Activity(title: title)
        let id = activity.id
        activities.append(activity)
        var kit = self.kit
        kit.log = { [weak self] line in Task { @MainActor in self?.log(line, to: id) } }
        let task = Task.detached { () async throws -> T in
            if changesFiles { try kit.requireGameStopped() }
            return try await work(kit)
        }
        cancelCurrent = { task.cancel() }
        defer { cancelCurrent = nil }
        let result: T?
        do {
            result = try await task.value
            finish(id, .succeeded)
        } catch {
            let error = Self.kitError(error)
            finish(id, error == .cancelled ? .cancelled : .failed, error: error)
            if error != .cancelled { failure = Failure(error: error) }
            result = nil
        }
        if refreshAfter { await refresh() }
        return result
    }

    /// Cancels the running activity. The library stops before it changes anything, so nothing is left half done.
    public func cancel() { cancelCurrent?() }

    public func clearFinishedActivities() { activities.removeAll { $0.status != .running } }

    func log(_ line: String, to id: UUID) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].lines.append(line)
    }

    func finish(_ id: UUID, _ status: Activity.Status, error: KitError? = nil) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].status = status
        activities[index].error = error
        if let error {
            activities[index].lines.append("Error: \(error.message)")
            activities[index].lines += error.details.map { "  \($0)" }
            activities[index].lines.append("Next: \(error.hint)")
        }
    }

    static func kitError(_ error: Error) -> KitError {
        if let error = error as? KitError { return error }
        if error is CancellationError { return .cancelled }
        return KitError(error.localizedDescription, hint: "Try again; if it keeps failing, open Health to check the setup.")
    }

    // MARK: Mod loader

    /// Installs (or updates) RED4ext for macOS: the newest verified GitHub release, or a bundle zip the user picked.
    public func installLoader(zip: URL? = nil, onlyIfNewer: Bool = false) async {
        let title = onlyIfNewer ? "Update mod loader" : "Install mod loader"
        guard let report = await run(title, { kit in try await Loader.install(kit: kit, zip: zip, onlyIfNewer: onlyIfNewer) }) else { return }
        notice = Notice(title: report.files > 0 ? "Installed RED4ext for macOS \(report.version ?? "")." : report.nextStep,
                        lines: report.warnings)
    }

    public func uninstallLoader() async {
        guard let report = await run("Remove mod loader", { kit in try Loader.uninstall(kit: kit) }) else { return }
        notice = Notice(title: "Removed RED4ext for macOS (\(report.files) files). Your mods were left in place.", lines: report.warnings)
    }

    // MARK: Mods

    /// Installs a mod from anything `ModSource.parse` accepts (path, https URL, github:, nexus:, nxm://, registry:).
    /// A non-Premium Nexus download opens the files page and waits for its nxm:// link (`nexusWaiting`).
    public func add(_ input: String, force: Bool = false) async {
        let source: ModSource
        do { source = try ModSource.parse(input) } catch {
            failure = Failure(error: Self.kitError(error))
            return
        }
        await add(source, force: force)
    }

    public func add(_ source: ModSource, force: Bool = false) async {
        if case .nxm = source { nexusWaiting = nil }
        if let reports = await run("Add \(source)", { kit in try await ModStore(kit: kit).add(source, force: force) }) {
            notice = Self.installNotice(reports)
            return
        }
        offerOverwrite(retryTitle: "Overwrite") { await self.add(source, force: true) }
        waitForNexusIfNeeded()
    }

    /// Installs dropped or picked files, folders and links one after another; stops at the first failure.
    public func add(urls: [URL]) async {
        for url in urls {
            if url.isFileURL { await add(.local(url.standardizedFileURL)) } else { await add(url.absoluteString) }
            if failure != nil || nexusWaiting != nil { return }
        }
    }

    /// Handles a URL the system opened the app with (nxm:// from Nexus "Mod Manager Download", or a dropped link).
    public func open(_ url: URL) async {
        await add(url.isFileURL ? url.path : url.absoluteString)
    }

    public func setEnabled(_ id: String, _ enabled: Bool, force: Bool = false) async {
        let done = await run(enabled ? "Enable \(id)" : "Disable \(id)") { kit in try ModStore(kit: kit).setEnabled(id, enabled, force: force) }
        if done == nil, enabled { offerOverwrite(retryTitle: "Enable Anyway") { await self.setEnabled(id, true, force: true) } }
    }

    public func remove(_ ids: [String]) async {
        let removed = await run(ids.count == 1 ? "Remove \(ids[0])" : "Remove \(ids.count) mods") { kit in
            try ids.map { try ModStore(kit: kit).remove($0) }
        }
        if let removed {
            notice = Notice(title: "Removed \(removed.map(\.name).joined(separator: ", ")).",
                            lines: ["Deleted \(removed.reduce(0) { $0 + $1.files.count }) file(s) from the game folder."])
        }
    }

    /// Tracks hand-installed mod files as mods without moving them.
    public func adopt() async {
        guard let mods = await run("Track hand-installed mods", { kit in try ModStore(kit: kit).adopt() }) else { return }
        notice = Notice(title: "Now tracking \(mods.count) hand-installed mod(s).",
                        lines: ["You can enable, disable and remove them like any other mod."])
    }

    // MARK: Updates

    public func checkForUpdates() async {
        guard let found = await run("Check for updates", changesFiles: false, refreshAfter: false, { kit in await Updates.check(kit: kit) })
        else { return }
        updates = found
        let available = found.filter { $0.error == nil }
        notice = Notice(title: available.isEmpty ? "All mods with a known source are up to date."
                            : "\(available.count) update(s) available.",
                        lines: found.compactMap { info in info.error.map { "\(info.id): \($0)" } })
    }

    public func update(_ id: String) async {
        guard let reports = await run("Update \(id)", { kit in try await ModStore(kit: kit).update(id) }) else {
            waitForNexusIfNeeded()
            return
        }
        updates.removeAll { $0.id == id }
        notice = Self.installNotice(reports)
    }

    public func updateAll() async {
        for id in updates.filter({ $0.error == nil }).map(\.id) {
            await update(id)
            if failure != nil || nexusWaiting != nil { return }
        }
    }

    // MARK: Health and load order

    public func fix(_ fixID: String) async {
        guard let done = await run("Fix: \(fixID)", { kit in try await Doctor.fix(fixID, kit: kit) }) else { return }
        notice = Notice(title: "Fixed.", lines: done)
    }

    /// Makes `archive` load before (and so win over) `other` by renaming it with a "!" prefix.
    public func prioritize(_ archive: String, over other: String) async {
        let rename = await run("Load \(archive) before \(other)") { kit in try LoadOrder.prioritize(kit: kit, archive: archive, before: other) }
        guard let rename else { return }
        notice = Notice(title: rename.map { "Renamed \($0.from) to \($0.to)." } ?? "\(archive) already loads first.",
                        lines: ["Takes effect the next time you play."])
    }

    // MARK: Discover

    public var registryURL: String { Config(home: kit.home).values["registry.url"] ?? "" }

    public func loadRegistry() async {
        guard !registryURL.isEmpty else { registryIndex = nil; registryError = nil; return }
        let kit = self.kit
        do {
            registryIndex = try await Task.detached { try await Registry.load(kit: kit) }.value
            registryError = nil
        } catch {
            registryIndex = nil
            registryError = Self.kitError(error)
        }
    }

    // MARK: Settings

    /// Set by $CP2077_GAME_DIR (used for testing with a fake game folder); the setting is then ignored.
    public var gameFolderFromEnvironment: Bool { ProcessInfo.processInfo.environment["CP2077_GAME_DIR"] != nil }

    public func setGameFolder(_ url: URL) async {
        do {
            var config = Config(home: kit.home)
            try config.set("game-dir", url.path)
        } catch {
            failure = Failure(error: Self.kitError(error))
            return
        }
        var fresh = Kit(home: kit.home)
        fresh.session = kit.session
        fresh.isGameRunning = kit.isGameRunning
        fresh.openURL = kit.openURL
        kit = fresh
        updates = []
        await refresh()
    }

    public func setRegistryURL(_ value: String) async {
        do {
            var config = Config(home: kit.home)
            try config.set("registry.url", value.trimmingCharacters(in: .whitespaces))
        } catch {
            failure = Failure(error: Self.kitError(error))
            return
        }
        await loadRegistry()
    }

    /// Validates a Nexus Mods API key and saves it in the Keychain. Returns the account, or nil on failure.
    public func saveNexusKey(_ key: String) async -> Nexus.User? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = kit.session
        do {
            let user = try await Nexus.validate(key: key, session: session)
            try Secrets.set(Nexus.keyAccount, key)
            nexusKeySaved = true
            return user
        } catch {
            failure = Failure(error: Self.kitError(error))
            return nil
        }
    }

    /// Whether a Nexus API key is set (from `checkNexusKey()`; reading the Keychain can show a prompt, so not on every redraw).
    public private(set) var nexusKeySaved = false

    public func checkNexusKey() { nexusKeySaved = (try? Nexus.key()) != nil }

    public func removeNexusKey() {
        Secrets.delete(Nexus.keyAccount)
        checkNexusKey()
    }

    // MARK: Play

    /// Starts the game through launch_red4ext.sh; events update `play`, `gameOutput` and `lastExit`.
    public func startGame() {
        guard play == .idle else { return }
        if let current {
            failure = Failure(error: KitError("\(current.title) is still running.", hint: "Wait for it to finish, then play."))
            return
        }
        let session: PlaySession
        do { session = try PlaySession.start(kit: kit, log: gameLogURL) } catch {
            failure = Failure(error: Self.kitError(error))
            return
        }
        self.session = session
        stopRequested = false
        play = .launching
        playStarted = session.startedAt
        gameOutput = []
        lastExit = nil
        var compileErrors: String?
        Task {
            for await event in session.events {
                switch event {
                case .output(let line):
                    gameOutput.append(line)
                    if gameOutput.count > 5000 { gameOutput.removeFirst(gameOutput.count - 5000) }
                case .compileFailed(let errors):
                    compileErrors = errors
                case .gameStarted(let pid):
                    if play == .launching { play = .running(pid: pid) }
                case .exited(let code, let report):
                    lastExit = GameExit(code: code, report: report, compileErrors: compileErrors, stoppedByUser: stopRequested)
                    var activity = Activity(title: "Play")
                    activity.status = code == 0 || stopRequested ? .succeeded : .failed
                    activity.lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    activities.append(activity)
                    play = .idle
                    playStarted = nil
                    self.session = nil
                    await refresh()
                }
            }
        }
    }

    /// Asks the game to quit; the launcher then cleans up and exits.
    public func stopGame() {
        guard let session, play != .stopping else { return }
        stopRequested = true
        play = .stopping
        session.stop()
    }

    // MARK: Helpers

    private func offerOverwrite(retryTitle: String, _ retry: @escaping @MainActor () async -> Void) {
        // The library refuses to overwrite files of other mods and says to run again with --force.
        guard let error = failure?.error, error.hint.contains("--force") else { return }
        failure?.retryTitle = retryTitle
        failure?.retry = retry
    }

    private func waitForNexusIfNeeded() {
        guard let error = failure?.error, error.message == Nexus.premiumOnly else { return }
        failure = nil
        nexusWaiting = error.details.first.flatMap(URL.init(string:))
        if let index = activities.lastIndex(where: { $0.status == .failed }) {
            activities[index].status = .waiting
            activities[index].lines.append("Waiting for \"Mod Manager Download\" on Nexus Mods; the download continues here.")
        }
    }

    static func installNotice(_ reports: [InstallReport]) -> Notice {
        let names = reports.map { "\($0.mod.name)\($0.mod.version.map { " \($0)" } ?? "")" }
        var lines: [String] = []
        for report in reports {
            lines.append("\(report.mod.name): \(report.mod.files.count) file(s) installed.")
            if !report.ignored.isEmpty { lines.append("\(report.mod.name): skipped \(report.ignored.count) file(s) that are not mod files.") }
            if !report.overwritten.isEmpty { lines.append("\(report.mod.name): replaced \(report.overwritten.count) file(s) of other mods.") }
            lines += report.mod.warnings.map { "\(report.mod.name): \($0)" }
        }
        return Notice(title: "Installed \(names.joined(separator: ", ")).", lines: lines)
    }
}
