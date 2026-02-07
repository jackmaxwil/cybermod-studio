// ModManagerView.swift - Full mod management interface

import SwiftUI
import CyberModCore

struct ModManagerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ModManagerViewModel()
    
    var body: some View {
        HSplitView {
            // Mod List
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    SearchField(text: $viewModel.searchText)
                        .frame(maxWidth: 300)
                    
                    Spacer()
                    
                    Menu {
                        Button("Install from File...") {
                            appState.showInstallSheet = true
                        }
                        Button("Browse Nexus Mods...") {
                            appState.showNexusBrowser = true
                        }
                        Divider()
                        Button("Refresh") {
                            Task { await viewModel.refreshMods() }
                        }
                    } label: {
                        Label("Actions", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Mod List
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredMods.isEmpty {
                    ContentUnavailableView(
                        "No Mods",
                        systemImage: "puzzlepiece.extension",
                        description: Text("Install mods to get started")
                    )
                } else {
                    List(selection: $viewModel.selectedModId) {
                        ForEach(viewModel.filteredMods) { mod in
                            ModRowView(mod: mod, viewModel: viewModel)
                                .tag(mod.id)
                        }
                        .onMove { source, destination in
                            viewModel.moveMods(from: source, to: destination)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 300, idealWidth: 400)
            
            // Detail View
            if let selectedMod = viewModel.selectedMod {
                ModDetailView(mod: selectedMod, viewModel: viewModel)
                    .frame(minWidth: 400)
            } else {
                ContentUnavailableView(
                    "Select a Mod",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Select a mod from the list to view details")
                )
                .frame(minWidth: 400)
            }
        }
        .task {
            await viewModel.loadMods()
        }
    }
}

// MARK: - Mod Row View

struct ModRowView: View {
    let mod: Mod
    @ObservedObject var viewModel: ModManagerViewModel
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { mod.isEnabled },
                set: { newValue in
                    Task {
                        if newValue {
                            try? await viewModel.enableMod(mod)
                        } else {
                            try? await viewModel.disableMod(mod)
                        }
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(mod.name)
                    .font(.headline)
                    .lineLimit(1)
                
                if let author = mod.author {
                    Text(author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Mod type badges
            HStack(spacing: 4) {
                ForEach(Array(mod.type.prefix(2)), id: \.self) { type in
                    Text(type.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
                if mod.type.count > 2 {
                    Text("+\(mod.type.count - 2)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(mod.isEnabled ? "Disable" : "Enable") {
                Task {
                    if mod.isEnabled {
                        try? await viewModel.disableMod(mod)
                    } else {
                        try? await viewModel.enableMod(mod)
                    }
                }
            }
            
            Divider()
            
            Button("Show in Finder") {
                NSWorkspace.shared.open(mod.stagingPath)
            }
            
            if let nexusUrl = mod.metadata?.nexusUrl {
                Button("View on Nexus") {
                    NSWorkspace.shared.open(nexusUrl)
                }
            }
            
            Divider()
            
            Button("Uninstall", role: .destructive) {
                Task {
                    try? await viewModel.uninstallMod(mod)
                }
            }
        }
    }
}

// MARK: - Mod Detail View

struct ModDetailView: View {
    let mod: Mod
    @ObservedObject var viewModel: ModManagerViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(mod.name)
                            .font(.title2)
                            .bold()
                        
                        Spacer()
                        
                        Toggle("Enabled", isOn: Binding(
                            get: { mod.isEnabled },
                            set: { newValue in
                                Task {
                                    if newValue {
                                        try? await viewModel.enableMod(mod)
                                    } else {
                                        try? await viewModel.disableMod(mod)
                                    }
                                }
                            }
                        ))
                    }
                    
                    if let author = mod.author {
                        Text("by \(author)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let version = mod.version, version != "1.0.0" {
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Description
                if let description = mod.description {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Mod Types
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mod Types")
                        .font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(Array(mod.type), id: \.self) { type in
                            Label(type.rawValue, systemImage: iconForModType(type))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
                
                // Dependencies
                if let dependencies = mod.metadata?.dependencies, !dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dependencies")
                            .font(.headline)
                        ForEach(dependencies, id: \.name) { dependency in
                            HStack {
                                Image(systemName: dependency.isRequired ? "exclamationmark.circle.fill" : "info.circle")
                                    .foregroundColor(dependency.isRequired ? .orange : .blue)
                                Text(dependency.name)
                                if let versionReq = dependency.versionRequirement {
                                    Text("(\(versionReq))")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                
                // Metadata
                VStack(alignment: .leading, spacing: 8) {
                    Text("Information")
                        .font(.headline)
                    
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("Installed:")
                                .foregroundColor(.secondary)
                            Text(mod.installedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        
                        if let nexusId = mod.nexusId {
                            GridRow {
                                Text("Nexus ID:")
                                    .foregroundColor(.secondary)
                                Text("\(nexusId)")
                            }
                        }
                    }
                    .font(.caption)
                }
                
                Divider()
                
                // Actions
                HStack {
                    Button("Uninstall", role: .destructive) {
                        Task {
                            try? await viewModel.uninstallMod(mod)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    if let nexusUrl = mod.metadata?.nexusUrl {
                        Button("View on Nexus") {
                            NSWorkspace.shared.open(nexusUrl)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(mod.stagingPath)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
    
    private func iconForModType(_ type: ModType) -> String {
        switch type {
        case .archive: return "archivebox"
        case .tweakXL: return "doc.text"
        case .archiveXL: return "doc.richtext"
        case .redscript: return "script"
        case .red4ext: return "puzzlepiece"
        case .cyber: return "laptopcomputer"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - View Model

@MainActor
class ModManagerViewModel: ObservableObject {
    @Published var mods: [Mod] = []
    @Published var selectedModId: UUID?
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    
    private let modManager = ModManager.shared
    
    var selectedMod: Mod? {
        guard let id = selectedModId else { return nil }
        return mods.first { $0.id == id }
    }
    
    var filteredMods: [Mod] {
        if searchText.isEmpty {
            return mods
        }
        return mods.filter { mod in
            mod.name.localizedCaseInsensitiveContains(searchText) ||
            mod.author?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    func loadMods() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            mods = try await modManager.listMods()
        } catch {
            print("Failed to load mods: \(error)")
        }
    }
    
    func refreshMods() async {
        await loadMods()
    }
    
    func enableMod(_ mod: Mod) async throws {
        try await modManager.enable(mod)
        await loadMods()
    }
    
    func disableMod(_ mod: Mod) async throws {
        try await modManager.disable(mod)
        await loadMods()
    }
    
    func uninstallMod(_ mod: Mod) async throws {
        try await modManager.uninstall(mod)
        if selectedModId == mod.id {
            selectedModId = nil
        }
        await loadMods()
    }
    
    func moveMods(from source: IndexSet, to destination: Int) {
        mods.move(fromOffsets: source, toOffset: destination)
        // TODO: Update load order in database
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Search Field

struct SearchField: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search mods...", text: $text)
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
}
