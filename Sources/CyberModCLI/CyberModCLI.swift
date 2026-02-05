// CyberModCLI.swift - Command-line interface for CyberMod Studio

import ArgumentParser
import Foundation
import CyberModCore

@main
struct CyberModCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cybermod",
        abstract: "CyberMod Studio - Cyberpunk 2077 mod manager for macOS",
        version: CyberModCore.version,
        subcommands: [
            ListCommand.self,
            InstallCommand.self,
            UninstallCommand.self,
            EnableCommand.self,
            DisableCommand.self,
            ProfileCommand.self,
            LaunchCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}

// MARK: - List Command

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List installed mods"
    )
    
    @Option(name: .shortAndLong, help: "Filter by mod type (archive, tweakXL, etc.)")
    var type: String?
    
    @Flag(name: .shortAndLong, help: "Show only enabled mods")
    var enabled = false
    
    @Flag(name: .shortAndLong, help: "Show only disabled mods")
    var disabled = false
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        var mods = try await database.listMods()
        
        // Apply filters
        if enabled {
            mods = mods.filter { $0.isEnabled }
        }
        if disabled {
            mods = mods.filter { !$0.isEnabled }
        }
        if let typeFilter = type {
            mods = mods.filter { mod in
                mod.type.contains { $0.rawValue.lowercased() == typeFilter.lowercased() }
            }
        }
        
        if mods.isEmpty {
            print("No mods found.")
            return
        }
        
        print("\nInstalled Mods (\(mods.count)):")
        print(String(repeating: "-", count: 60))
        
        for mod in mods.sorted(by: { $0.name < $1.name }) {
            let status = mod.isEnabled ? "✓" : "○"
            let types = mod.type.map(\.rawValue).joined(separator: ", ")
            print("\(status) \(mod.name) v\(mod.version) [\(types)]")
        }
    }
}

// MARK: - Install Command

struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a mod from a local archive"
    )
    
    @Argument(help: "Path to mod archive (ZIP, 7Z, RAR)")
    var path: String
    
    @Flag(name: .shortAndLong, help: "Force install even if compatibility issues found")
    var force = false
    
    func run() async throws {
        let url = URL(fileURLWithPath: path)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Error: File not found at \(path)")
            throw ExitCode.failure
        }
        
        print("Installing mod from \(url.lastPathComponent)...")
        
        let database = ModDatabase.shared
        try await database.initialize()
        
        let modManager = ModManager.shared
        
        // Ensure we have an active profile
        let profiles = try await database.listProfiles()
        guard let profile = profiles.first else {
            print("Error: No profiles configured. Create a profile first.")
            throw ExitCode.failure
        }
        
        let options = InstallOptions(forceInstall: force)
        
        do {
            let result = try await modManager.install(.local(url: url), profile: profile, options: options)
            print("✓ Installed: \(result.mod.name) v\(result.mod.version)")
            
            if !result.warnings.isEmpty {
                print("\nWarnings:")
                for warning in result.warnings {
                    print("  ⚠ \(warning)")
                }
            }
        } catch let error as ModManagerError {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Uninstall Command

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall a mod"
    )
    
    @Argument(help: "Name of the mod to uninstall")
    var name: String
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        let mods = try await database.searchMods(query: name)
        
        guard let mod = mods.first else {
            print("Error: No mod found matching '\(name)'")
            throw ExitCode.failure
        }
        
        print("Uninstalling \(mod.name)...")
        
        let modManager = ModManager.shared
        try await modManager.uninstall(mod)
        
        print("✓ Uninstalled: \(mod.name)")
    }
}

// MARK: - Enable/Disable Commands

struct EnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable a disabled mod"
    )
    
    @Argument(help: "Name of the mod to enable")
    var name: String
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        let mods = try await database.searchMods(query: name)
        
        guard let mod = mods.first else {
            print("Error: No mod found matching '\(name)'")
            throw ExitCode.failure
        }
        
        if mod.isEnabled {
            print("\(mod.name) is already enabled.")
            return
        }
        
        let modManager = ModManager.shared
        try await modManager.enable(mod)
        
        print("✓ Enabled: \(mod.name)")
    }
}

struct DisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable an enabled mod"
    )
    
    @Argument(help: "Name of the mod to disable")
    var name: String
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        let mods = try await database.searchMods(query: name)
        
        guard let mod = mods.first else {
            print("Error: No mod found matching '\(name)'")
            throw ExitCode.failure
        }
        
        if !mod.isEnabled {
            print("\(mod.name) is already disabled.")
            return
        }
        
        let modManager = ModManager.shared
        try await modManager.disable(mod)
        
        print("✓ Disabled: \(mod.name)")
    }
}

// MARK: - Profile Command

struct ProfileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Manage mod profiles",
        subcommands: [
            ProfileListCommand.self,
            ProfileCreateCommand.self,
            ProfileActivateCommand.self,
        ],
        defaultSubcommand: ProfileListCommand.self
    )
}

struct ProfileListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all profiles"
    )
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        let profiles = try await database.listProfiles()
        
        if profiles.isEmpty {
            print("No profiles configured.")
            return
        }
        
        print("\nProfiles:")
        for profile in profiles {
            let active = profile.isActive ? "→ " : "  "
            print("\(active)\(profile.name) (\(profile.gamePath.path))")
        }
    }
}

struct ProfileCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new profile"
    )
    
    @Argument(help: "Profile name")
    var name: String
    
    @Option(name: .shortAndLong, help: "Path to Cyberpunk 2077 installation")
    var gamePath: String
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        let url = URL(fileURLWithPath: gamePath)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Error: Game path does not exist: \(gamePath)")
            throw ExitCode.failure
        }
        
        let modManager = ModManager.shared
        let profile = try await modManager.createProfile(name: name, gamePath: url)
        
        print("✓ Created profile: \(profile.name)")
    }
}

struct ProfileActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Activate a profile"
    )
    
    @Argument(help: "Profile name to activate")
    var name: String
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        let profiles = try await database.listProfiles()
        
        guard let profile = profiles.first(where: { $0.name == name }) else {
            print("Error: Profile not found: \(name)")
            throw ExitCode.failure
        }
        
        let modManager = ModManager.shared
        try await modManager.setActiveProfile(profile)
        
        print("✓ Activated profile: \(profile.name)")
    }
}

// MARK: - Launch Command

struct LaunchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch Cyberpunk 2077"
    )
    
    @Flag(name: .shortAndLong, help: "Enable debug agent for runtime inspection")
    var debug = false
    
    func run() async throws {
        let database = ModDatabase.shared
        try await database.initialize()
        
        guard let profile = try await database.getActiveProfile() else {
            print("Error: No active profile. Activate a profile first.")
            throw ExitCode.failure
        }
        
        print("Launching Cyberpunk 2077...")
        print("Profile: \(profile.name)")
        print("Game path: \(profile.gamePath.path)")
        
        let launcher = GameLauncher.shared
        await launcher.configure(gamePath: profile.gamePath)
        
        let options = LaunchOptions(enableDebugAgent: debug)
        
        do {
            let session = try await launcher.launch(profile: profile, options: options)
            print("✓ Game launched (PID: \(session.pid))")
            print("\nPress Ctrl+C to exit (game will continue running)")
            
            // Wait for game to exit
            while await launcher.isRunning {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            if let exitCode = session.exitCode {
                print("\nGame exited with code: \(exitCode)")
            }
        } catch let error as GameLaunchError {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
