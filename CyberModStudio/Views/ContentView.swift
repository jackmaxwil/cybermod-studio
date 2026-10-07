// ContentView.swift - Main content view with navigation

import SwiftUI
import CyberModCore

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
    @EnvironmentObject var appState: AppState
    @State private var gamePath = ""
    @State private var logLines: [String] = []
    @State private var isLoadingLogs = false
    
    private static let defaultGamePath = NSHomeDirectory() + "/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Game Runner")
                        .font(.title.bold())
                    Text("Launch and monitor Cyberpunk 2077")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                launchButton
            }
            .padding()
            
            Divider()
            
            HSplitView {
                // Left: Status & Config
                VStack(alignment: .leading, spacing: 16) {
                    statusSection
                    Divider()
                    configSection
                    Divider()
                    frameworkStatusSection
                    Spacer()
                }
                .padding()
                .frame(minWidth: 350, idealWidth: 400)
                
                // Right: Log viewer
                logViewerSection
            }
        }
        .onAppear {
            if gamePath.isEmpty {
                gamePath = Self.defaultGamePath
            }
        }
    }
    
    @ViewBuilder
    private var launchButton: some View {
        Button {
            Task { await appState.toggleGame() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: appState.isGameRunning ? "stop.fill" : "play.fill")
                Text(appState.isGameRunning ? "Stop Game" : "Launch Game")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.isGameRunning ? .red : .green)
    }
    
    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Status", systemImage: "gauge")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(appState.isGameRunning ? .green : .gray)
                    .frame(width: 10, height: 10)
                Text(appState.isGameRunning ? "Running" : "Stopped")
                    .foregroundStyle(appState.isGameRunning ? .primary : .secondary)
            }
            
            if appState.isGameRunning {
                LabeledContent("Uptime") {
                    Text(formatUptime(appState.gameUptime))
                        .monospacedDigit()
                }
                
                if let session = appState.activeSession {
                    LabeledContent("PID") {
                        Text("\(session.pid)")
                            .monospacedDigit()
                    }
                }
            }
            
            if let error = appState.lastError {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    @ViewBuilder
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Configuration", systemImage: "gearshape")
                .font(.headline)
            
            LabeledContent("Game Path") {
                HStack {
                    Text(gamePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            gamePath = url.path
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
    
    @ViewBuilder
    private var frameworkStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Frameworks", systemImage: "puzzlepiece.extension")
                .font(.headline)
            
            let basePath = gamePath + "/red4ext"
            FrameworkRow(name: "RED4ext", path: basePath + "/RED4ext.dylib")
            FrameworkRow(name: "TweakXL", path: basePath + "/plugins/TweakXL/TweakXL.dylib")
            FrameworkRow(name: "ArchiveXL", path: basePath + "/plugins/ArchiveXL/ArchiveXL.dylib")
            FrameworkRow(name: "ModMenu", path: basePath + "/plugins/ModMenu/ModMenu.dylib")
        }
    }
    
    @ViewBuilder
    private var logViewerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Log Viewer", systemImage: "doc.text")
                    .font(.headline)
                Spacer()
                Button {
                    loadLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isLoadingLogs)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            if logLines.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text",
                    description: Text("Launch the game to see logs, or click refresh")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(logLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(logColor(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: logLines.count) { _, _ in
                        if let last = logLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 400)
    }
    
    private func loadLogs() {
        isLoadingLogs = true
        let logPath = gamePath + "/red4ext/logs"
        
        DispatchQueue.global(qos: .userInitiated).async {
            var lines: [String] = []
            let fm = FileManager.default
            
            if let contents = try? fm.contentsOfDirectory(atPath: logPath) {
                let logFiles = contents
                    .filter { $0.hasSuffix(".log") && !$0.contains("->") }
                    .sorted()
                
                if let latest = logFiles.last {
                    let fullPath = logPath + "/" + latest
                    if let data = fm.contents(atPath: fullPath),
                       let content = String(data: data, encoding: .utf8) {
                        lines = content.components(separatedBy: .newlines)
                            .filter { !$0.isEmpty }
                    }
                }
            }
            
            DispatchQueue.main.async {
                logLines = lines
                isLoadingLogs = false
            }
        }
    }
    
    private func logColor(for line: String) -> Color {
        if line.contains("[error]") { return .red }
        if line.contains("[warning]") || line.contains("[warn]") { return .orange }
        if line.contains("[info]") { return .primary }
        if line.contains("[debug]") { return .secondary }
        return .primary
    }
    
    private func formatUptime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct FrameworkRow: View {
    let name: String
    let path: String
    
    var body: some View {
        HStack {
            Image(systemName: FileManager.default.fileExists(atPath: path) ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(FileManager.default.fileExists(atPath: path) ? .green : .red)
            Text(name)
                .font(.callout)
        }
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
                Text(".archive mods need ArchiveXL installed; the game does not load archive/pc/mod on its own on macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack {
                    Button("Cancel") { dismiss() }
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.zip, .archive]
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        
                        if panel.runModal() == .OK, let url = panel.url {
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
    }
    
    private func installMod(from url: URL) async {
        isInstalling = true
        defer { isInstalling = false }
        
        do {
            _ = try await appState.modManager.install(.local(url: url))
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
