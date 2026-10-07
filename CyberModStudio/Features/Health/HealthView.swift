// HealthView.swift - the doctor's findings with one-click fixes, and the mod loader.

import CyberModKit
import CyberModModel
import SwiftUI

struct HealthView: View {
    @Environment(AppModel.self) private var model
    @State private var choosingLoaderZip = false
    @State private var confirmingUninstall = false

    var body: some View {
        Form {
            let problems = model.problems
            let info = model.findings.filter { $0.level == .info }
            let ok = model.findings.filter { $0.level == .ok }
            Section {
                if model.doctor == nil {
                    HStack { ProgressView().controlSize(.small); Text("Checking…") }
                } else if problems.isEmpty {
                    Label("Everything checks out.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                ForEach(problems, id: \.id) { FindingRow(finding: $0) }
            } header: {
                Text("Needs Attention")
            }
            if !info.isEmpty {
                Section("Information") { ForEach(info, id: \.id) { FindingRow(finding: $0) } }
            }
            if !ok.isEmpty {
                Section("Working") { ForEach(ok, id: \.id) { FindingRow(finding: $0) } }
            }
            Section("Mod Loader") {
                LabeledContent("RED4ext for macOS", value: model.loaderInstalled ? (model.loaderVersion ?? "installed") : "Not installed")
                HStack {
                    Button(model.loaderInstalled ? "Update" : "Install") {
                        Task { await model.installLoader(onlyIfNewer: model.loaderInstalled) }
                    }
                    .help("Download the newest release from GitHub, verify it and install it")
                    Button("Install from Zip…") { choosingLoaderZip = true }
                        .fileImporter(isPresented: $choosingLoaderZip, allowedContentTypes: [.zip]) { result in
                            if case .success(let url) = result { Task { await model.installLoader(zip: url) } }
                        }
                    Spacer()
                    if model.loaderInstalled {
                        Button("Remove…", role: .destructive) { confirmingUninstall = true }
                    }
                }
                .disabled(model.isBusy || model.isPlaying || !model.gameFound)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup {
                let fixes = model.problems.compactMap(\.fix).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                Button("Fix All") {
                    Task {
                        for fix in fixes {
                            await model.fix(fix)
                            if model.failure != nil { break }
                        }
                    }
                }
                .help("Apply every available fix, one after another")
                .disabled(fixes.isEmpty || model.isBusy || model.isPlaying)
                Button { Task { await model.refresh() } } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                    .help("Check again (⇧⌘R)")
                    .disabled(model.refreshing)
            }
        }
        .confirmationDialog("Remove the mod loader?", isPresented: $confirmingUninstall) {
            Button("Remove", role: .destructive) { Task { await model.uninstallLoader() } }
        } message: {
            Text("Removes RED4ext and its plugins and puts the original game binary back. Your mods stay; Steam's Play button starts the game without mods.")
        }
    }
}

struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.level.symbol)
                .foregroundStyle(finding.level.color)
                .accessibilityLabel(finding.level.label)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.message).textSelection(.enabled)
                if let hint = finding.hint, finding.level != .ok {
                    Text("Next: \(hint)").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let details = finding.details, !details.isEmpty {
                    DisclosureGroup("\(details.count) detail\(details.count == 1 ? "" : "s")") {
                        Text(details.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }
            }
            Spacer()
            if let fix = finding.fix {
                Button(fixTitle(fix)) { Task { await model.fix(fix) } }
                    .disabled(model.isBusy || model.isPlaying)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
