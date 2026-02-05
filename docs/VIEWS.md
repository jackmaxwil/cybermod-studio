# CyberMod Studio - View Architecture

## 1. Navigation Structure

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ CyberMod Studio                                                    ─ □ ✕       │
├─────────────────────────────────────────────────────────────────────────────────┤
│ ┌─────────────┐ ┌─────────────────────────────────────────────────────────────┐ │
│ │  Sidebar    │ │                     Detail View                             │ │
│ │             │ │                                                             │ │
│ │ ┌─────────┐ │ │  ┌─────────────────────────────────────────────────────┐   │ │
│ │ │ Mod     │ │ │  │                    Toolbar                          │   │ │
│ │ │ Manager │◄──┼──┤  [Install] [Nexus] [Profiles ▼] [Search...]  [⚙️]  │   │ │
│ │ └─────────┘ │ │  └─────────────────────────────────────────────────────┘   │ │
│ │             │ │                                                             │ │
│ │ ┌─────────┐ │ │  ┌─────────────────────┐ ┌───────────────────────────────┐ │ │
│ │ │  Game   │ │ │  │   Master List       │ │      Detail Inspector         │ │ │
│ │ │ Runner  │ │ │  │                     │ │                               │ │ │
│ │ └─────────┘ │ │  │  ☑ Mod Name v1.0   │ │  Name: Mod Name               │ │ │
│ │             │ │  │    Author • TweakXL │ │  Version: 1.0                 │ │ │
│ │ ┌─────────┐ │ │  │                     │ │  Author: Creator              │ │ │
│ │ │Creation │ │ │  │  ☐ Another Mod     │ │  Type: TweakXL                │ │ │
│ │ │ Studio  │ │ │  │    Author • Archive │ │  Installed: 2024-01-15        │ │ │
│ │ └─────────┘ │ │  │                     │ │                               │ │ │
│ │             │ │  │  ...                │ │  [Enable] [Uninstall] [More▼] │ │ │
│ │ ┌─────────┐ │ │  │                     │ │                               │ │ │
│ │ │Porting  │ │ │  │                     │ │  ┌───────────────────────────┐│ │ │
│ │ │ Studio  │ │ │  │                     │ │  │ Files                     ││ │ │
│ │ └─────────┘ │ │  │                     │ │  │ • base/v_core.archive     ││ │ │
│ │             │ │  │                     │ │  │ • r6/tweaks/core.yaml     ││ │ │
│ │ ┌─────────┐ │ │  │                     │ │  └───────────────────────────┘│ │ │
│ │ │ Debug   │ │ │  │                     │ │                               │ │ │
│ │ │ Studio  │ │ │  └─────────────────────┘ └───────────────────────────────┘ │ │
│ │ └─────────┘ │ │                                                             │ │
│ │             │ │  ┌─────────────────────────────────────────────────────────┐│ │
│ │ ─────────── │ │  │ Status: 47 mods • 12 enabled • Profile: Default        ││ │
│ │ ┌─────────┐ │ │  └─────────────────────────────────────────────────────────┘│ │
│ │ │Settings │ │ │                                                             │ │
│ │ └─────────┘ │ │                                                             │ │
│ └─────────────┘ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 2. View Hierarchy

```
App
├── MainWindow
│   ├── NavigationSplitView
│   │   ├── SidebarView
│   │   │   ├── ModuleNavigationItem (Mod Manager)
│   │   │   ├── ModuleNavigationItem (Game Runner)
│   │   │   ├── ModuleNavigationItem (Creation Studio)
│   │   │   ├── ModuleNavigationItem (Porting Studio)
│   │   │   ├── ModuleNavigationItem (Debug Studio)
│   │   │   └── ModuleNavigationItem (Settings)
│   │   │
│   │   └── DetailView (switches based on selection)
│   │       ├── ModManagerView
│   │       ├── GameRunnerView
│   │       ├── CreationStudioView
│   │       ├── PortingStudioView
│   │       ├── DebugStudioView
│   │       └── SettingsView
│   │
│   └── ToolbarContent
│
├── Sheets (modal)
│   ├── InstallModSheet
│   ├── NexusBrowserSheet
│   ├── FomodWizardSheet
│   ├── NewProjectSheet
│   └── AddressMapperSheet
│
└── Popovers
    ├── ProfilePickerPopover
    ├── ConflictResolutionPopover
    └── QuickLaunchPopover
```

