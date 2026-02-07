// ContentView.swift - Main content view with navigation

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .sheet(isPresented: $appState.showInstallSheet) {
            InstallModSheet()
        }
        .sheet(isPresented: $appState.showNexusBrowser) {
            NexusBrowserSheet()
        }
        .sheet(isPresented: $appState.showNewProjectSheet) {
            NewProjectSheet()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        List(selection: $appState.selectedModule) {
            Section("Workspace") {
                ForEach(StudioModule.allCases) { module in
                    NavigationLink(value: module) {
                        Label(module.rawValue, systemImage: module.icon)
                    }
                }
            }
            
            Section("Quick Actions") {
                Button {
                    appState.showInstallSheet = true
                } label: {
                    Label("Install Mod...", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                
                Button {
                    Task { await appState.toggleGame() }
                } label: {
                    Label(
                        appState.isGameRunning ? "Stop Game" : "Launch Game",
                        systemImage: appState.isGameRunning ? "stop.circle" : "play.circle"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }
}

// MARK: - Detail View

struct DetailView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        switch appState.selectedModule {
        case .modManager:
            ModManagerView()
        case .gameRunner:
            GameRunnerView()
        case .creationStudio:
            CreationStudioView()
        case .portingStudio:
            PortingStudioView()
        case .debugStudio:
            DebugStudioView()
        }
    }
}

// ModManagerView is now in its own file

struct GameRunnerView: View {
    var body: some View {
        VStack {
            Text("Game Runner")
                .font(.largeTitle)
            Text("Launch and monitor Cyberpunk 2077")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CreationStudioView: View {
    var body: some View {
        VStack {
            Text("Creation Studio")
                .font(.largeTitle)
            Text("Create and edit mod projects")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PortingStudioView: View {
    var body: some View {
        VStack {
            Text("Porting Studio")
                .font(.largeTitle)
            Text("Port Windows mods to macOS")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DebugStudioView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if appState.isGameRunning {
            VStack {
                Text("Debug Studio")
                    .font(.largeTitle)
                Text("Connected to game")
                    .foregroundColor(.green)
            }
        } else {
            ContentUnavailableView(
                "Game Not Running",
                systemImage: "ant",
                description: Text("Launch the game to use the debug studio")
            )
        }
    }
}

// MARK: - Sheet Views (Placeholders)

struct InstallModSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var selectedFile: URL?
    @State private var showFomodWizard = false
    @State private var fomodSessionId: UUID?
    @State private var isInstalling = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Install Mod")
                .font(.title)
            
            if isInstalling {
                ProgressView("Installing mod...")
            } else {
                Text("Drop a mod archive here or click Browse")
                    .foregroundColor(.secondary)
                
                HStack {
                    Button("Cancel") { dismiss() }
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.zip, .archive]
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        
                        if panel.runModal() == .OK, let url = panel.url {
                            selectedFile = url
                            Task {
                                await installMod(from: url)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 300)
        .sheet(isPresented: $showFomodWizard) {
            if let sessionId = fomodSessionId {
                FomodInstallerSheet(sessionId: sessionId)
            }
        }
    }
    
    private func installMod(from url: URL) async {
        isInstalling = true
        defer { isInstalling = false }
        
        do {
            let source = ModSource.local(url: url)
            let result = try await appState.modManager.install(source)
            
            // Check if FOMOD wizard is needed
            // This would be detected during installation
            // For now, just dismiss
            dismiss()
        } catch ModManagerError.fomodRequired(let config) {
            // Create FOMOD session and show wizard
            // This is a simplified version - in reality, we'd need to create the session
            // with the extracted mod directory
            // showFomodWizard = true
            dismiss()
        } catch {
            print("Installation failed: \(error)")
            dismiss()
        }
    }
}

// NexusBrowserSheet is now in its own file

struct NewProjectSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.title)
            
            Text("Create a new mod project")
                .foregroundColor(.secondary)
            
            HStack {
                Button("Cancel") { dismiss() }
                Button("Create") { }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            
            PathsSettingsView()
                .tabItem { Label("Paths", systemImage: "folder") }
            
            NexusSettingsView()
                .tabItem { Label("Nexus", systemImage: "globe") }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Toggle("Launch game automatically on startup", isOn: .constant(false))
            Toggle("Check for updates automatically", isOn: .constant(true))
        }
        .padding()
    }
}

struct PathsSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Game Path") {
                HStack {
                    Text("Not configured")
                        .foregroundColor(.secondary)
                    Button("Browse...") { }
                }
            }
            
            LabeledContent("Staging Directory") {
                HStack {
                    Text("~/Library/Application Support/CyberModStudio/staging")
                        .foregroundColor(.secondary)
                    Button("Change...") { }
                }
            }
        }
        .padding()
    }
}

struct NexusSettingsView: View {
    @State private var apiKey = ""
    
    var body: some View {
        Form {
            SecureField("Nexus API Key", text: $apiKey)
            
            Text("Get your API key from nexusmods.com/users/myaccount?tab=api")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
