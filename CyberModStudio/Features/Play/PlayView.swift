// PlayView.swift - home: setup checklist until everything is ready, the Play button, and the game's output.

import AppKit
import CyberModKit
import CyberModModel
import SwiftUI

struct PlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !model.setupSteps.isEmpty { SetupChecklist() }
                if let exit = model.lastExit, exit.code != 0, !exit.stoppedByUser { ExitReport(exit: exit) }
                GameOutput()
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            gameIcon
            VStack(alignment: .leading, spacing: 4) {
                Text("Cyberpunk 2077").font(.title).fontWeight(.semibold)
                Text(summary).foregroundStyle(.secondary)
                healthPill
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                PlayButton()
                if let blocker = model.playBlocker, !model.isPlaying {
                    Text(blocker).font(.callout).foregroundStyle(.secondary)
                } else if model.findings.contains(where: { $0.id == "steam" && $0.level == .warning }), !model.isPlaying {
                    Label("Start Steam and sign in first, or your saves are missing.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder private var gameIcon: some View {
        let app = model.kit.game.appendingPathComponent("Cyberpunk2077.app")
        if FileManager.default.fileExists(atPath: app.path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 40)).foregroundStyle(.secondary).frame(width: 64, height: 64)
                .accessibilityHidden(true)
        }
    }

    private var summary: String {
        guard model.gameFound else { return "Game folder not found" }
        let loader = model.loaderInstalled ? "RED4ext \(model.loaderVersion ?? "")" : "Mod loader not installed"
        let enabled = model.mods.filter(\.enabled).count
        return "\(loader) · \(enabled) of \(model.mods.count) mod\(model.mods.count == 1 ? "" : "s") enabled"
    }

    private var healthPill: some View {
        let errors = model.findings.filter { $0.level == .error }.count
        let warnings = model.findings.filter { $0.level == .warning }.count
        let (text, level): (String, Finding.Level) = model.doctor == nil ? ("Checking…", .info)
            : errors > 0 ? ("\(errors) problem\(errors == 1 ? "" : "s")", .error)
            : warnings > 0 ? ("\(warnings) warning\(warnings == 1 ? "" : "s")", .warning)
            : ("All good", .ok)
        return Button { navigator.screen = .health } label: {
            Label(text, systemImage: level.symbol)
                .font(.callout)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(level.color.opacity(0.12), in: Capsule())
                .foregroundStyle(level.color)
        }
        .buttonStyle(.plain)
        .help("Open Health")
        .accessibilityLabel("Health: \(text)")
    }
}

struct PlayButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            switch model.play {
            case .idle:
                Button { model.startGame() } label: {
                    Label("Play", systemImage: "play.fill").frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.playBlocker != nil)
                .help("Start the game with mods (⌘R)")
            case .launching, .running, .stopping:
                status
                Button { model.stopGame() } label: { Label("Stop", systemImage: "stop.fill") }
                    .controlSize(.large)
                    .disabled(model.play == .stopping)
                    .help("Ask the game to quit (⌘.)")
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.play {
        case .running:
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").foregroundStyle(.green).font(.caption).accessibilityHidden(true)
                Text("Running")
                if let start = model.playStarted { Text(start, style: .timer).monospacedDigit().foregroundStyle(.secondary) }
            }
        case .stopping:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Stopping…") }
        default:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Starting… (compiling scripts)") }
        }
    }
}

