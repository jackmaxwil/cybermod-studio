// SettingsView.swift - game folder, Nexus Mods API key and nxm:// links, mod registry.

import AppKit
import CyberModKit
import CyberModModel
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            NexusSettings().tabItem { Label("Nexus Mods", systemImage: "arrow.down.circle") }
            RegistrySettings().tabItem { Label("Registry", systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var choosing = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Game folder") {
                    Text(model.kit.game.path)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if !model.gameFound {
                    Label("Cyberpunk2077.app is not in this folder.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.open(model.kit.game) }.disabled(!model.gameFound)
                    Button("Choose…") { choosing = true }
                        .disabled(model.gameFolderFromEnvironment || model.isBusy || model.isPlaying)
                        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                            if case .success(let url) = result { Task { await model.setGameFolder(url) } }
                        }
                }
            } footer: {
                Text(model.gameFolderFromEnvironment ? "Set by the CP2077_GAME_DIR environment variable."
                     : "The folder that contains Cyberpunk2077.app. Steam: right-click the game > Manage > Browse local files.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Data folder") {
                    Text(model.kit.home.path).font(.system(.body, design: .monospaced)).lineLimit(2).truncationMode(.middle)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.open(model.kit.home) }
                        .disabled(!FileManager.default.fileExists(atPath: model.kit.home.path))
                }
            } footer: {
                Text("Settings, the list of files each mod installed, and disabled mods. The cybermod command-line tool uses the same folder.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct NexusSettings: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var account: String?
    @State private var saving = false
    @State private var handlesNXM = NXMHandler.isDefault

    var body: some View {
        Form {
            Section {
                SecureField("API key", text: $key, prompt: Text(model.nexusKeySaved ? "Saved in your Keychain" : "Paste your personal API key"))
                HStack {
                    if let account { Label(account, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    Spacer()
                    if model.nexusKeySaved {
                        Button("Remove Key") { model.removeNexusKey(); account = nil; key = "" }
                    }
                    Button("Save") {
                        saving = true
                        Task {
                            if let user = await model.saveNexusKey(key) {
                                account = "Saved for \(user.name) (\(user.is_premium ? "Premium: direct downloads" : "free account: use Mod Manager Download"))"
                                key = ""
                            }
                            saving = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            } header: {
                Text("API Key")
            } footer: {
                HStack(spacing: 4) {
                    Text("Copy it from the bottom of")
                    Link("nexusmods.com > Site preferences > API Keys", destination: URL(string: "https://www.nexusmods.com/users/myaccount?tab=api")!)
                    Text(". Kept in your Keychain.")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("nxm:// links open in", value: NXMHandler.currentName ?? "no app")
                HStack {
                    Spacer()
                    Button("Open nxm:// Links with CyberMod Studio") { Task { handlesNXM = await NXMHandler.makeDefault() } }
                        .disabled(handlesNXM)
                }
            } header: {
                Text("Mod Manager Download")
            } footer: {
                Text("Free Nexus accounts download through the \"Mod Manager Download\" button, which hands an nxm:// link to the app set here. Vortex and other managers may claim these links too.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { model.checkNexusKey() }
    }
}

struct RegistrySettings: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""

    var body: some View {
        Form {
            Section {
                TextField("Registry address", text: $url, prompt: Text("https://example.com/cyberpunk-mods/index.json"))
                HStack {
                    Spacer()
                    Button("Save") { Task { await model.setRegistryURL(url) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(url == model.registryURL)
                }
            } header: {
                Text("Mod Registry")
            } footer: {
                Text("A JSON index of mods (https:// or file://) that Discover lists for one-click install. Leave empty for none.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { url = model.registryURL }
    }
}