## 3. Module Views

### 3.1 Mod Manager View

```swift
// Views/ModManager/ModManagerView.swift
struct ModManagerView: View {
    @StateObject private var viewModel = ModManagerViewModel()
    @State private var searchText = ""
    @State private var showInstallSheet = false
    @State private var showNexusBrowser = false
    
    var body: some View {
        HSplitView {
            // Left: Mod List
            ModListView(
                mods: viewModel.filteredMods,
                selection: $viewModel.selectedModId,
                onToggle: { mod in
                    Task { await viewModel.toggleMod(mod) }
                }
            )
            .frame(minWidth: 300, idealWidth: 350)
            
            // Right: Detail/Actions
            if let mod = viewModel.selectedMod {
                ModDetailView(
                    mod: mod,
                    onEnable: { Task { await viewModel.enableMod(mod) } },
                    onDisable: { Task { await viewModel.disableMod(mod) } },
                    onUninstall: { Task { await viewModel.uninstallMod(mod) } }
                )
            } else {
                ContentUnavailableView(
                    "Select a Mod",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Choose a mod from the list to view details")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search mods...")
        .onChange(of: searchText) { viewModel.filter(by: searchText) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Install", systemImage: "plus") {
                    showInstallSheet = true
                }
                
                Button("Nexus", systemImage: "globe") {
                    showNexusBrowser = true
                }
                
                Divider()
                
                ProfilePicker(
                    profiles: viewModel.profiles,
                    selection: $viewModel.activeProfile
                )
            }
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallModSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showNexusBrowser) {
            NexusBrowserView(onInstall: { mod in
                Task { await viewModel.installFromNexus(mod) }
            })
        }
    }
}

// Views/ModManager/ModListView.swift
struct ModListView: View {
    let mods: [Mod]
    @Binding var selection: UUID?
    let onToggle: (Mod) -> Void
    
    var body: some View {
        List(mods, selection: $selection) { mod in
            ModRowView(mod: mod, onToggle: { onToggle(mod) })
                .tag(mod.id)
        }
        .listStyle(.sidebar)
    }
}

// Views/ModManager/ModRowView.swift
struct ModRowView: View {
    let mod: Mod
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { mod.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .font(.headline)
                    .foregroundColor(mod.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 8) {
                    if let author = mod.author {
                        Text(author)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ModTypeBadge(types: mod.type)
                }
            }
            
            Spacer()
            
            Text("v\(mod.version)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// Views/ModManager/ModDetailView.swift
struct ModDetailView: View {
    let mod: Mod
    let onEnable: () -> Void
    let onDisable: () -> Void
    let onUninstall: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(mod.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        HStack {
                            Text("v\(mod.version)")
                            if let author = mod.author {
                                Text("•")
                                Text("by \(author)")
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    ModTypeBadge(types: mod.type)
                }
                
                Divider()
                
                // Actions
                HStack(spacing: 12) {
                    if mod.isEnabled {
                        Button("Disable", systemImage: "pause.circle") {
                            onDisable()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Enable", systemImage: "play.circle") {
                            onEnable()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button("Uninstall", systemImage: "trash", role: .destructive) {
                        onUninstall()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                
                // Details
                GroupBox("Details") {
                    LabeledContent("Installed", value: mod.installedAt.formatted())
                    LabeledContent("Staging Path", value: mod.stagingPath.lastPathComponent)
                    if let nexusId = mod.nexusId {
                        LabeledContent("Nexus ID", value: "\(nexusId)")
                    }
                }
                
                // Files
                GroupBox("Files") {
                    ModFilesListView(modId: mod.id)
                }
            }
            .padding()
        }
    }
}
```

### 3.2 Game Runner View

