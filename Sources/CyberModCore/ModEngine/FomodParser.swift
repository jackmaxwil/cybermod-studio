// FomodParser.swift - FOMOD installer XML parsing

import Foundation
import Logging

// MARK: - Extended FOMOD Types

/// FOMOD info parsed from info.xml
public struct FomodInfo: Sendable {
    public var name: String
    public var author: String?
    public var version: String?
    public var website: URL?
    public var description: String?
    
    public init(name: String = "Unknown Mod", author: String? = nil, version: String? = nil, website: URL? = nil, description: String? = nil) {
        self.name = name
        self.author = author
        self.version = version
        self.website = website
        self.description = description
    }
}

/// FOMOD file mapping (source to destination)
public struct FomodFileMapping: Sendable {
    public var source: String
    public var destination: String
    public var priority: Int
    public var isFolder: Bool
    public var alwaysInstall: Bool
    public var installIfUsable: Bool
    
    public init(source: String, destination: String, priority: Int = 0, isFolder: Bool = false, alwaysInstall: Bool = false, installIfUsable: Bool = false) {
        self.source = source
        self.destination = destination
        self.priority = priority
        self.isFolder = isFolder
        self.alwaysInstall = alwaysInstall
        self.installIfUsable = installIfUsable
    }
}

/// FOMOD condition flag
public struct FomodConditionFlag: Sendable {
    public var name: String
    public var value: String
    
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// FOMOD condition for visibility/file installation
public struct FomodCondition: Sendable {
    public var flagName: String?
    public var flagValue: String?
    public var filePath: String?
    public var gameVersion: String?
    public var `operator`: ConditionOperator
    public var subConditions: [FomodCondition]
    
    public init(flagName: String? = nil, flagValue: String? = nil, filePath: String? = nil, gameVersion: String? = nil, operator: ConditionOperator = .and, subConditions: [FomodCondition] = []) {
        self.flagName = flagName
        self.flagValue = flagValue
        self.filePath = filePath
        self.gameVersion = gameVersion
        self.`operator` = `operator`
        self.subConditions = subConditions
    }
    
    public func evaluate(flags: [String: String], installedFiles: [String] = []) -> Bool {
        var results: [Bool] = []
        
        if let flagName = flagName {
            let currentValue = flags[flagName] ?? ""
            results.append(currentValue == (flagValue ?? ""))
        }
        
        if let filePath = filePath {
            results.append(installedFiles.contains(filePath))
        }
        
        for sub in subConditions {
            results.append(sub.evaluate(flags: flags, installedFiles: installedFiles))
        }
        
        if results.isEmpty {
            return true
        }
        
        return `operator` == .and ? results.allSatisfy { $0 } : results.contains(true)
    }
}

/// Condition operator
public enum ConditionOperator: String, Sendable {
    case and = "And"
    case or = "Or"
}

/// Extended FomodConfig with info and required files
public struct ExtendedFomodConfig: Sendable {
    public var info: FomodInfo
    public var moduleName: String
    public var requiredFiles: [FomodFileMapping]
    public var steps: [FomodStep]
    public var conditionalFileInstalls: [(condition: FomodCondition, files: [FomodFileMapping])]
    public var fomodPath: URL?
    
    public init(info: FomodInfo, moduleName: String = "", requiredFiles: [FomodFileMapping] = [], steps: [FomodStep] = [], conditionalFileInstalls: [(FomodCondition, [FomodFileMapping])] = [], fomodPath: URL? = nil) {
        self.info = info
        self.moduleName = moduleName
        self.requiredFiles = requiredFiles
        self.steps = steps
        self.conditionalFileInstalls = conditionalFileInstalls
        self.fomodPath = fomodPath
    }
    
    /// Convert to basic FomodConfig for ModManager compatibility
    public func toFomodConfig() -> FomodConfig {
        FomodConfig(moduleName: moduleName, steps: steps)
    }
}

/// Extended FomodOption with full file mappings
public struct ExtendedFomodOption: Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var imagePath: String?
    public var files: [FomodFileMapping]
    public var conditionFlags: [FomodConditionFlag]
    public var typeDescriptor: PluginType
    
