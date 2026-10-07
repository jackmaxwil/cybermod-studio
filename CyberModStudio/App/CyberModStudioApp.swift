// CyberModStudioApp.swift - scenes, window layout, menu commands, drops and nxm:// links.

import AppKit
import CyberModKit
import CyberModModel
import SwiftUI

@main
struct CyberModStudioApp: App {
    @State private var model: AppModel = {
        // Game folder: $CP2077_GAME_DIR, else Settings (config.json game-dir), else the Steam folder. State folder:
        // $CYBERMOD_HOME, else ~/Library/Application Support/CyberModStudio. Both env vars let you try the app on a
        // fake game folder.
        var kit = Kit()
        kit.openURL = { url in DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
        return AppModel(kit: kit)
    }()
    @State private var navigator = Navigator()

    var body: some Scene {
        Window("CyberMod Studio", id: "main") {
            RootView()
                .environment(model)
                .environment(navigator)
                .frame(minWidth: 880, minHeight: 560)
                .onOpenURL { url in
                    // nxm:// links from Nexus Mods "Mod Manager Download", and files opened with the app.
                    navigator.screen = .library
                    Task { await model.open(url) }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands(model: model, navigator: navigator) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case play, library, loadOrder, discover, health, activity
    var id: Self { self }

    var title: String {
        switch self {
        case .play: "Play"
        case .library: "Library"
        case .loadOrder: "Load Order"
        case .discover: "Discover"
        case .health: "Health"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .play: "play.fill"
        case .library: "square.stack.3d.up"
        case .loadOrder: "list.number"
        case .discover: "magnifyingglass"
        case .health: "stethoscope"
        case .activity: "clock.arrow.circlepath"
        }
    }
}

/// Window-level UI state the menu commands also drive.
@MainActor @Observable
final class Navigator {
    var screen: Screen = Screen(rawValue: UserDefaults.standard.string(forKey: "screen") ?? "") ?? .play {
        didSet { UserDefaults.standard.set(screen.rawValue, forKey: "screen") }
    }
    var choosingFiles = false
    var addingLink = false
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var navigator = navigator
        NavigationSplitView {
            List(selection: Binding($navigator.screen)) {
                ForEach(Screen.allCases) { screen in
                    Label(screen.title, systemImage: screen.symbol)
                        .badge(badge(for: screen))
                        .tag(screen)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if let page = model.nexusWaiting {
                    NexusWaitingBanner(page: page)
                    Divider()
                }
                if let notice = model.notice {
                    NoticeBanner(notice: notice)
                    Divider()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(navigator.screen.title)
            .toolbar {
                ToolbarItem(placement: .status) { ActivityStatus() }
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(Label("Drop to install", systemImage: "arrow.down.doc").font(.title2).foregroundStyle(Color.accentColor))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            navigator.screen = .library
            Task { await model.add(urls: urls) }
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .fileImporter(isPresented: $navigator.choosingFiles, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            navigator.screen = .library
            Task { await model.add(urls: urls) }
        }
        .sheet(isPresented: $navigator.addingLink) { AddLinkSheet() }
        .alert(model.failure?.error.message ?? "", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }),
               presenting: model.failure) { failure in
            if let retry = failure.retry {
                Button(failure.retryTitle ?? "Retry", role: .destructive) { Task { await retry() } }
            }
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(describe(failure.error))
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !model.isBusy else { return }
            Task { await model.refresh() }
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigator.screen {
        case .play: PlayView()
        case .library: LibraryView()
        case .loadOrder: LoadOrderView()
        case .discover: DiscoverView()
        case .health: HealthView()
        case .activity: ActivityView()
        }
    }

    private func badge(for screen: Screen) -> Int {
        switch screen {
        case .library: model.updates.filter { $0.error == nil }.count
        case .loadOrder: model.conflicts.count
        case .health: model.problems.count
        default: 0
        }
    }
}

/// Paste a link: https, nexusmods.com page, nexus:<id>, nxm://, github:owner/repo, registry:<id> or a path.
struct AddLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Mod from a Link").font(.headline)
            TextField("Link or source", text: $text, prompt: Text("https://www.nexusmods.com/cyberpunk2077/mods/1234"))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 420)
                .onSubmit(add)
            Text("""
            Accepts a Nexus Mods page, nexus:1234, a "Mod Manager Download" nxm:// link, a GitHub repository \
            (github:owner/repo or its URL), registry:<id>, or a direct https:// download link.
            """)
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func add() {
        let input = text
        dismiss()
        Task { await model.add(input) }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    let navigator: Navigator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Mod from File…") { navigator.choosingFiles = true }
                .keyboardShortcut("o")
            Button("Add Mod from Link…") { navigator.addingLink = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            ForEach(Array(Screen.allCases.enumerated()), id: \.element) { index, screen in
                Button(screen.title) { navigator.screen = screen }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Button("Refresh") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isBusy)
        }
        CommandMenu("Game") {
            Button("Play") { model.startGame() }
                .keyboardShortcut("r")
                .disabled(model.isPlaying || model.playBlocker != nil)
            Button("Stop") { model.stopGame() }
                .keyboardShortcut(".")
                .disabled(!model.isPlaying)
            Divider()
            Button("Show game.log in Finder") { reveal([model.gameLogURL]) }
        }
        CommandMenu("Mods") {
            Button("Check for Updates") { Task { await model.checkForUpdates() } }
                .keyboardShortcut("u")
                .disabled(model.isBusy || model.mods.isEmpty)
            Button("Update All") { Task { await model.updateAll() } }
                .disabled(model.isBusy || model.isPlaying || !model.updates.contains { $0.error == nil })
            Divider()
            Button("Track Hand-Installed Mods") { Task { await model.adopt() } }
                .disabled(model.isBusy || model.isPlaying || model.unmanaged.isEmpty)
            Divider()
            Button("Cancel Current Task") { model.cancel() }
                .disabled(!model.isBusy)
        }
    }
}