```swift
// Views/GameRunner/GameRunnerView.swift
struct GameRunnerView: View {
    @StateObject private var viewModel = GameRunnerViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Launch Configuration Panel
            GroupBox("Launch Configuration") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Game Path") {
                        HStack {
                            Text(viewModel.gamePath?.path ?? "Not configured")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Button("Browse...") {
                                viewModel.selectGamePath()
                            }
                        }
                    }
                    
                    LabeledContent("Profile") {
                        Picker("", selection: $viewModel.selectedProfile) {
                            ForEach(viewModel.profiles) { profile in
                                Text(profile.name).tag(profile as ModProfile?)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    DisclosureGroup("Advanced Options") {
                        Toggle("Enable Debug Agent", isOn: $viewModel.enableDebugAgent)
                        Toggle("Skip Intro Videos", isOn: $viewModel.skipIntro)
                        
                        LabeledContent("Launch Arguments") {
                            TextField("Arguments", text: $viewModel.launchArguments)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
            }
            .padding()
            
            Divider()
            
            // Status Area
            if let session = viewModel.activeSession {
                GameSessionView(session: session, viewModel: viewModel)
            } else {
                // Ready to launch
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("Ready to Launch")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    if let profile = viewModel.selectedProfile {
                        Text("\(profile.enabledModCount) mods enabled")
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        Task { await viewModel.launchGame() }
                    } label: {
                        Label("Launch Cyberpunk 2077", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.gamePath == nil)
                    
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Views/GameRunner/GameSessionView.swift
struct GameSessionView: View {
    let session: GameSession
    @ObservedObject var viewModel: GameRunnerViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Status Header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                
                Text(statusText)
                    .font(.headline)
                
                Spacer()
                
                Text("PID: \(session.pid)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(8)
            
            // Runtime Stats
            if case .running = session.status {
                HStack(spacing: 20) {
                    StatBox(title: "Uptime", value: viewModel.uptimeString)
                    StatBox(title: "CPU", value: viewModel.cpuUsage)
                    StatBox(title: "Memory", value: viewModel.memoryUsage)
                }
            }
            
            // Log Viewer
            GroupBox("Game Output") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.logLines) { line in
                            LogLineView(line: line)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            
            // Controls
            HStack {
                Button("Stop Game", systemImage: "stop.fill", role: .destructive) {
                    Task { await viewModel.stopGame() }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if viewModel.enableDebugAgent {
                    Button("Open Debugger", systemImage: "ant") {
                        viewModel.openDebugStudio()
                    }
                }
            }
        }
        .padding()
    }
    
    var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .terminated: return .orange
        case .crashed: return .red
        }
    }
    
    var statusText: String {
        switch session.status {
        case .running: return "Game Running"
        case .terminated(let code): return "Exited (code: \(code))"
        case .crashed(let signal): return "Crashed (signal: \(signal))"
        }
    }
}
```

### 3.3 Creation Studio View