/// First run: choose the game, install the loader, track hand-installed mods, add a first mod.
struct SetupChecklist: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var choosingGame = false
    @State private var choosingLoaderZip = false

    var body: some View {
        Card {
            Text("Get Set Up").font(.headline)
            ForEach(Array(model.setupSteps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Divider() }
                row(step)
            }
        }
    }

    @ViewBuilder private func row(_ step: SetupStep) -> some View {
        switch step {
        case .chooseGame:
            StepRow(symbol: "folder", title: "Choose your Cyberpunk 2077 folder",
                    detail: "Not found in \(model.kit.game.path). Pick the folder that contains Cyberpunk2077.app.") {
                Button("Choose Folder…") { choosingGame = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.gameFolderFromEnvironment)
                    .fileImporter(isPresented: $choosingGame, allowedContentTypes: [.folder]) { result in
                        if case .success(let url) = result { Task { await model.setGameFolder(url) } }
                    }
            }
        case .installLoader:
            StepRow(symbol: "puzzlepiece.extension", title: "Install the mod loader",
                    detail: "RED4ext for macOS with ArchiveXL, TweakXL and ModMenu, downloaded from GitHub and checked against its checksums.") {
                Button("Install") { Task { await model.installLoader() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                Button("From Zip…") { choosingLoaderZip = true }
                    .disabled(model.isBusy)
                    .fileImporter(isPresented: $choosingLoaderZip, allowedContentTypes: [.zip]) { result in
                        if case .success(let url) = result { Task { await model.installLoader(zip: url) } }
                    }
                    .help("Install a RED4ext-macOS-arm64-<version>.zip you downloaded")
            }
        case .adopt(let files):
            StepRow(symbol: "tray.and.arrow.down", title: "Track \(files) mod file\(files == 1 ? "" : "s") you installed by hand",
                    detail: "Then you can switch them on and off and remove them here. Nothing is moved.") {
                Button("Track Them") { Task { await model.adopt() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
            }
        case .addFirstMod:
            StepRow(symbol: "plus.circle", title: "Add your first mod",
                    detail: "Drop a .zip, .7z, .rar, folder or mod file anywhere in this window, or paste a Nexus Mods or GitHub link.") {
                Button("Choose File…") { navigator.choosingFiles = true }
                Button("Add from Link…") { navigator.addingLink = true }
            }
        }
    }
}

struct StepRow<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            actions
        }
        .accessibilityElement(children: .contain)
    }
}

/// After a failed launch: the launcher's compile errors and the report (crash reports, skipped plugins, log tails).
struct ExitReport: View {
    let exit: GameExit

    var body: some View {
        Card {
            HStack {
                Label(exit.compileErrors != nil ? "Scripts did not compile, so the game was not started"
                      : "The game stopped with status \(exit.code)", systemImage: "xmark.octagon.fill")
                    .font(.headline).foregroundStyle(.red)
                Spacer()
                Button("Copy Report") { copyToPasteboard((exit.compileErrors.map { $0 + "\n\n" } ?? "") + exit.report) }
            }
            Text(exit.compileErrors != nil
                 ? "Next: fix or remove the mod named in the errors below (Library), then play again."
                 : "Next: read the report below. Health checks the setup; a crash report names the mod or plugin that failed.")
                .font(.callout)
            ScrollView {
                Text((exit.compileErrors.map { $0 + "\n\n" } ?? "") + exit.report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
    }
}

/// Live output of the current (or last) session.
struct GameOutput: View {
    @Environment(AppModel.self) private var model
    @State private var errorsOnly = false

    var body: some View {
        Card {
            HStack {
                Text("Game Output").font(.headline)
                Spacer()
                Picker("Show", selection: $errorsOnly) {
                    Text("All").tag(false)
                    Text("Errors").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                Button("Copy", systemImage: "doc.on.doc") { copyToPasteboard(model.gameOutput.joined(separator: "\n")) }
                    .labelStyle(.iconOnly)
                    .help("Copy the output")
                    .disabled(model.gameOutput.isEmpty)
                Button("Show game.log in Finder", systemImage: "folder") { reveal([model.gameLogURL]) }
                    .labelStyle(.iconOnly)
                    .help("Show game.log in Finder")
            }
            let lines = errorsOnly ? model.gameOutput.filter(isError) : model.gameOutput
            if lines.isEmpty {
                Text(model.gameOutput.isEmpty
                     ? "The launcher's and game's output appears here when you play. It is also saved to \(model.gameLogURL.path)."
                     : "No errors so far.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(isError(line) ? .red : .primary)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160, maxHeight: 360)
                    .onChange(of: lines.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
    }

    private func isError(_ line: String) -> Bool {
        line.hasPrefix("[ERROR") || line.localizedCaseInsensitiveContains("error:") || line.hasPrefix("Not compiling")
    }
}
