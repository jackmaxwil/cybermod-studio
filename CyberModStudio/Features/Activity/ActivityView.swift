// ActivityView.swift - every action this session with its progress lines and result; cancel the running one.

import CyberModModel
import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.activities.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Installs, updates, fixes and play sessions show up here with their full output."))
            } else {
                List {
                    ForEach(model.activities.reversed()) { activity in
                        ActivityRow(activity: activity)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Clear Finished") { model.clearFinishedActivities() }
                    .disabled(!model.activities.contains { $0.status != .running })
            }
        }
    }
}

struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    let activity: Activity
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { expanded || activity.status == .running }, set: { expanded = $0 })) {
            VStack(alignment: .leading, spacing: 6) {
                if activity.lines.isEmpty {
                    Text("No output.").foregroundStyle(.secondary)
                } else {
                    Text(activity.lines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Copy") { copyToPasteboard(([activity.title] + activity.lines).joined(separator: "\n")) }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 8) {
                if activity.status == .running {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: activity.status.symbol).foregroundStyle(activity.status.color).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.title)
                    Text(activity.error?.message ?? activity.lines.last ?? activity.status.label)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(activity.started, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                if activity.status == .running {
                    Button("Cancel") { model.cancel() }.controlSize(.small)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(activity.status.label)
        }
    }
}