```swift
// Views/CreationStudio/CreationStudioView.swift
struct CreationStudioView: View {
    @StateObject private var viewModel = CreationStudioViewModel()
    @State private var showNewProjectSheet = false
    
    var body: some View {
        HSplitView {
            // Project Navigator
            ProjectNavigatorView(
                project: viewModel.project,
                selection: $viewModel.selectedFile,
                onOpen: { file in viewModel.openFile(file) }
            )
            .frame(minWidth: 200, idealWidth: 250)
            
            // Editor Area
            VStack(spacing: 0) {
                // Tab Bar
                if !viewModel.openTabs.isEmpty {
                    EditorTabBar(
                        tabs: viewModel.openTabs,
                        selection: $viewModel.activeTabId,
                        onClose: { tab in viewModel.closeTab(tab) }
                    )
                }
                
                // Editor Content
                if let activeTab = viewModel.activeTab {
                    EditorView(file: activeTab, viewModel: viewModel)
                } else {
                    ContentUnavailableView(
                        "No File Open",
                        systemImage: "doc",
                        description: Text("Open a file from the navigator to edit")
                    )
                }
            }
            
            // Inspector Panel
            if let activeTab = viewModel.activeTab {
                InspectorPanelView(file: activeTab, viewModel: viewModel)
                    .frame(width: 280)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Project", systemImage: "folder.badge.plus") {
                    showNewProjectSheet = true
                }
                
                Button("Open Project", systemImage: "folder") {
                    viewModel.openProject()
                }
                
                Divider()
                
                Button("Build", systemImage: "hammer") {
                    Task { await viewModel.buildProject() }
                }
                .disabled(viewModel.project == nil)
                
                Button("Hot Reload", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await viewModel.hotReload() }
                }
                .disabled(!viewModel.canHotReload)
            }
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet(onCreate: { config in
                Task { await viewModel.createProject(config) }
            })
        }
    }
}

// Views/CreationStudio/EditorView.swift
struct EditorView: View {
    let file: ProjectFile
    @ObservedObject var viewModel: CreationStudioViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Editor based on file type
            switch file.fileType {
            case .yaml:
                TweakYamlEditorView(
                    content: Binding(
                        get: { file.content ?? "" },
                        set: { viewModel.updateFileContent(file, content: $0) }
                    ),
                    diagnostics: viewModel.diagnostics(for: file)
                )
                
            case .xl:
                ArchiveXLEditorView(
                    content: Binding(
                        get: { file.content ?? "" },
                        set: { viewModel.updateFileContent(file, content: $0) }
                    ),
                    diagnostics: viewModel.diagnostics(for: file)
                )
                
            case .reds:
                RedscriptEditorView(
                    content: Binding(
                        get: { file.content ?? "" },
                        set: { viewModel.updateFileContent(file, content: $0) }
                    )
                )
                
            case .cpp, .hpp:
                CppEditorView(
                    content: Binding(
                        get: { file.content ?? "" },
                        set: { viewModel.updateFileContent(file, content: $0) }
                    )
                )
                
            default:
                PlainTextEditorView(
                    content: Binding(
                        get: { file.content ?? "" },
                        set: { viewModel.updateFileContent(file, content: $0) }
                    )
                )
            }
            
            // Diagnostics Bar
            if let diagnostics = viewModel.diagnostics(for: file), !diagnostics.isEmpty {
                DiagnosticsBarView(diagnostics: diagnostics)
            }
        }
    }
}

// Views/CreationStudio/TweakYamlEditorView.swift
struct TweakYamlEditorView: View {
    @Binding var content: String
    let diagnostics: [Diagnostic]?
    
    @State private var showRecordBrowser = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CodeEditor(
                content: $content,
                language: .yaml,
                theme: .solarizedDark,
                lineNumbers: true,
                diagnostics: diagnostics
            )
            
            // Quick actions
            HStack {
                Button("Browse Records", systemImage: "list.bullet.rectangle") {
                    showRecordBrowser = true
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
        .popover(isPresented: $showRecordBrowser) {
            TweakDBRecordBrowserView(onSelect: { recordId in
                content += "\n\(recordId):\n  $type: \n"
            })
            .frame(width: 400, height: 500)
        }
    }
}

// Views/CreationStudio/InspectorPanelView.swift
struct InspectorPanelView: View {
    let file: ProjectFile
    @ObservedObject var viewModel: CreationStudioViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // File Info
                GroupBox("File Info") {
                    LabeledContent("Name", value: file.relativePath)
                    LabeledContent("Type", value: file.fileType.rawValue)
                    if let content = file.content {
                        LabeledContent("Size", value: "\(content.count) chars")
                    }
                }
                
                // Type-specific inspector
                switch file.fileType {
                case .yaml:
                    TweakYamlInspector(file: file, viewModel: viewModel)
                    
                case .xl:
                    ArchiveXLInspector(file: file, viewModel: viewModel)
                    
                default:
                    EmptyView()
                }
                
                // Validation Results
                if let diagnostics = viewModel.diagnostics(for: file) {
                    GroupBox("Validation") {
                        ForEach(diagnostics) { diagnostic in
                            DiagnosticRowView(diagnostic: diagnostic)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
```

### 3.4 Porting Studio View

