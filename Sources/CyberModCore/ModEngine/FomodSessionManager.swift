// FomodSessionManager.swift - FOMOD wizard session management

import Foundation
import Logging

/// Represents an active FOMOD installation wizard session
public struct FomodSession: Sendable, Identifiable {
    public let id: UUID
    public let tempDir: URL
    public let config: ExtendedFomodConfig
    public let modInfo: [String: String]
    
    public var currentStep: Int
    public var choices: [FomodChoice]
    public var conditionFlags: [String: String]
    public let createdAt: Date
    public var expiresAt: Date
    
    public init(
        id: UUID = UUID(),
        tempDir: URL,
        config: ExtendedFomodConfig,
        modInfo: [String: String],
        currentStep: Int = 0,
        choices: [FomodChoice] = [],
        conditionFlags: [String: String] = [:],
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(3600) // 1 hour default
    ) {
        self.id = id
        self.tempDir = tempDir
        self.config = config
        self.modInfo = modInfo
        self.currentStep = currentStep
        self.choices = choices
        self.conditionFlags = conditionFlags
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
    
    public var isExpired: Bool {
        Date() > expiresAt
    }
    
    public mutating func extendExpiration(hours: Int = 1) {
        expiresAt = Date().addingTimeInterval(TimeInterval(hours * 3600))
    }
    
    /// Get list of step indices that are currently visible
    public func getVisibleSteps() -> [Int] {
        var visible: [Int] = []
        for (index, _) in config.steps.enumerated() {
            // For now, all steps are visible (condition checking would go here)
            visible.append(index)
        }
        return visible
    }
    
    /// Get the data for the current step
    public func getCurrentStepData() -> StepData? {
        let visibleSteps = getVisibleSteps()
        guard currentStep < visibleSteps.count else {
            return nil
        }
        
        let stepIdx = visibleSteps[currentStep]
        let step = config.steps[stepIdx]
        
        return StepData(
            stepIndex: currentStep,
            totalSteps: visibleSteps.count,
            stepId: step.id,
            stepName: step.name,
            groups: step.groups.map { group in
                GroupData(
                    id: group.id,
                    name: group.name,
                    type: group.type,
                    options: group.options.map { option in
                        OptionData(
                            id: option.id,
                            name: option.name,
                            description: option.description,
                            imagePath: option.imagePath
                        )
                    }
                )
            },
            isFirst: currentStep == 0,
            isLast: currentStep == visibleSteps.count - 1
        )
    }
    
    /// Set choices for a specific step
    public mutating func setStepChoices(stepIdx: Int, groupChoices: [GroupChoice]) {
        let visibleSteps = getVisibleSteps()
        guard stepIdx < visibleSteps.count else {
            return
        }
        
        let actualStepIdx = visibleSteps[stepIdx]
        let step = config.steps[actualStepIdx]
        
        // Remove existing choices for this step
        choices.removeAll { $0.stepId == step.id }
        
        // Add new choices
        for groupChoice in groupChoices {
            if let group = step.groups.first(where: { $0.id == groupChoice.groupId }) {
                let choice = FomodChoice(
                    stepId: step.id,
                    groupId: groupChoice.groupId,
                    optionIds: groupChoice.optionIds
                )
                choices.append(choice)
                
                // Update condition flags based on selected plugins
                for optionId in groupChoice.optionIds {
                    if group.options.contains(where: { $0.id == optionId }) {
                        // Note: Extended options would have condition flags
                        // For now, we'll handle this in the parser
                    }
                }
            }
        }
    }
    
    public var canAdvance: Bool {
        let visibleSteps = getVisibleSteps()
        return currentStep < visibleSteps.count - 1
    }
    
    public var canGoBack: Bool {
        return currentStep > 0
    }
    
    @discardableResult
    public mutating func advanceStep() -> Bool {
        if canAdvance {
            currentStep += 1
            return true
        }
        return false
    }
    
    @discardableResult
    public mutating func goBack() -> Bool {
        if canGoBack {
            currentStep -= 1
            return true
        }
        return false
    }
    
    /// Get a summary of all choices made
    public func getSummary() -> SessionSummary {
        var stepSummaries: [StepSummary] = []
        
        for step in config.steps {
            let stepChoices = choices.filter { $0.stepId == step.id }
            var groupSummaries: [GroupSummary] = []
            
            for group in step.groups {
                if let choice = stepChoices.first(where: { $0.groupId == group.id }) {
                    let selections = choice.optionIds.compactMap { optionId in
                        group.options.first(where: { $0.id == optionId })?.name
                    }
                    
                    if !selections.isEmpty {
                        groupSummaries.append(GroupSummary(
                            name: group.name,
                            selections: selections
                        ))
                    }
                }
            }
            
            if !groupSummaries.isEmpty {
                stepSummaries.append(StepSummary(
                    name: step.name,
                    groups: groupSummaries
                ))
            }
        }
        
        return SessionSummary(
            modName: modInfo["name"] ?? "Unknown Mod",
            steps: stepSummaries
        )
    }
}

// MARK: - Supporting Types

public struct StepData: Sendable {
    public var stepIndex: Int
    public var totalSteps: Int
    public var stepId: String
    public var stepName: String
    public var groups: [GroupData]
    public var isFirst: Bool
    public var isLast: Bool
}

public struct GroupData: Sendable {
    public var id: String
    public var name: String
    public var type: FomodGroupType
    public var options: [OptionData]
}

public struct OptionData: Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var imagePath: String?
}