    public init(id: String, name: String, description: String? = nil, imagePath: String? = nil, files: [FomodFileMapping] = [], conditionFlags: [FomodConditionFlag] = [], typeDescriptor: PluginType = .optional) {
        self.id = id
        self.name = name
        self.description = description
        self.imagePath = imagePath
        self.files = files
        self.conditionFlags = conditionFlags
        self.typeDescriptor = typeDescriptor
    }
}

/// Plugin type descriptor
public enum PluginType: String, Sendable {
    case required = "Required"
    case optional = "Optional"
    case recommended = "Recommended"
    case notUsable = "NotUsable"
    case couldBeUsable = "CouldBeUsable"
}

// MARK: - FOMOD Parser

/// Errors thrown by FomodParser
public enum FomodParseError: LocalizedError {
    case fomodDirectoryNotFound(URL)
    case moduleConfigNotFound(URL)
    case xmlParseError(String)
    case invalidFormat(String)
    
    public var errorDescription: String? {
        switch self {
        case .fomodDirectoryNotFound(let url):
            return "FOMOD directory not found in \(url.path)"
        case .moduleConfigNotFound(let url):
            return "ModuleConfig.xml not found in \(url.path)"
        case .xmlParseError(let reason):
            return "XML parsing error: \(reason)"
        case .invalidFormat(let reason):
            return "Invalid FOMOD format: \(reason)"
        }
    }
}