```swift
// Views/PortingStudio/PortingStudioView.swift
struct PortingStudioView: View {
    @StateObject private var viewModel = PortingStudioViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Drop Zone / Source Selection
            if viewModel.analysisResult == nil {
                SourceSelectionView(viewModel: viewModel)
            } else {
                // Analysis Results
                PortingAnalysisView(
                    analysis: viewModel.analysisResult!,
                    viewModel: viewModel
                )
            }
        }
        .padding()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Analysis", systemImage: "arrow.counterclockwise") {
                    viewModel.reset()
                }
                .disabled(viewModel.analysisResult == nil)
                
                if let project = viewModel.activePortingProject {
                    Button("Save Project", systemImage: "square.and.arrow.down") {
                        Task { await viewModel.saveProject() }
                    }
                }
            }
        }
    }
}

// Views/PortingStudio/SourceSelectionView.swift
struct SourceSelectionView: View {
    @ObservedObject var viewModel: PortingStudioViewModel
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDragging ? Color.accentColor : Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 48))
                        .foregroundColor(isDragging ? .accentColor : .secondary)
                    
                    Text("Drop Windows Mod Here")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Supports .zip, .7z, .rar, .dll")
                        .foregroundColor(.secondary)
                    
                    Button("Or Browse Files...") {
                        viewModel.selectSourceFile()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(height: 250)
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }
            
            // Recent Projects
            if !viewModel.recentProjects.isEmpty {
                GroupBox("Recent Porting Projects") {
                    ForEach(viewModel.recentProjects) { project in
                        HStack {
                            Image(systemName: statusIcon(for: project.status))
                            Text(project.name)
                            Spacer()
                            Text(project.status.rawValue)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.openProject(project)
                        }
                    }
                }
                .frame(maxWidth: 500)
            }
            
            Spacer()
        }
    }
    
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            
            Task { @MainActor in
                await viewModel.analyzeSource(url)
            }
        }
        
        return true
    }
    
    func statusIcon(for status: PortingProject.Status) -> String {
        switch status {
        case .analyzing: return "magnifyingglass"
        case .mapping: return "arrow.triangle.2.circlepath"
        case .building: return "hammer"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

// Views/PortingStudio/PortingAnalysisView.swift
struct PortingAnalysisView: View {
    let analysis: PortingAnalysis
    @ObservedObject var viewModel: PortingStudioViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(analysis.modName)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        HStack {
                            PortabilityBadge(level: analysis.portabilityLevel)
                            
                            if let version = analysis.detectedVersion {
                                Text("v\(version)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Quick Actions
                    VStack(alignment: .trailing, spacing: 8) {
                        if analysis.isAutoPortable {
                            Button("Auto-Port Now", systemImage: "bolt.fill") {
                                Task { await viewModel.autoPort() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if analysis.hasNativeCode {
                            Button("Generate Scaffold", systemImage: "doc.badge.gearshape") {
                                Task { await viewModel.generateScaffold() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                Divider()
                
                // Detected Components
                GroupBox("Detected Components") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(analysis.components) { component in
                            ComponentRowView(component: component)
                        }
                    }
                }
                
                // Issues
                if !analysis.issues.isEmpty {
                    GroupBox("Issues to Address") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(analysis.issues) { issue in
                                IssueRowView(issue: issue)
                            }
                        }
                    }
                }
                
                // Address Mapping (for native plugins)
                if analysis.hasNativeCode {
                    GroupBox("Address Mapping") {
                        AddressMappingEditorView(
                            windowsAddresses: analysis.windowsAddresses,
                            macosAddresses: $viewModel.macosAddresses
                        )
                    }
                }
                
                // Files
                GroupBox("Files") {
                    FileTreeView(files: analysis.files)
                }
            }
            .padding()
        }
    }
}

// Views/PortingStudio/AddressMappingEditorView.swift
struct AddressMappingEditorView: View {
    let windowsAddresses: [AddressEntry]
    @Binding var macosAddresses: [UInt32: UInt64]
    
    @State private var searchText = ""
    
    var filteredAddresses: [AddressEntry] {
        if searchText.isEmpty {
            return windowsAddresses
        }
        return windowsAddresses.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Search
            TextField("Search addresses...", text: $searchText)
                .textFieldStyle(.roundedBorder)
            
            // Stats
            HStack {
                Text("\(windowsAddresses.count) addresses")
                Spacer()
                Text("\(macosAddresses.count) mapped")
                    .foregroundColor(
                        macosAddresses.count == windowsAddresses.count ? .green : .orange
                    )
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Table
            Table(filteredAddresses) {
                TableColumn("Name") { entry in
                    Text(entry.name)
                        .font(.system(.body, design: .monospaced))
                }
                
                TableColumn("Hash") { entry in
                    Text("0x\(String(entry.hash, radix: 16, uppercase: true))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                TableColumn("Windows Offset") { entry in
                    Text("0x\(String(entry.windowsOffset, radix: 16, uppercase: true))")
                        .font(.system(.body, design: .monospaced))
                }
                
                TableColumn("macOS Offset") { entry in
                    HStack {
                        if let offset = macosAddresses[entry.hash] {
                            Text("0x\(String(offset, radix: 16, uppercase: true))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                        } else {
                            Text("Not mapped")
                                .foregroundColor(.red)
                        }
                        
                        Button("Find", systemImage: "magnifyingglass") {
                            // Open address finder for this entry
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 300)
        }
    }
}
```

### 3.5 Debug Studio View

