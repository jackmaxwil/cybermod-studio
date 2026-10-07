// CyberModStudioApp.swift - Main SwiftUI application entry point

import SwiftUI
import CyberModCore

@main
struct CyberModStudioApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    appState.showNewProjectSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])
                
                Button("Open Project...") {
                    appState.openProject()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            
            CommandMenu("Mods") {
                Button("Install Mod...") {
                    appState.showInstallSheet = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("Browse Nexus Mods...") {
                    appState.showNexusBrowser = true
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Refresh Mod List") {
                    Task { await appState.refreshMods() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            
            CommandMenu("Game") {
                Button(appState.isGameRunning ? "Stop Game" : "Launch Game") {
                    Task { await appState.toggleGame() }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Open Debug Studio") {
                    appState.selectedModule = .debugStudio
                }
                .disabled(!appState.isGameRunning)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    // Navigation
    @Published var selectedModule: StudioModule = .modManager
    
    // Sheets
    @Published var showInstallSheet = false
    @Published var showNexusBrowser = false
    @Published var showNewProjectSheet = false
    
    // Game State
    @Published var isGameRunning = false
    @Published var activeSession: GameSession?
    
    // Services
    let modManager = ModManager.shared
    let gameLauncher = GameLauncher.shared
    let database = ModDatabase.shared
    
    init() {
        Task {
            try? await database.initialize()
        }
    }
    
    func refreshMods() async {
        // Refresh mod list
    }
    
    @Published var lastError: String?
    @Published var gameUptime: TimeInterval = 0
    
    private var uptimeTimer: Timer?
    
    func toggleGame() async {
        if isGameRunning {
            try? await gameLauncher.terminate()
            isGameRunning = false
            activeSession = nil
            uptimeTimer?.invalidate()
            uptimeTimer = nil
            gameUptime = 0
        } else {
            lastError = nil
            do {
                let profile = try await modManager.getActiveProfile()
                await gameLauncher.configure(gamePath: profile.gamePath)
                let session = try await gameLauncher.launch(profile: profile)
                activeSession = session
                isGameRunning = true
                startUptimeTimer()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
    
    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if let session = self.activeSession {
                    self.gameUptime = session.uptime
                    if !session.isRunning, self.isGameRunning {
                        self.isGameRunning = false
                        self.uptimeTimer?.invalidate()
                        if let code = session.exitCode, code != 0 {
                            let report = await self.gameLauncher.exitReport(for: session)
                            self.lastError = "Game exited with code \(code).\n\(report)"
                        }
                    }
                }
            }
        }
    }
    
    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK, let url = panel.url {
            // Open project at URL
        }
    }
}

// MARK: - Studio Modules

enum StudioModule: String, CaseIterable, Identifiable {
    case modManager = "Mod Manager"
    case gameRunner = "Game Runner"
    case creationStudio = "Creation Studio"
    case portingStudio = "Porting Studio"
    case debugStudio = "Debug Studio"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .modManager: return "puzzlepiece.extension"
        case .gameRunner: return "play.circle"
        case .creationStudio: return "hammer"
        case .portingStudio: return "arrow.triangle.2.circlepath"
        case .debugStudio: return "ant"
        }
    }
    
    var description: String {
        switch self {
        case .modManager: return "Install, manage, and organize your mods"
        case .gameRunner: return "Launch and monitor Cyberpunk 2077"
        case .creationStudio: return "Create and edit mod projects"
        case .portingStudio: return "Port Windows mods to macOS"
        case .debugStudio: return "Debug mods at runtime"
        }
    }
}
