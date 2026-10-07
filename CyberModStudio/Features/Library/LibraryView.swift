// LibraryView.swift - installed mods: enable/disable, inspect, update, remove, add.

import AppKit
import CyberModKit
import CyberModModel
import SwiftUI

struct LibraryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All Mods", enabled = "Enabled", disabled = "Disabled", updates = "Updates", warnings = "With Warnings"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var selection = Set<ModRecord.ID>()
    @State private var sortOrder = [KeyPathComparator(\ModRecord.name, comparator: .localizedStandard)]
    @State private var search = ""
    @State private var filter = Filter.all
    @State private var showInspector = true
    @State private var removing: [String]?

    var body: some View {
        content
            .searchable(text: $search, placement: .toolbar, prompt: "Search mods")
            .inspector(isPresented: $showInspector) {
                ModInspector(mod: selectedMod, removing: $removing)
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
            }
            .toolbar { toolbar }
            .confirmationDialog(removalTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                presenting: removing) { ids in
                Button("Remove", role: .destructive) { Task { await model.remove(ids) } }
            } message: { _ in
                Text("Deletes exactly the files these mods installed in the game folder. This cannot be undone; disable a mod instead to keep it.")
            }
    }

    @ViewBuilder private var content: some View {
        if model.mods.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                if !model.unmanaged.isEmpty {
                    HStack {
                        Image(systemName: "tray.and.arrow.down").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                        Text("\(model.unmanaged.count) mod file(s) in the game folder were installed by hand.")
                        Spacer()
                        Button("Track Them") { Task { await model.adopt() } }.disabled(model.isBusy || model.isPlaying)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    Divider()
                }
                table
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Mods Yet", systemImage: "square.stack.3d.up")
        } description: {
            Text(model.unmanaged.isEmpty
                 ? "Drop a mod's .zip, .7z, .rar, folder or file anywhere in this window, or add one from a link."
                 : "\(model.unmanaged.count) mod file(s) in the game folder were installed by hand. Track them to manage them here.")
        } actions: {
            if !model.unmanaged.isEmpty {
                Button("Track Hand-Installed Mods") { Task { await model.adopt() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.isPlaying || !model.gameFound)
            }
            HStack {
                Button("Choose File…") { navigator.choosingFiles = true }
                Button("Add from Link…") { navigator.addingLink = true }
            }
            .disabled(!model.gameFound)
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("On") { mod in
                Toggle(mod.name, isOn: Binding(get: { mod.enabled }, set: { on in Task { await model.setEnabled(mod.id, on) } }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(model.isBusy || model.isPlaying)
                    .help(mod.enabled ? "Disable \(mod.name)" : "Enable \(mod.name)")
            }
            .width(28)
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { mod in
                Text(mod.name).foregroundStyle(mod.enabled ? .primary : .secondary)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Version") { mod in
                if let update = model.update(for: mod.id) {
                    Text("\(mod.version ?? "–") → \(update.available ?? "")").foregroundStyle(Color.accentColor)
                } else {
                    Text(mod.version ?? "–").foregroundStyle(.secondary)
                }
            }
            .width(min: 60, ideal: 90)
            TableColumn("Contents") { mod in
                HStack(spacing: 4) {
                    ForEach(ModKind.of(mod), id: \.self) { kind in
                        Image(systemName: kind.symbol).help(kind.rawValue).accessibilityLabel(kind.rawValue)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Source", value: \.sourceLabel) { mod in Text(mod.sourceLabel).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 90)
            TableColumn("Installed", value: \.installedAt) { mod in
                Text(mod.installedAt, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Status") { mod in status(mod) }
                .width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: ModRecord.ID.self) { ids in
            menu(for: Array(ids))
        } primaryAction: { _ in
            showInspector = true
        }
        .onDeleteCommand { if !selection.isEmpty { removing = Array(selection) } }
    }

    @ViewBuilder private func status(_ mod: ModRecord) -> some View {
        if model.update(for: mod.id) != nil {
            Label("Update", systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        } else if !mod.warnings.isEmpty {
            Label("\(mod.warnings.count) warning\(mod.warnings.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(mod.warnings.joined(separator: "\n"))
        } else if !mod.enabled {
            Label("Off", systemImage: "pause.circle").foregroundStyle(.secondary)
        } else {
            Label("OK", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func menu(for ids: [String]) -> some View {
        let mods = model.mods.filter { ids.contains($0.id) }
        let locked = model.isBusy || model.isPlaying
        if mods.contains(where: { !$0.enabled }) {
            Button("Enable") { Task { for mod in mods where !mod.enabled { await model.setEnabled(mod.id, true) } } }.disabled(locked)
        }
        if mods.contains(where: \.enabled) {
            Button("Disable") { Task { for mod in mods where mod.enabled { await model.setEnabled(mod.id, false) } } }.disabled(locked)
        }
        if let mod = mods.first, mods.count == 1 {
            if model.update(for: mod.id) != nil {
                Button("Update") { Task { await model.update(mod.id) } }.disabled(locked)
            }
            Button("Show Files in Finder") { reveal(mod.files.map { model.kit.game.appendingPathComponent($0.path) }) }
                .disabled(!mod.enabled)
            if let page = mod.sourcePage { Button("Open Mod Page") { NSWorkspace.shared.open(page) } }
        }
        Divider()
        Button("Remove…", role: .destructive) { removing = ids }.disabled(locked)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("From File…") { navigator.choosingFiles = true }
                Button("From Link…") { navigator.addingLink = true }
            } label: {
                Label("Add Mod", systemImage: "plus")
            }
            .help("Add a mod (⌘O, ⇧⌘O), or drop it on the window")
            .disabled(!model.gameFound || model.isPlaying)
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .help("Show only some mods")
            Button { Task { await model.checkForUpdates() } } label: {
                Label("Check for Updates", systemImage: "arrow.down.circle")
            }
            .help("Compare mods from GitHub, Nexus Mods and the registry with their source (⌘U)")
            .disabled(model.isBusy || model.mods.isEmpty)
            if model.updates.contains(where: { $0.error == nil }) {
                Button("Update All") { Task { await model.updateAll() } }
                    .disabled(model.isBusy || model.isPlaying)
            }
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                .help("Show or hide details")
        }
    }

    private var rows: [ModRecord] {
        model.mods.filter { mod in
            let matches = search.isEmpty || mod.name.localizedCaseInsensitiveContains(search) || mod.id.contains(search.lowercased())
            let kept = switch filter {
            case .all: true
            case .enabled: mod.enabled
            case .disabled: !mod.enabled
            case .updates: model.update(for: mod.id) != nil
            case .warnings: !mod.warnings.isEmpty
            }
            return matches && kept
        }
        .sorted(using: sortOrder)
    }

    private var selectedMod: ModRecord? {
        selection.count == 1 ? model.mods.first { $0.id == selection.first } : nil
    }

    private var removalTitle: String {
        guard let ids = removing else { return "" }
        if ids.count == 1, let mod = model.mods.first(where: { $0.id == ids[0] }) { return "Remove \(mod.name)?" }
        return "Remove \(ids.count) mods?"
    }
}

struct ModInspector: View {
    @Environment(AppModel.self) private var model
    let mod: ModRecord?
    @Binding var removing: [String]?

    var body: some View {
        if let mod {
            Form {
                Section {
                    LabeledContent("Name", value: mod.name)
                    LabeledContent("Id") { Text(mod.id).textSelection(.enabled) }
                    LabeledContent("Version", value: mod.version ?? "–")
                    LabeledContent("Status", value: mod.enabled ? "Enabled" : "Disabled")
                    LabeledContent("Installed") { Text(mod.installedAt, format: .dateTime) }
                    LabeledContent("Source") {
                        if let page = mod.sourcePage { Link(mod.source, destination: page) } else { Text(mod.source).textSelection(.enabled) }
                    }
                }
                if let update = model.update(for: mod.id) {
                    Section("Update") {
                        LabeledContent("Available", value: update.available ?? "")
                        Button("Update to \(update.available ?? "the newest version")") { Task { await model.update(mod.id) } }
                            .disabled(model.isBusy || model.isPlaying)
                    }
                }
                if !mod.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(mod.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                    }
                }
                Section("Files (\(mod.files.count))") {
                    ForEach(mod.files, id: \.path) { file in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            if let original = file.original {
                                Text("renamed from \(original) to change load order").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        Button("Show in Finder") { reveal(mod.files.map { model.kit.game.appendingPathComponent($0.path) }) }
                            .disabled(!mod.enabled)
                        Spacer()
                        Button("Remove…", role: .destructive) { removing = [mod.id] }
                            .disabled(model.isBusy || model.isPlaying)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right", description: Text("Select a mod to see its files and details."))
        }
    }
}