```swift
// Views/DebugStudio/DebugStudioView.swift
struct DebugStudioView: View {
    @StateObject private var viewModel = DebugStudioViewModel()
    
    var body: some View {
        HSplitView {
            // Left: Data Browser
            VStack(spacing: 0) {
                // Data Source Picker
                Picker("Data Source", selection: $viewModel.dataSource) {
                    Label("TweakDB", systemImage: "tray.full")
                        .tag(DebugDataSource.tweakDB)
                    Label("Hooks", systemImage: "arrow.triangle.branch")
                        .tag(DebugDataSource.hooks)
                    Label("Plugins", systemImage: "puzzlepiece.extension")
                        .tag(DebugDataSource.plugins)
                    Label("Memory", systemImage: "memorychip")
                        .tag(DebugDataSource.memory)
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Data View
                switch viewModel.dataSource {
                case .tweakDB:
                    TweakDBBrowserView(viewModel: viewModel)
                case .hooks:
                    HookMonitorView(viewModel: viewModel)
                case .plugins:
                    PluginInspectorView(viewModel: viewModel)
                case .memory:
                    MemoryInspectorView(viewModel: viewModel)
                }
            }
            .frame(minWidth: 400)
            
            // Right: Log Viewer
            VStack(spacing: 0) {
                // Log Filters
                HStack {
                    Text("Logs")
                        .font(.headline)
                    
                    Spacer()
                    
                    Picker("Level", selection: $viewModel.logLevelFilter) {
                        Text("All").tag(LogLevel?.none)
                        Text("Info").tag(LogLevel.info)
                        Text("Warning").tag(LogLevel.warning)
                        Text("Error").tag(LogLevel.error)
                    }
                    .frame(width: 100)
                    
                    Button("Clear", systemImage: "trash") {
                        viewModel.clearLogs()
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                // Log Content
                LogViewerView(logs: viewModel.filteredLogs)
            }
            .frame(minWidth: 350)
        }
        .toolbar {
            ToolbarItemGroup(placement: .status) {
                // Connection Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    
                    Text(viewModel.isConnected ? "Connected" : "Disconnected")
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh() }
                }
                .disabled(!viewModel.isConnected)
                
                Button("Connect", systemImage: "link") {
                    Task { await viewModel.connect() }
                }
                .disabled(viewModel.isConnected)
            }
        }
        .onAppear {
            Task { await viewModel.connect() }
        }
    }
}

// Views/DebugStudio/TweakDBBrowserView.swift
struct TweakDBBrowserView: View {
    @ObservedObject var viewModel: DebugStudioViewModel
    @State private var searchText = ""
    @State private var selectedRecord: TweakDBRecord?
    
    var body: some View {
        HSplitView {
            // Record List
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search records...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.regularMaterial)
                
                Divider()
                
                // Records
                List(viewModel.tweakDBRecords, selection: $selectedRecord) { record in
                    TweakDBRecordRowView(record: record)
                        .tag(record)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 250)
            
            // Record Detail
            if let record = selectedRecord {
                TweakDBRecordDetailView(
                    record: record,
                    onEdit: { field, value in
                        Task {
                            await viewModel.setTweakDBValue(
                                recordId: record.id,
                                field: field,
                                value: value
                            )
                        }
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a Record",
                    systemImage: "tray",
                    description: Text("Choose a TweakDB record to inspect")
                )
            }
        }
    }
}

// Views/DebugStudio/HookMonitorView.swift
struct HookMonitorView: View {
    @ObservedObject var viewModel: DebugStudioViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats Header
            HStack(spacing: 20) {
                StatBox(
                    title: "Active Hooks",
                    value: "\(viewModel.hookStats.activeCount)"
                )
                
                StatBox(
                    title: "Total Calls",
                    value: "\(viewModel.hookStats.totalCalls)"
                )
                
                StatBox(
                    title: "Avg Latency",
                    value: String(format: "%.2fms", viewModel.hookStats.avgLatency)
                )
            }
            .padding()
            
            Divider()
            
            // Hook List
            Table(viewModel.hookStats.hooks) {
                TableColumn("Function") { hook in
                    Text(hook.functionName)
                        .font(.system(.body, design: .monospaced))
                }
                
                TableColumn("Address") { hook in
                    Text("0x\(String(hook.address, radix: 16))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                TableColumn("Calls") { hook in
                    Text("\(hook.callCount)")
                }
                
                TableColumn("Last Call") { hook in
                    if let lastCall = hook.lastCallTime {
                        Text(lastCall.formatted())
                    } else {
                        Text("Never")
                            .foregroundColor(.secondary)
                    }
                }
                
                TableColumn("Avg Time") { hook in
                    Text(String(format: "%.3fms", hook.avgExecutionTime))
                }
                
                TableColumn("Status") { hook in
                    HStack {
                        Circle()
                            .fill(hook.isEnabled ? .green : .gray)
                            .frame(width: 8, height: 8)
                        
                        Text(hook.isEnabled ? "Active" : "Disabled")
                    }
                }
            }
        }
    }
}

// Views/DebugStudio/LogViewerView.swift
struct LogViewerView: View {
    let logs: [LogEntry]
    
    @State private var autoScroll = true
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(logs) { log in
                        LogEntryRowView(entry: log)
                            .id(log.id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .font(.system(.caption, design: .monospaced))
            .background(Color.black.opacity(0.9))
            .onChange(of: logs.count) { _ in
                if autoScroll, let lastLog = logs.last {
                    withAnimation {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(8)
                .background(.regularMaterial)
                .cornerRadius(6)
                .padding(8)
        }
    }
}

struct LogEntryRowView: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .foregroundColor(.secondary)
            
            Text(entry.level.symbol)
                .foregroundColor(entry.level.color)
            
            Text("[\(entry.source)]")
                .foregroundColor(.cyan)
            
            Text(entry.message)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }
}
```

