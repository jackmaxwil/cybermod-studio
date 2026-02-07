// FomodInstallerSheet.swift - FOMOD installation wizard

import SwiftUI
import CyberModCore

struct FomodInstallerSheet: View {
    @Environment(\.dismiss) var dismiss
    let sessionId: UUID
    @StateObject private var viewModel: FomodInstallerViewModel
    
    init(sessionId: UUID) {
        self.sessionId = sessionId
        _viewModel = StateObject(wrappedValue: FomodInstallerViewModel(sessionId: sessionId))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                if let stepData = viewModel.currentStepData {
                    ProgressView(value: Double(stepData.stepIndex + 1), total: Double(stepData.totalSteps))
                        .padding()
                }
                
                Divider()
                
                // Step content
                if let stepData = viewModel.currentStepData {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(stepData.stepName)
                                .font(.title2)
                                .bold()
                                .padding(.bottom, 8)
                            
                            ForEach(stepData.groups, id: \.id) { group in
                                FomodGroupView(
                                    group: group,
                                    selectedOptions: viewModel.getSelectedOptions(for: group.id),
                                    onSelectionChanged: { options in
                                        viewModel.selectOptions(groupId: group.id, options: options)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                } else {
                    ProgressView("Loading installer...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Divider()
                
                // Navigation buttons
                HStack {
                    Button("Cancel") {
                        Task {
                            await viewModel.cancel()
                            dismiss()
                        }
                    }
                    
                    Spacer()
                    
                    if viewModel.canGoBack {
                        Button("Back") {
                            Task {
                                await viewModel.goBack()
                            }
                        }
                    }
                    
                    if viewModel.canAdvance {
                        Button("Next") {
                            Task {
                                await viewModel.advance()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Install") {
                            Task {
                                await viewModel.complete()
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("FOMOD Installer")
            .frame(width: 700, height: 600)
        }
        .task {
            await viewModel.loadSession()
        }
    }
}

// MARK: - FOMOD Group View

struct FomodGroupView: View {
    let group: GroupData
    let selectedOptions: Set<String>
    let onSelectionChanged: (Set<String>) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.name)
                .font(.headline)
            
            Text(groupTypeDescription(group.type))
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.options, id: \.id) { option in
                    FomodOptionView(
                        option: option,
                        isSelected: selectedOptions.contains(option.id),
                        selectionType: group.type,
                        onToggle: {
                            var newSelection = selectedOptions
                            if newSelection.contains(option.id) {
                                newSelection.remove(option.id)
                            } else {
                                switch group.type {
                                case .selectExactlyOne, .selectAtMostOne:
                                    newSelection = [option.id]
                                default:
                                    newSelection.insert(option.id)
                                }
                            }
                            onSelectionChanged(newSelection)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func groupTypeDescription(_ type: FomodGroupType) -> String {
        switch type {
        case .selectExactlyOne:
            return "Select exactly one option"
        case .selectAtMostOne:
            return "Select at most one option (optional)"
        case .selectAtLeastOne:
            return "Select at least one option"
        case .selectAll:
            return "All options will be installed"
        case .selectAny:
            return "Select any combination of options"
        }
    }
}

// MARK: - FOMOD Option View

struct FomodOptionView: View {
    let option: OptionData
    let isSelected: Bool
    let selectionType: FomodGroupType
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator
                Group {
                    switch selectionType {
                    case .selectExactlyOne, .selectAtMostOne:
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                    default:
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                    }
                }
                .font(.title3)
                
                // Option content
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    if let description = option.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                // Image if available
                if let imagePath = option.imagePath {
                    AsyncImage(url: URL(fileURLWithPath: imagePath)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 80, height: 60)
                    .cornerRadius(6)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Model

@MainActor
class FomodInstallerViewModel: ObservableObject {
    @Published var currentStepData: StepData?
    @Published var canGoBack: Bool = false
    @Published var canAdvance: Bool = false
    @Published var choices: [String: Set<String>] = [:] // groupId -> selected option IDs
    
    private let sessionId: UUID
    private let sessionManager = FomodSessionManager.shared
    
    init(sessionId: UUID) {
        self.sessionId = sessionId
    }
    
    func loadSession() async {
        guard var session = await sessionManager.getSession(sessionId) else {
            return
        }
        
        updateState(from: session)
    }
    
    func getSelectedOptions(for groupId: String) -> Set<String> {
        choices[groupId] ?? []
    }
    
    func selectOptions(groupId: String, options: Set<String>) {
        choices[groupId] = options
        
        // Update session
        Task {
            let groupChoices = [GroupChoice(groupId: groupId, optionIds: Array(options))]
            let stepIdx = currentStepData?.stepIndex ?? 0
            await sessionManager.updateChoices(
                sessionId: sessionId,
                stepIdx: stepIdx,
                groupChoices: groupChoices
            )
        }
    }
    
    func advance() async {
        guard var session = await sessionManager.getSession(sessionId) else {
            return
        }
        
        // Save current step choices
        if let stepData = currentStepData {
            for group in stepData.groups {
                let selected = choices[group.id] ?? []
                let groupChoices = [GroupChoice(groupId: group.id, optionIds: Array(selected))]
                await sessionManager.updateChoices(
                    sessionId: sessionId,
                    stepIdx: stepData.stepIndex,
                    groupChoices: groupChoices
                )
            }
        }
        
        session.advanceStep()
        updateState(from: session)
    }
    
    func goBack() async {
        guard var session = await sessionManager.getSession(sessionId) else {
            return
        }
        
        session.goBack()
        updateState(from: session)
    }
    
    func complete() async {
        // Save final choices
        if let stepData = currentStepData {
            for group in stepData.groups {
                let selected = choices[group.id] ?? []
                let groupChoices = [GroupChoice(groupId: group.id, optionIds: Array(selected))]
                await sessionManager.updateChoices(
                    sessionId: sessionId,
                    stepIdx: stepData.stepIndex,
                    groupChoices: groupChoices
                )
            }
        }
        
        // Complete session
        await sessionManager.completeSession(sessionId)
    }
    
    func cancel() async {
        await sessionManager.cancelSession(sessionId)
    }
    
    private func updateState(from session: FomodSession) {
        currentStepData = session.getCurrentStepData()
        canGoBack = session.canGoBack
        canAdvance = session.canAdvance
        
        // Load choices for current step
        if let stepData = currentStepData {
            choices.removeAll()
            for group in stepData.groups {
                // Find choices from session
                let sessionChoices = session.choices.filter { $0.stepId == stepData.stepId && $0.groupId == group.id }
                if let choice = sessionChoices.first {
                    choices[group.id] = Set(choice.optionIds)
                }
            }
        }
    }
}