public struct GroupChoice: Sendable {
    public var groupId: String
    public var optionIds: [String]
    
    public init(groupId: String, optionIds: [String]) {
        self.groupId = groupId
        self.optionIds = optionIds
    }
}

public struct SessionSummary: Sendable {
    public var modName: String
    public var steps: [StepSummary]
}

public struct StepSummary: Sendable {
    public var name: String
    public var groups: [GroupSummary]
}

public struct GroupSummary: Sendable {
    public var name: String
    public var selections: [String]
}

// MARK: - Session Manager

/// Manages FOMOD wizard sessions
public actor FomodSessionManager {
    private var sessions: [UUID: FomodSession] = [:]
    private let logger: Logger
    private let fileManager: FileManager
    
    public static let shared = FomodSessionManager()
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "com.cybermod.fomodsession")
        self.fileManager = FileManager.default
    }
    
    /// Create a new FOMOD wizard session
    public func createSession(
        config: ExtendedFomodConfig,
        tempDir: URL,
        modInfo: [String: String]
    ) -> UUID {
        let sessionId = UUID()
        
        let session = FomodSession(
            id: sessionId,
            tempDir: tempDir,
            config: config,
            modInfo: modInfo
        )
        
        sessions[sessionId] = session
        logger.info("Created FOMOD session \(sessionId.uuidString) for mod: \(modInfo["name"] ?? "Unknown")")
        
        return sessionId
    }
    
    /// Get a session by ID
    public func getSession(_ sessionId: UUID) -> FomodSession? {
        guard var session = sessions[sessionId] else {
            return nil
        }
        
        if session.isExpired {
            logger.info("Session \(sessionId.uuidString) has expired, cleaning up")
            cleanupSession(sessionId)
            return nil
        }
        
        // Extend expiration on access
        session.extendExpiration()
        sessions[sessionId] = session
        
        return session
    }
    
    /// Update choices for a step in a session
    public func updateChoices(
        sessionId: UUID,
        stepIdx: Int,
        groupChoices: [GroupChoice]
    ) -> Bool {
        guard var session = getSession(sessionId) else {
            return false
        }
        
        session.setStepChoices(stepIdx: stepIdx, groupChoices: groupChoices)
        sessions[sessionId] = session
        return true
    }
    
    /// Complete a session and return the final choices
    public func completeSession(_ sessionId: UUID) -> CompletedSession? {
        guard let session = getSession(sessionId) else {
            return nil
        }
        
        let result = CompletedSession(
            choices: session.choices,
            tempDir: session.tempDir,
            config: session.config,
            modInfo: session.modInfo
        )
        
        // Don't clean up temp_dir yet - let the installer handle it
        sessions.removeValue(forKey: sessionId)
        logger.info("Completed FOMOD session \(sessionId.uuidString)")
        
        return result
    }
    
    /// Cancel a session and clean up resources
    public func cancelSession(_ sessionId: UUID) -> Bool {
        guard sessions[sessionId] != nil else {
            return false
        }
        
        cleanupSession(sessionId)
        logger.info("Cancelled FOMOD session \(sessionId.uuidString)")
        return true
    }
    
    private func cleanupSession(_ sessionId: UUID) {
        guard let session = sessions[sessionId] else {
            return
        }
        
        // Clean up temp directory
        if fileManager.fileExists(atPath: session.tempDir.path) {
            do {
                try fileManager.removeItem(at: session.tempDir)
                logger.debug("Cleaned up temp dir for session \(sessionId.uuidString)")
            } catch {
                logger.warning("Failed to clean up temp dir for session \(sessionId.uuidString): \(error.localizedDescription)")
            }
        }
        
        sessions.removeValue(forKey: sessionId)
    }
    
    /// Clean up all expired sessions
    public func cleanupExpired() -> Int {
        let expiredIds = sessions.values.filter { $0.isExpired }.map { $0.id }
        
        for sessionId in expiredIds {
            cleanupSession(sessionId)
        }
        
        if !expiredIds.isEmpty {
            logger.info("Cleaned up \(expiredIds.count) expired FOMOD sessions")
        }
        
        return expiredIds.count
    }
    
    /// Get a list of all active sessions (for debugging)
    public func getActiveSessions() -> [SessionInfo] {
        return sessions.values.filter { !$0.isExpired }.map { session in
            SessionInfo(
                sessionId: session.id,
                modName: session.modInfo["name"] ?? "Unknown",
                currentStep: session.currentStep,
                createdAt: session.createdAt,
                expiresAt: session.expiresAt
            )
        }
    }
}

// MARK: - Completed Session

public struct CompletedSession: Sendable {
    public var choices: [FomodChoice]
    public var tempDir: URL
    public var config: ExtendedFomodConfig
    public var modInfo: [String: String]
}

public struct SessionInfo: Sendable {
    public var sessionId: UUID
    public var modName: String
    public var currentStep: Int
    public var createdAt: Date
    public var expiresAt: Date
}
