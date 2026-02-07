// NexusBrowserSheet.swift - Nexus Mods browser and download interface

import SwiftUI
import CyberModCore

struct NexusBrowserSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = NexusBrowserViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    SearchField(text: $viewModel.searchQuery)
                        .onSubmit {
                            Task { await viewModel.search() }
                        }
                    
                    Button("Search") {
                        Task { await viewModel.search() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSearching)
                }
                .padding()
                
                Divider()
                
                // Results
                if viewModel.isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.searchResults) { mod in
                                NexusModCard(mod: mod, viewModel: viewModel)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Browse Nexus Mods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 900, height: 700)
        .task {
            if viewModel.searchResults.isEmpty {
                await viewModel.loadTrending()
            }
        }
    }
}

// MARK: - Nexus Mod Card

struct NexusModCard: View {
    let mod: NexusMod
    @ObservedObject var viewModel: NexusBrowserViewModel
    @State private var showFilePicker = false
    @State private var selectedFile: NexusFile?
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Thumbnail
            AsyncImage(url: mod.pictureUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    }
            }
            .frame(width: 120, height: 80)
            .cornerRadius(8)
            .clipped()
            
            // Mod Info
            VStack(alignment: .leading, spacing: 8) {
                Text(mod.name)
                    .font(.headline)
                    .lineLimit(2)
                
                if let summary = mod.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 16) {
                    Label("\(mod.endorsements)", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(mod.totalDownloads)", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let author = mod.author {
                        Text("by \(author)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 8) {
                Button("View Files") {
                    showFilePicker = true
                }
                .buttonStyle(.bordered)
                
                if let nexusUrl = mod.nexusUrl {
                    Link("Open on Nexus", destination: nexusUrl)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(isPresented: $showFilePicker) {
            if let files = viewModel.modFiles[mod.id] {
                NexusFilePickerSheet(
                    mod: mod,
                    files: files,
                    onSelect: { file in
                        selectedFile = file
                        Task {
                            await viewModel.downloadMod(mod: mod, file: file)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - File Picker Sheet

struct NexusFilePickerSheet: View {
    let mod: NexusMod
    let files: [NexusFile]
    let onSelect: (NexusFile) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List(files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.headline)
                    
                    HStack {
                        if let version = file.version {
                            Text("v\(version)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(formatFileSize(file.sizeInBytes))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if file.isPrimary {
                            Text("Primary")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(file)
                    dismiss()
                }
            }
            .navigationTitle("Select File - \(mod.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - View Model

@MainActor
class NexusBrowserViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [NexusMod] = []
    @Published var modFiles: [Int: [NexusFile]] = [:]
    @Published var isSearching: Bool = false
    @Published var downloadProgress: [Int: Double] = [:]
    
    private let apiClient = NexusAPIClient.shared
    private let gameDomain = "cyberpunk2077"
    
    func loadTrending() async {
        isSearching = true
        defer { isSearching = false }
        
        do {
            let result = try await apiClient.searchMods(
                gameDomain: gameDomain,
                sortBy: "downloads",
                limit: 20
            )
            searchResults = result.results
        } catch {
            print("Failed to load trending mods: \(error)")
        }
    }
    
    func search() async {
        guard !searchQuery.isEmpty else {
            await loadTrending()
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            let result = try await apiClient.searchMods(
                gameDomain: gameDomain,
                query: searchQuery,
                limit: 50
            )
            searchResults = result.results
        } catch {
            print("Search failed: \(error)")
        }
    }
    
    func loadModFiles(modId: Int) async {
        guard modFiles[modId] == nil else { return }
        
        do {
            let files = try await apiClient.getModFiles(
                gameDomain: gameDomain,
                modId: modId
            )
            modFiles[modId] = files
        } catch {
            print("Failed to load mod files: \(error)")
        }
    }
    
    func downloadMod(mod: NexusMod, file: NexusFile) async {
        do {
            // Get download link
            let downloadLink = try await apiClient.getDownloadLink(
                gameDomain: gameDomain,
                modId: mod.nexusModId,
                fileId: file.fileId
            )
            
            // Choose save location
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = file.name
            savePanel.allowedContentTypes = [.zip, .archive]
            
            guard savePanel.runModal() == .OK, let destination = savePanel.url else {
                return
            }
            
            // Download with progress
            downloadProgress[mod.id] = 0.0
            
            try await apiClient.downloadFile(
                url: downloadLink.uri,
                to: destination
            ) { downloaded, total in
                Task { @MainActor in
                    if total > 0 {
                        self.downloadProgress[mod.id] = Double(downloaded) / Double(total)
                    }
                }
            }
            
            downloadProgress[mod.id] = nil
            
            // TODO: Trigger mod installation flow
            print("Downloaded to: \(destination.path)")
            
        } catch {
            print("Download failed: \(error)")
            downloadProgress[mod.id] = nil
        }
    }
}