## 4. Component Library

### 4.1 Reusable Components

```swift
// Views/Components/StatBox.swift
struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
        .padding()
        .background(.regularMaterial)
        .cornerRadius(8)
    }
}

// Views/Components/ModTypeBadge.swift
struct ModTypeBadge: View {
    let types: Set<ModType>
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(types).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                Text(type.shortName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(type.color.opacity(0.2))
                    .foregroundColor(type.color)
                    .cornerRadius(4)
            }
        }
    }
}

extension ModType {
    var shortName: String {
        switch self {
        case .archive: return "Archive"
        case .tweakXL: return "Tweak"
        case .archiveXL: return "AXL"
        case .redscript: return "Reds"
        case .red4ext: return "R4E"
        case .cyber: return "CET"
        case .unknown: return "?"
        }
    }
    
    var color: Color {
        switch self {
        case .archive: return .blue
        case .tweakXL: return .green
        case .archiveXL: return .orange
        case .redscript: return .purple
        case .red4ext: return .red
        case .cyber: return .gray
        case .unknown: return .secondary
        }
    }
}

// Views/Components/PortabilityBadge.swift
struct PortabilityBadge: View {
    let level: PortabilityLevel
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
            Text(level.text)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(level.color.opacity(0.2))
        .foregroundColor(level.color)
        .cornerRadius(6)
    }
}

enum PortabilityLevel {
    case fullyCompatible
    case autoPortable
    case requiresManualWork
    case notPortable
    
    var text: String {
        switch self {
        case .fullyCompatible: return "Fully Compatible"
        case .autoPortable: return "Auto-Portable"
        case .requiresManualWork: return "Requires Work"
        case .notPortable: return "Not Portable"
        }
    }
    
    var icon: String {
        switch self {
        case .fullyCompatible: return "checkmark.circle.fill"
        case .autoPortable: return "bolt.circle.fill"
        case .requiresManualWork: return "wrench.and.screwdriver"
        case .notPortable: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .fullyCompatible: return .green
        case .autoPortable: return .blue
        case .requiresManualWork: return .orange
        case .notPortable: return .red
        }
    }
}

// Views/Components/ProfilePicker.swift
struct ProfilePicker: View {
    let profiles: [ModProfile]
    @Binding var selection: ModProfile?
    
    var body: some View {
        Menu {
            ForEach(profiles) { profile in
                Button {
                    selection = profile
                } label: {
                    HStack {
                        Text(profile.name)
                        if profile == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Manage Profiles...", systemImage: "folder.badge.gearshape") {
                // Open profile manager
            }
        } label: {
            HStack {
                Image(systemName: "person.crop.circle")
                Text(selection?.name ?? "No Profile")
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
    }
}

// Views/Components/DiagnosticsBarView.swift
struct DiagnosticsBarView: View {
    let diagnostics: [Diagnostic]
    
    var errorCount: Int { diagnostics.filter { $0.severity == .error }.count }
    var warningCount: Int { diagnostics.filter { $0.severity == .warning }.count }
    
    var body: some View {
        HStack(spacing: 16) {
            if errorCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("\(errorCount) errors")
                }
            }
            
            if warningCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("\(warningCount) warnings")
                }
            }
            
            Spacer()
            
            Button("View All") {
                // Open diagnostics panel
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(
            errorCount > 0 ? Color.red.opacity(0.1) : Color.yellow.opacity(0.1)
        )
    }
}
```