/// Parses FOMOD installer XML files
public struct FomodParser {
    private let logger: Logger
    
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "com.cybermod.fomodparser")
    }
    
    /// Parse FOMOD configuration from a directory containing fomod files
    public func parse(fomodDir: URL) throws -> ExtendedFomodConfig {
        // Find fomod directory (case insensitive)
        let fomodPath = try findFomodDirectory(in: fomodDir)
        
        // Parse info.xml
        let info = try parseInfoXML(fomodPath: fomodPath)
        
        // Parse ModuleConfig.xml
        var config = try parseModuleConfig(fomodPath: fomodPath, info: info)
        config.fomodPath = fomodPath
        
        return config
    }
    
    /// Find the fomod directory (case insensitive)
    private func findFomodDirectory(in baseDir: URL) throws -> URL {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw FomodParseError.fomodDirectoryNotFound(baseDir)
        }
        
        for item in contents {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
               item.lastPathComponent.lowercased() == "fomod" {
                return item
            }
        }
        
        throw FomodParseError.fomodDirectoryNotFound(baseDir)
    }
    
    /// Parse info.xml file
    private func parseInfoXML(fomodPath: URL) throws -> FomodInfo {
        var info = FomodInfo()
        
        let infoPath = fomodPath.appendingPathComponent("info.xml")
        let fm = FileManager.default
        
        // Try case insensitive search
        var actualInfoPath = infoPath
        if !fm.fileExists(atPath: infoPath.path) {
            if let contents = try? fm.contentsOfDirectory(at: fomodPath, includingPropertiesForKeys: nil) {
                for file in contents {
                    if file.lastPathComponent.lowercased() == "info.xml" {
                        actualInfoPath = file
                        break
                    }
                }
            }
        }
        
        guard fm.fileExists(atPath: actualInfoPath.path) else {
            return info // Return default if not found
        }
        
        guard let xmlDoc = try? XMLDocument(contentsOf: actualInfoPath, options: []) else {
            logger.warning("Failed to parse info.xml")
            return info
        }
        
        let root = xmlDoc.rootElement()!
        
        // Parse elements (case insensitive)
        if let nameElem = root.firstElement(named: "Name") ?? root.firstElement(named: "name"),
           let text = nameElem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            info.name = text
        }
        
        if let authorElem = root.firstElement(named: "Author") ?? root.firstElement(named: "author"),
           let text = authorElem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            info.author = text
        }
        
        if let versionElem = root.firstElement(named: "Version") ?? root.firstElement(named: "version"),
           let text = versionElem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            info.version = text
        }
        
        if let descElem = root.firstElement(named: "Description") ?? root.firstElement(named: "description"),
           let text = descElem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            info.description = text
        }
        
        if let websiteElem = root.firstElement(named: "Website") ?? root.firstElement(named: "website"),
           let text = websiteElem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           let url = URL(string: text) {
            info.website = url
        }
        
        return info
    }
    
    /// Parse ModuleConfig.xml file
    private func parseModuleConfig(fomodPath: URL, info: FomodInfo) throws -> ExtendedFomodConfig {
        let configPath = fomodPath.appendingPathComponent("ModuleConfig.xml")
        let fm = FileManager.default
        
        // Try case insensitive search
        var actualConfigPath = configPath
        if !fm.fileExists(atPath: configPath.path) {
            if let contents = try? fm.contentsOfDirectory(at: fomodPath, includingPropertiesForKeys: nil) {
                for file in contents {
                    if file.lastPathComponent.lowercased() == "moduleconfig.xml" {
                        actualConfigPath = file
                        break
                    }
                }
            }
        }
        
        guard fm.fileExists(atPath: actualConfigPath.path) else {
            throw FomodParseError.moduleConfigNotFound(fomodPath)
        }
        
        guard let xmlDoc = try? XMLDocument(contentsOf: actualConfigPath, options: []) else {
            throw FomodParseError.xmlParseError("Failed to parse ModuleConfig.xml")
        }
        
        let root = xmlDoc.rootElement()!
        var config = ExtendedFomodConfig(info: info)
        
        // Parse module name
        if let moduleName = root.firstElement(named: "moduleName"),
           let text = moduleName.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            config.moduleName = text
            if config.info.name == "Unknown Mod" {
                config.info.name = text
            }
        }
        
        // Parse required install files
        if let requiredFiles = root.firstElement(named: "requiredInstallFiles") {
            config.requiredFiles = try parseFileList(requiredFiles)
        }
        
        // Parse install steps
        if let installSteps = root.firstElement(named: "installSteps") {
            config.steps = try parseInstallSteps(installSteps)
        }
        
        // Parse conditional file installs
        if let conditionalInstalls = root.firstElement(named: "conditionalFileInstalls") {
            config.conditionalFileInstalls = try parseConditionalInstalls(conditionalInstalls)
        }
        
        return config
    }
    
    /// Parse a list of file/folder elements
    private func parseFileList(_ element: XMLElement) throws -> [FomodFileMapping] {
        var files: [FomodFileMapping] = []
        
        for child in element.children ?? [] {
            guard let childElem = child as? XMLElement else { continue }
            let tag = childElem.name?.lowercased() ?? ""
            
            if tag == "file" || tag == "folder" {
                let source = childElem.attribute(forName: "source")?.stringValue ?? ""
                let destination = childElem.attribute(forName: "destination")?.stringValue ?? source
                let priority = Int(childElem.attribute(forName: "priority")?.stringValue ?? "0") ?? 0
                let alwaysInstall = (childElem.attribute(forName: "alwaysInstall")?.stringValue ?? "false").lowercased() == "true"
                let installIfUsable = (childElem.attribute(forName: "installIfUsable")?.stringValue ?? "false").lowercased() == "true"
                
                files.append(FomodFileMapping(
                    source: source,
                    destination: destination,
                    priority: priority,
                    isFolder: tag == "folder",
                    alwaysInstall: alwaysInstall,
                    installIfUsable: installIfUsable
                ))
            }
        }
        
        return files
    }
    
    /// Parse installSteps element
    private func parseInstallSteps(_ element: XMLElement) throws -> [FomodStep] {
        var steps: [FomodStep] = []
        
        guard let installStepElements = element.elements(forName: "installStep") else {
            return steps
        }
        
        for (index, stepElem) in installStepElements.enumerated() {
            let stepName = stepElem.attribute(forName: "name")?.stringValue ?? "Installation"
            var step = FomodStep(
                id: "step_\(index)",
                name: stepName,
                groups: []
            )
            
            // Parse visibility condition
            if let visible = stepElem.firstElement(named: "visible") {
                // Note: We'll parse conditions but visibility checking happens in session manager
            }
            
            // Parse option groups
            if let groupsElem = stepElem.firstElement(named: "optionalFileGroups") {
                step.groups = try parseGroups(groupsElem, stepId: step.id)
            }
            
            steps.append(step)
        }
        
        return steps
    }
    
    /// Parse optionalFileGroups element
    private func parseGroups(_ element: XMLElement, stepId: String) throws -> [FomodGroup] {
        var groups: [FomodGroup] = []
        
        guard let groupElements = element.elements(forName: "group") else {
            return groups
        }
        
        for (index, groupElem) in groupElements.enumerated() {
            let groupName = groupElem.attribute(forName: "name")?.stringValue ?? "Options"
            let groupTypeStr = groupElem.attribute(forName: "type")?.stringValue ?? "SelectAny"
            
            let groupType: FomodGroupType
            switch groupTypeStr {
            case "SelectExactlyOne":
                groupType = .selectExactlyOne
            case "SelectAtMostOne":
                groupType = .selectAtMostOne
            case "SelectAtLeastOne":
                groupType = .selectAtLeastOne
            case "SelectAll":
                groupType = .selectAll
            default:
                groupType = .selectAny
            }
            
            var group = FomodGroup(
                id: "\(stepId)_group_\(index)",
                name: groupName,
                type: groupType,
                options: []
            )
            
            // Parse plugins
            if let pluginsElem = groupElem.firstElement(named: "plugins") {
                group.options = try parsePlugins(pluginsElem, groupId: group.id)
            }
            
            groups.append(group)
        }
        
        return groups
    }
    
    /// Parse plugins element
    private func parsePlugins(_ element: XMLElement, groupId: String) throws -> [FomodOption] {
        var plugins: [FomodOption] = []
        
        guard let pluginElements = element.elements(forName: "plugin") else {
            return plugins
        }
        
        for (index, pluginElem) in pluginElements.enumerated() {
            let pluginName = pluginElem.attribute(forName: "name")?.stringValue ?? "Option"
            var plugin = ExtendedFomodOption(
                id: "\(groupId)_plugin_\(index)",
                name: pluginName,
                files: []
            )
            
            // Parse description
            if let descElem = pluginElem.firstElement(named: "description"),
               let text = descElem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                plugin.description = text
            }
            
            // Parse image
            if let imageElem = pluginElem.firstElement(named: "image"),
               let path = imageElem.attribute(forName: "path")?.stringValue {
                plugin.imagePath = path
            }
            
            // Parse type descriptor
            if let typeElem = pluginElem.firstElement(named: "typeDescriptor"),
               let typeDep = typeElem.firstElement(named: "type"),
               let typeName = typeDep.attribute(forName: "name")?.stringValue {
                plugin.typeDescriptor = PluginType(rawValue: typeName) ?? .optional
            }
            
            // Parse files
            if let filesElem = pluginElem.firstElement(named: "files") {
                plugin.files = try parseFileList(filesElem)
            }
            
            // Parse condition flags
            if let flagsElem = pluginElem.firstElement(named: "conditionFlags") {
                plugin.conditionFlags = parseConditionFlags(flagsElem)
            }
            
            // Convert to FomodOption (simplified for now)
            plugins.append(FomodOption(
                id: plugin.id,
                name: plugin.name,
                description: plugin.description,
                imagePath: plugin.imagePath,
                files: plugin.files.map { $0.source }
            ))
        }
        
        return plugins
    }
    
    /// Parse conditionFlags element
    private func parseConditionFlags(_ element: XMLElement) -> [FomodConditionFlag] {
        var flags: [FomodConditionFlag] = []
        
        guard let flagElements = element.elements(forName: "flag") else {
            return flags
        }
        
        for flagElem in flagElements {
            if let name = flagElem.attribute(forName: "name")?.stringValue,
               !name.isEmpty {
                let value = flagElem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                flags.append(FomodConditionFlag(name: name, value: value))
            }
        }
        
        return flags
    }
    
    /// Parse conditionalFileInstalls element
    private func parseConditionalInstalls(_ element: XMLElement) throws -> [(FomodCondition, [FomodFileMapping])] {
        var result: [(FomodCondition, [FomodFileMapping])] = []
        
        guard let patterns = element.firstElement(named: "patterns"),
              let patternElements = patterns.elements(forName: "pattern") else {
            return result
        }
        
        for pattern in patternElements {
            if let deps = pattern.firstElement(named: "dependencies"),
               let files = pattern.firstElement(named: "files") {
                let condition = try parseCompositeCondition(deps)
                let fileList = try parseFileList(files)
                result.append((condition, fileList))
            }
        }
        
        return result
    }
    
    /// Parse a composite condition
    private func parseCompositeCondition(_ element: XMLElement) throws -> FomodCondition {
        let operatorStr = element.attribute(forName: "operator")?.stringValue ?? "And"
        let op: ConditionOperator = operatorStr == "Or" ? .or : .and
        
        var condition = FomodCondition(`operator`: op)
        var subConditions: [FomodCondition] = []
        
        // Parse flag dependencies
        if let flagDeps = element.elements(forName: "flagDependency") {
            for flagDep in flagDeps {
                if let flag = flagDep.attribute(forName: "flag")?.stringValue,
                   let value = flagDep.attribute(forName: "value")?.stringValue {
                    subConditions.append(FomodCondition(flagName: flag, flagValue: value))
                }
            }
        }
        
        // Parse file dependencies
        if let fileDeps = element.elements(forName: "fileDependency") {
            for fileDep in fileDeps {
                if let file = fileDep.attribute(forName: "file")?.stringValue {
                    subConditions.append(FomodCondition(filePath: file))
                }
            }
        }
        
        // Parse nested dependencies
        if let nestedDeps = element.elements(forName: "dependencies") {
            for nested in nestedDeps {
                subConditions.append(try parseCompositeCondition(nested))
            }
        }
        
        condition.subConditions = subConditions
        condition.`operator` = op
        return condition
    }
    
    /// Resolve which files to install based on user choices
    public func resolveFiles(
        config: ExtendedFomodConfig,
        choices: [FomodChoice],
        baseDir: URL
    ) throws -> [(source: URL, destination: String)] {
        var filesToInstall: [(URL, String)] = []
        var flags: [String: String] = [:]
        let fm = FileManager.default
        
        // Always install required files
        for fileMapping in config.requiredFiles {
            let source = baseDir.appendingPathComponent(fileMapping.source)
            if fm.fileExists(atPath: source.path) {
                filesToInstall.append((source, fileMapping.destination))
            }
        }
        
        // Process choices
        for choice in choices {
            // Find the step
            guard let step = config.steps.first(where: { $0.id == choice.stepId }) else {
                continue
            }
            
            // Find the group
            guard let group = step.groups.first(where: { $0.id == choice.groupId }) else {
                continue
            }
            
            // Process selected options
            for optionId in choice.optionIds {
                guard let option = group.options.first(where: { $0.id == optionId }) else {
                    continue
                }
                
                // Add files from this option
                for filePath in option.files {
                    let source = baseDir.appendingPathComponent(filePath)
                    if fm.fileExists(atPath: source.path) {
                        // Use relative path as destination for now
                        filesToInstall.append((source, filePath))
                    }
                }
            }
        }
        
        // Process conditional file installs
        for (condition, fileList) in config.conditionalFileInstalls {
            if condition.evaluate(flags: flags) {
                for fileMapping in fileList {
                    let source = baseDir.appendingPathComponent(fileMapping.source)
                    if fm.fileExists(atPath: source.path) {
                        filesToInstall.append((source, fileMapping.destination))
                    }
                }
            }
        }
        
        return filesToInstall
    }
}

// MARK: - XML Helper Extensions

extension XMLElement {
    func firstElement(named name: String) -> XMLElement? {
        // Try exact match first
        if self.name?.lowercased() == name.lowercased() {
            return self
        }
        
        // Search children
        for child in children ?? [] {
            if let elem = child as? XMLElement,
               elem.name?.lowercased() == name.lowercased() {
                return elem
            }
        }
        
        // Recursive search
        for child in children ?? [] {
            if let elem = child as? XMLElement,
               let found = elem.firstElement(named: name) {
                return found
            }
        }
        
        return nil
    }
    
    func elements(forName name: String) -> [XMLElement]? {
        var results: [XMLElement] = []
        
        for child in children ?? [] {
            if let elem = child as? XMLElement {
                if elem.name?.lowercased() == name.lowercased() {
                    results.append(elem)
                }
            }
        }
        
        return results.isEmpty ? nil : results
    }
}
