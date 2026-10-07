// LoadOrderView.swift - archives in the order ArchiveXL loads them, who wins each overlap, and changing priority.

import CyberModKit
import CyberModModel
import SwiftUI

struct LoadOrderView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Archives load in name order and the first one wins any file it shares with a later one. "
                  + "To let an archive win, CyberMod Studio renames it with a \"!\" prefix; updating or removing the mod undoes that. "
                  + "Changes take effect the next time you play.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if model.archives.isEmpty {
                ContentUnavailableView("No Archive Mods", systemImage: "list.number",
                                       description: Text(".archive mods in archive/pc/mod appear here in the order they load."))
            } else {
                HSplitView {
                    archiveTable.frame(minWidth: 360)
                    conflictList.frame(minWidth: 280, idealWidth: 340)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { moveUp() } label: { Label("Move Up", systemImage: "arrow.up") }
                    .help("Load the selected archive before the one above it")
                    .disabled(!canMoveUp)
                Button { moveToTop() } label: { Label("Move to Top", systemImage: "arrow.up.to.line") }
                    .help("Load the selected archive first")
                    .disabled(!canMoveUp)
            }
        }
    }

    private var archiveTable: some View {
        Table(model.archives, selection: $selection) {
            TableColumn("#") { entry in Text("\(entry.rank)").monospacedDigit().foregroundStyle(.secondary) }
                .width(36)
            TableColumn("Archive") { entry in
                HStack(spacing: 6) {
                    Text(entry.file)
                    let wins = model.conflicts.filter { $0.winner == entry.file }.count
                    let loses = model.conflicts.filter { $0.loser == entry.file }.count
                    if wins > 0 {
                        Image(systemName: "crown.fill").foregroundStyle(.yellow).help("Wins over \(wins) archive(s)")
                            .accessibilityLabel("wins over \(wins) archives")
                    }
                    if loses > 0 {
                        Image(systemName: "arrow.down.right.circle").foregroundStyle(.orange).help("Overridden by \(loses) archive(s)")
                            .accessibilityLabel("overridden by \(loses) archives")
                    }
                }
            }
            TableColumn("Mod") { entry in
                Text(entry.mod.flatMap { id in model.mods.first { $0.id == id }?.name } ?? "Installed by hand")
                    .foregroundStyle(entry.mod == nil ? .secondary : .primary)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first {
                Button("Move Up") { selection = id; moveUp() }.disabled(!canMove(id))
                Button("Move to Top") { selection = id; moveToTop() }.disabled(!canMove(id))
            }
        }
    }

    private var conflictList: some View {
        List {
            Section("Overlaps (\(model.conflicts.count))") {
                if model.conflicts.isEmpty {
                    Text("No two archives replace the same file.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.conflicts.enumerated()), id: \.offset) { _, conflict in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("**\(conflict.winner)** wins over **\(conflict.loser)**")
                        Text("\(conflict.files) shared file\(conflict.files == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        Button("Let \(conflict.loser) Win") { Task { await model.prioritize(conflict.loser, over: conflict.winner) } }
                            .controlSize(.small)
                            .disabled(model.isBusy || model.isPlaying)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func index(of id: String?) -> Int? { model.archives.firstIndex { $0.file == id } }
    private func canMove(_ id: String) -> Bool { (index(of: id) ?? 0) > 0 && !model.isBusy && !model.isPlaying }
    private var canMoveUp: Bool { selection.map(canMove) ?? false }

    private func moveUp() {
        guard let selection, let i = index(of: selection), i > 0 else { return }
        let above = model.archives[i - 1].file
        Task { await model.prioritize(selection, over: above) }
        self.selection = nil
    }

    private func moveToTop() {
        guard let selection, let first = model.archives.first?.file, first != selection else { return }
        Task { await model.prioritize(selection, over: first) }
        self.selection = nil
    }
}