## 5. View State Management

### 5.1 ViewModels

```swift
// ViewModels/ModManagerViewModel.swift
@MainActor
class ModManagerViewModel: ObservableObject {
    // Services
    private let modManager: ModManager
    private let nexusClient: NexusAPIClient
    
    // Published State
    @Published var mods: [Mod] = []
    @Published var selectedModId: UUID?
    @Published var profiles: [ModProfile] = []
    @Published var activeProfile: ModProfile?
    @Published var isLoading = false
    @Published var error: CyberModError?
    
    // Computed
    var selectedMod: Mod? {
        guard let id = selectedModId else { return nil }
        return mods.first { $0.id == id }
    }
    
    var filteredMods: [Mod] {
        // Apply filters and search
        mods
    }
    
    init(modManager: ModManager = .shared, nexusClient: NexusAPIClient = .shared) {
        self.modManager = modManager
        self.nexusClient = nexusClient
        
        Task { await loadData() }
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            mods = try await modManager.listMods()
            profiles = try await modManager.listProfiles()
            activeProfile = profiles.first { $0.isActive }
        } catch let error as CyberModError {
            self.error = error
        } catch {
            self.error = .installationFailed(reason: error.localizedDescription, suggestion: nil)
        }
    }
    
    func toggleMod(_ mod: Mod) async {
        do {
            if mod.isEnabled {
                try await modManager.disable(mod)
            } else {
                try await modManager.enable(mod)
            }
            await loadData()
        } catch {
            // Handle error
        }
    }
    
    func installFromNexus(_ listing: ModListing) async {
        guard let profile = activeProfile else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get download link
            let downloadUrl = try await nexusClient.getDownloadLink(
                nexusId: listing.nexusId,
                fileId: listing.mainFileId
            )
            
            // Download
            let localUrl = try await nexusClient.download(url: downloadUrl)
            
            // Install
            _ = try await modManager.install(
                .local(url: localUrl),
                profile: profile,
                options: .default
            )
            
            await loadData()
        } catch {
            // Handle error
        }
    }
}
```

## 6. Navigation Flow

```
┌────────────────┐
│   App Launch   │
└───────┬────────┘
        │
        ▼
┌────────────────┐     ┌────────────────┐
│  Check Setup   │────▶│ Setup Wizard   │──┐
│  (Game Path?)  │ No  │ (First Run)    │  │
└───────┬────────┘     └────────────────┘  │
        │ Yes                              │
        │◀─────────────────────────────────┘
        ▼
┌────────────────┐
│  Main Window   │
│  (Mod Manager) │
└───────┬────────┘
        │
        ├─────────────┬─────────────┬─────────────┬─────────────┐
        ▼             ▼             ▼             ▼             ▼
┌──────────────┐┌──────────────┐┌──────────────┐┌──────────────┐┌──────────────┐
│  Mod Manager ││ Game Runner  ││   Creation   ││   Porting    ││    Debug     │
│              ││              ││    Studio    ││    Studio    ││    Studio    │
│ • List mods  ││ • Launch     ││ • Projects   ││ • Analyze    ││ • TweakDB    │
│ • Install    ││ • Monitor    ││ • Edit files ││ • Map addrs  ││ • Hooks      │
│ • Profiles   ││ • Logs       ││ • Build      ││ • Generate   ││ • Memory     │
└──────┬───────┘└──────────────┘└──────┬───────┘└──────────────┘└──────┬───────┘
       │                               │                               │
       ▼                               ▼                               ▼
┌──────────────┐               ┌──────────────┐               ┌──────────────┐
│   Sheets:    │               │   Sheets:    │               │   Sheets:    │
│ • Install    │               │ • New Project│               │ • Export     │
│ • Nexus      │               │ • Templates  │               │ • Snapshot   │
│ • FOMOD      │               │ • Build Log  │               │              │
└──────────────┘               └──────────────┘               └──────────────┘
```
