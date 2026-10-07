// DiscoverView.swift - add mods from a link, Nexus Mods (with the nxm:// handoff), and the community registry.

import AppKit
import CyberModKit
import CyberModModel
import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var link = ""
    @State private var search = ""
    @State private var handlesNXM = NXMHandler.isDefault

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Link", text: $link, prompt: Text("Nexus Mods page, nxm://, github:owner/repo, registry:<id> or https:// link"))
                        .labelsHidden()
                        .onSubmit(addLink)
                    Button("Add", action: addLink)
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy || model.isPlaying || !model.gameFound)
                }
            } header: {
                Text("Add from a Link")
            } footer: {
                Text("Or drop a downloaded .zip, .7z, .rar, folder or mod file anywhere in this window.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Nexus Mods") {
                HStack {
                    Text(model.nexusKeySaved ? "Your API key is saved." : "Add your personal API key to download from Nexus Mods.")
                    Spacer()
                    SettingsLink { Text(model.nexusKeySaved ? "Nexus Settings…" : "Add API Key…") }
                }
                if !handlesNXM {
                    HStack {
                        Label("\"Mod Manager Download\" links open \(NXMHandler.currentName.map { "in \($0)" } ?? "nowhere") right now.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Them Here") { Task { handlesNXM = await NXMHandler.makeDefault() } }
                    }
                }
                HStack {
                    Text("Find a mod on the website, then click \"Mod Manager Download\" (free accounts) or paste its page link above (Premium).")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Browse Nexus Mods") { NSWorkspace.shared.open(URL(string: "https://www.nexusmods.com/cyberpunk2077/mods/")!) }
                }
            }

            registrySection
        }
        .formStyle(.grouped)
        .task { await model.loadRegistry() }
        .task { model.checkNexusKey() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            handlesNXM = NXMHandler.isDefault
        }
    }

    @ViewBuilder private var registrySection: some View {
        Section {
            if model.registryURL.isEmpty {
                HStack {
                    Text("No mod registry set. A registry is a curated list of mods you can install with one click.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsLink { Text("Set Registry…") }
                }
            } else if let error = model.registryError {
                VStack(alignment: .leading, spacing: 4) {
                    Label(error.message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    Text("Next: \(error.hint)").font(.callout).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await model.loadRegistry() } }
                }
            } else {
                TextField("Search", text: $search, prompt: Text("Search the registry"))
                let results = search.isEmpty ? model.registry : model.registryIndex?.search(search) ?? []
                if results.isEmpty {
                    Text(model.registry.isEmpty ? "The registry lists no mods." : "Nothing found.").foregroundStyle(.secondary)
                }
                ForEach(results, id: \.id) { entry in RegistryRow(entry: entry) }
            }
        } header: {
            HStack {
                Text("Registry")
                Spacer()
                if !model.registryURL.isEmpty {
                    Button("Reload", systemImage: "arrow.clockwise") { Task { await model.loadRegistry() } }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Reload the registry")
                }
            }
        }
    }

    private func addLink() {
        let input = link
        link = ""
        Task { await model.add(input) }
    }
}

struct RegistryRow: View {
    @Environment(AppModel.self) private var model
    let entry: RegistryEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name).fontWeight(.medium)
                    Text(entry.version).foregroundStyle(.secondary)
                    if let author = entry.author { Text("by \(author)").foregroundStyle(.secondary) }
                }
                if let description = entry.description { Text(description).font(.callout) }
                if let requires = entry.requires, !requires.isEmpty {
                    Text("Needs \(requires.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let installed = model.mods.first(where: { $0.id == entry.id }) {
                Text(installed.version == entry.version ? "Installed" : "Installed \(installed.version ?? "")").foregroundStyle(.secondary)
            } else {
                Button("Install") { Task { await model.add("registry:\(entry.id)") } }
                    .disabled(model.isBusy || model.isPlaying || !model.gameFound)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Which app opens nxm:// links ("Mod Manager Download" on Nexus Mods). Info.plist declares the scheme.
enum NXMHandler {
    static let probe = URL(string: "nxm://cyberpunk2077")!

    static var isDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: probe)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static var currentName: String? {
        NSWorkspace.shared.urlForApplication(toOpen: probe).map { FileManager.default.displayName(atPath: $0.path) }
    }

    /// Asks macOS to open nxm:// links with this app (macOS may ask the user to confirm). Returns the new state.
    static func makeDefault() async -> Bool {
        try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "nxm")
        return isDefault
    }
}
