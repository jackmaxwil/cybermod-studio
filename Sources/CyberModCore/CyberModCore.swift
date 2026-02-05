// CyberModCore - Core business logic for CyberMod Studio
// Copyright (c) 2024

import Foundation
import Logging

/// CyberModCore version
public let version = "0.1.0"

/// Global logger for the CyberModCore module
public let logger = Logger(label: "com.cybermod.core")

/// Initialize the CyberModCore library
public func initialize() {
    logger.info("CyberModCore \(version) initialized")
}

// MARK: - Public Type Exports

// Re-export commonly used types
@_exported import struct Foundation.URL
@_exported import struct Foundation.UUID
@_exported import struct Foundation.Date
@_exported import struct Foundation.Data
