// Components.swift - small presentation helpers shared by the screens (no mod logic).

import AppKit
import CyberModKit
import CyberModModel
import SwiftUI

extension Finding.Level {
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }

    var label: String {
        switch self {
        case .ok: "OK"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Problem"
        }
    }
}

extension Activity.Status {
    var symbol: String {
        switch self {
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .waiting: "hourglass"
        }
    }

    var color: Color {
        switch self {
        case .running, .waiting: .accentColor
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    var label: String {
        switch self {
        case .running: "Running"
        case .succeeded: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .waiting: "Waiting"
        }
    }
}

/// What a mod contains, from where its files went (for the Library's type column).
enum ModKind: String, CaseIterable {
    case archive = "Archive", tweak = "Tweak", script = "Script", plugin = "Plugin", input = "Input"

    var symbol: String {
        switch self {
        case .archive: "shippingbox"
        case .tweak: "slider.horizontal.3"
        case .script: "chevron.left.forwardslash.chevron.right"
        case .plugin: "puzzlepiece.extension"
        case .input: "keyboard"
        }
    }

    static func of(_ mod: ModRecord) -> [ModKind] {
        let paths = mod.files.map { $0.path.lowercased() }
        return allCases.filter { kind in
            let prefix = switch kind {
            case .archive: "archive/"
            case .tweak: "r6/tweaks/"
            case .script: "r6/scripts/"
            case .plugin: "red4ext/"
            case .input: "r6/input/"
            }
            return paths.contains { $0.hasPrefix(prefix) }
        }
    }
}

extension ModRecord {
    /// "Nexus Mods", "GitHub" ... for the source column.
    var sourceLabel: String {
        let source = source.lowercased()
        if source.hasPrefix("nexus:") { return "Nexus Mods" }
        if source.hasPrefix("github:") { return "GitHub" }
        if source.hasPrefix("registry:") { return "Registry" }
        if source == "adopted" { return "By hand" }
        if source.hasPrefix("https://") { return "Web" }
        return "File"
    }

    /// The web page the mod came from, when there is one.
    var sourcePage: URL? {
        let parts = source.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "nexus":
            return parts[1].split(separator: "/").first.flatMap { URL(string: "https://www.nexusmods.com/cyberpunk2077/mods/\($0)") }
        case "github":
            return parts[1].split(separator: "@").first.flatMap { URL(string: "https://github.com/\($0)") }
        case "https":
            return URL(string: source)
        default:
            return nil
        }
    }
}

/// Fix ids from `Doctor` as button titles.
func fixTitle(_ fix: String) -> String {
    switch fix {
    case "install-loader": "Install Mod Loader"
    case "rerun-setup": "Re-run Setup"
    case "move-nested-archives": "Move Archives"
    case "move-misplaced-xl": "Move .xl Files"
    case "remove-duplicate-archives": "Move Duplicates Out"
    case "adopt": "Track Mods"
    default: "Fix"
    }
}

/// A KitError as alert text: details, then what to do next.
func describe(_ error: KitError) -> String {
    var text = ""
    let details = error.details.prefix(8)
    if !details.isEmpty { text += details.joined(separator: "\n") + (error.details.count > 8 ? "\n… and \(error.details.count - 8) more" : "") + "\n\n" }
    return text + "Next: \(error.hint)"
}

func reveal(_ urls: [URL]) {
    let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    if existing.isEmpty, let parent = urls.first?.deletingLastPathComponent() {
        NSWorkspace.shared.open(parent)
    } else {
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// A rounded panel like the grouped sections of System Settings.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// Status of the running activity for the toolbar, with Cancel.
struct ActivityStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let current = model.current {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 0) {
                    Text(current.title).font(.callout).lineLimit(1)
                    if let line = current.lines.last {
                        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: 260, alignment: .leading)
                Button("Cancel", systemImage: "xmark.circle.fill") { model.cancel() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Cancel \(current.title)")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(current.title) in progress")
        }
    }
}

/// The last finished action's result, with its warnings, until dismissed.
struct NoticeBanner: View {
    @Environment(AppModel.self) private var model
    let notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).fontWeight(.medium)
                ForEach(notice.lines.prefix(6), id: \.self) { line in
                    Text(line).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer()
            Button("Dismiss", systemImage: "xmark") { model.notice = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.green.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

/// A non-Premium Nexus download waiting for the "Mod Manager Download" click in the browser.
struct NexusWaitingBanner: View {
    @Environment(AppModel.self) private var model
    let page: URL

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for Nexus Mods").fontWeight(.medium)
                Text("On the page that opened, click \"Mod Manager Download\", then \"Slow download\". The mod installs here when your browser hands over the link.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Page Again") { NSWorkspace.shared.open(page) }
            Button("Stop Waiting") { model.nexusWaiting = nil }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }
}
