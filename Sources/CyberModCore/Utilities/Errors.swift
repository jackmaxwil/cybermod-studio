// Errors.swift - Common error types for CyberMod Studio

import Foundation

/// Top-level error type for CyberMod Studio
public enum CyberModError: LocalizedError {
    // Installation errors
    case installationFailed(reason: String, suggestion: String?)
    case incompatibleMod(reasons: [String])
    case dependencyMissing(name: String, version: String?)
    case conflictDetected(with: [String])
    
    // Game errors
    case gameNotFound
    case launchFailed(reason: String)
    case injectionFailed(reason: String)
    case gameAlreadyRunning
    
    // Profile errors
    case noActiveProfile
    case profileNotFound(name: String)
    
    // Project errors
    case projectNotFound(path: URL)
    case validationFailed(errors: [ValidationError])
    case buildFailed(log: String)
    
    // IPC errors
    case connectionFailed(reason: String)
    case timeout(operation: String)
    case disconnected
    case invalidResponse(expected: String)
    
    // Database errors
    case databaseError(reason: String)
    
    // File errors
    case fileNotFound(path: URL)
    case permissionDenied(path: URL)
    case extractionFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .installationFailed(let reason, _):
            return "Installation failed: \(reason)"
        case .incompatibleMod(let reasons):
            return "Mod is incompatible: \(reasons.joined(separator: "; "))"
        case .dependencyMissing(let name, let version):
            if let version = version {
                return "Required dependency missing: \(name) v\(version)"
            }
            return "Required dependency missing: \(name)"
        case .conflictDetected(let mods):
            return "Conflict detected with: \(mods.joined(separator: ", "))"
        case .gameNotFound:
            return "Cyberpunk 2077 installation not found"
        case .launchFailed(let reason):
            return "Failed to launch game: \(reason)"
        case .injectionFailed(let reason):
            return "Failed to inject dylibs: \(reason)"
        case .gameAlreadyRunning:
            return "Game is already running"
        case .noActiveProfile:
            return "No active mod profile selected"
        case .profileNotFound(let name):
            return "Profile not found: \(name)"
        case .projectNotFound(let path):
            return "Project not found at \(path.path)"
        case .validationFailed(let errors):
            return "Validation failed with \(errors.count) errors"
        case .buildFailed(let log):
            return "Build failed. See log for details: \(log)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .disconnected:
            return "Disconnected from game"
        case .invalidResponse(let expected):
            return "Invalid response, expected: \(expected)"
        case .databaseError(let reason):
            return "Database error: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path.path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path.path)"
        case .extractionFailed(let reason):
            return "Archive extraction failed: \(reason)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .installationFailed(_, let suggestion):
            return suggestion
        case .incompatibleMod:
            return "Check if a macOS port of this mod exists"
        case .dependencyMissing(let name, _):
            return "Install \(name) first, then try again"
        case .gameNotFound:
            return "Select your Cyberpunk 2077 installation directory in Settings"
        case .noActiveProfile:
            return "Create a new profile or select an existing one"
        case .connectionFailed:
            return "Ensure the game is running with the debug agent enabled"
        default:
            return nil
        }
    }
}

/// Validation error with location information
public struct ValidationError: Error, Sendable, Identifiable {
    public let id = UUID()
    public let severity: ValidationSeverity
    public let message: String
    public let file: String?
    public let line: Int?
    public let column: Int?
    
    public init(
        severity: ValidationSeverity,
        message: String,
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.column = column
    }
}

/// Severity level for validation errors
public enum ValidationSeverity: String, Sendable {
    case error
    case warning
    case info
    case hint
}
