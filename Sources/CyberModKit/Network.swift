// Network.swift - HTTP, GitHub releases, the Nexus Mods API and the Keychain-stored API key.

import Foundation
import Security

public struct HTTPError: LocalizedError {
    public let status: Int
    public let url: URL
    public var errorDescription: String? { "HTTP \(status) from \(url.host ?? url.absoluteString)" }
}

enum HTTP {
    static func request(_ url: URL, _ headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("cybermod/\(cybermodVersion)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    static func check(_ response: URLResponse, _ url: URL) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError(status: http.statusCode, url: url)
        }
    }

    static func offline(_ url: URL, _ error: Error) -> KitError {
        if Task.isCancelled || (error as? URLError)?.code == .cancelled { return .cancelled }
        return KitError("Could not reach \(url.host ?? url.absoluteString): \(error.localizedDescription)",
                 hint: "Check your internet connection and run the command again.")
    }

    static func get(_ url: URL, session: URLSession, headers: [String: String] = [:]) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request(url, headers)) } catch { throw offline(url, error) }
        try check(response, url)
        return data
    }

    static func getJSON<T: Decodable>(_ type: T.Type, _ url: URL, session: URLSession, headers: [String: String] = [:]) async throws -> T {
        let data = try await get(url, session: session, headers: headers)
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw KitError("Unexpected reply from \(url.host ?? url.absoluteString).",
                           hint: "Try again later; if it persists, update cybermod.", details: ["\(error)"])
        }
    }

    /// Downloads to `dir`, keeping the server's file name. Returns the file.
    static func download(_ url: URL, to dir: URL, kit: Kit, headers: [String: String] = [:]) async throws -> URL {
        kit.log("Downloading \(url.lastPathComponent) ...")
        let (temp, response): (URL, URLResponse)
        do { (temp, response) = try await kit.session.download(for: request(url, headers)) } catch { throw offline(url, error) }
        do { try check(response, url) } catch let error as HTTPError {
            throw KitError("Download failed (HTTP \(error.status)): \(url.absoluteString)",
                           hint: "Check that the link still works in a browser, then run the command again.")
        }
        let name = (response.suggestedFilename ?? url.lastPathComponent).replacingOccurrences(of: "/", with: "_")
        let file = dir.appendingPathComponent(name.isEmpty ? "download" : name)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temp, to: file)
        return file
    }
}

// MARK: - GitHub

public struct GitHubRelease: Decodable, Equatable {
    public struct Asset: Decodable, Equatable {
        public var name: String
        public var browser_download_url: URL
    }

    public var tag_name: String
    public var prerelease: Bool
    public var draft: Bool
    public var assets: [Asset]
    public var zipball_url: URL?
}

enum GitHub {
    static var headers: [String: String] {
        var headers = ["Accept": "application/vnd.github+json"]
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    static func api(_ path: String) -> URL { URL(string: "https://api.github.com/repos/\(path)")! }

    /// Releases, newest first. A missing repository is a KitError naming it.
    static func releases(_ repo: String, session: URLSession) async throws -> [GitHubRelease] {
        do {
            return try await HTTP.getJSON([GitHubRelease].self, api("\(repo)/releases?per_page=100"), session: session, headers: headers)
                .filter { !$0.draft }
        } catch let error as HTTPError where error.status == 404 {
            throw KitError("GitHub repository \(repo) not found.", hint: "Check the name: github:owner/repo")
        } catch let error as HTTPError where error.status == 403 || error.status == 429 {
            throw KitError("GitHub is rate-limiting requests from this network.",
                           hint: "Wait an hour, or set GITHUB_TOKEN to a GitHub token and run the command again.")
        }
    }

    /// The asset of a release that looks like the mod itself: an archive or loose mod file, a macOS build first.
    static func modAsset(_ release: GitHubRelease) -> GitHubRelease.Asset? {
        let extensions = [".zip", ".7z", ".rar", ".archive", ".reds"]
        let candidates = release.assets.filter { asset in
            let name = asset.name.lowercased()
            return extensions.contains { name.hasSuffix($0) } && !name.contains("source") && !name.contains("windows")
        }
        return candidates.first { $0.name.lowercased().contains("mac") } ?? candidates.first
    }
}

// MARK: - Nexus Mods

/// Nexus Mods public API v1 for the cyberpunk2077 game domain, with the user's personal API key.
public enum Nexus {
    static let api = "https://api.nexusmods.com/v1/games/cyberpunk2077"
    public static let keyAccount = "nexus.api-key"
    /// Message of the KitError `nexus:` sources throw for non-Premium accounts after opening the files page (its URL is
    /// the first detail); the app then waits for the nxm:// link instead of showing an error.
    public static let premiumOnly = "Nexus Mods gives direct downloads only to Premium members."

    public struct User: Decodable, Sendable { public var name: String; public var is_premium: Bool }
    struct Mod: Decodable { var name: String?; var version: String?; var author: String? }
    struct File: Decodable { var file_id: Int; var version: String?; var category_name: String?; var is_primary: Bool?; var uploaded_timestamp: Int? }
    struct Files: Decodable { var files: [File] }
    struct Link: Decodable { var URI: URL }

    /// $NEXUS_API_KEY, else the key saved with `cybermod config set nexus.api-key`.
    public static func key() throws -> String {
        if let key = ProcessInfo.processInfo.environment["NEXUS_API_KEY"], !key.isEmpty { return key }
        if let key = Secrets.get(keyAccount) { return key }
        throw KitError("No Nexus Mods API key set.",
                       hint: "Copy your personal API key from https://www.nexusmods.com/users/myaccount?tab=api "
                           + "(bottom of the page), then run `cybermod config set nexus.api-key` and paste it.")
    }

    static func headers(_ key: String) -> [String: String] {
        ["apikey": key, "Application-Name": "cybermod", "Application-Version": cybermodVersion, "Accept": "application/json"]
    }

    static func call<T: Decodable>(_ type: T.Type, _ url: String, key: String, session: URLSession) async throws -> T {
        do {
            return try await HTTP.getJSON(type, URL(string: url)!, session: session, headers: headers(key))
        } catch let error as HTTPError where error.status == 401 {
            throw KitError("Nexus Mods rejected the API key.",
                           hint: "Copy a fresh key from https://www.nexusmods.com/users/myaccount?tab=api and run "
                               + "`cybermod config set nexus.api-key`.")
        } catch let error as HTTPError where error.status == 404 {
            throw KitError("Not found on Nexus Mods (cyberpunk2077): \(url.replacingOccurrences(of: api, with: "")).",
                           hint: "Check the mod id in the mod page's address: nexusmods.com/cyberpunk2077/mods/<id>.")
        } catch let error as HTTPError where error.status == 429 {
            throw KitError("Nexus Mods rate limit reached.", hint: "Wait an hour and run the command again.")
        }
    }

    public static func validate(key: String, session: URLSession = .shared) async throws -> User {
        try await call(User.self, "https://api.nexusmods.com/v1/users/validate.json", key: key, session: session)
    }

    static func mod(_ id: Int, key: String, session: URLSession) async throws -> Mod {
        try await call(Mod.self, "\(api)/mods/\(id).json", key: key, session: session)
    }

    /// The file a "Download" click gets: the primary MAIN file, else the newest MAIN file, else the newest file.
    static func mainFile(_ mod: Int, key: String, session: URLSession) async throws -> File {
        let files = try await call(Files.self, "\(api)/mods/\(mod)/files.json", key: key, session: session).files
            .sorted { ($0.uploaded_timestamp ?? 0) > ($1.uploaded_timestamp ?? 0) }
        let main = files.filter { $0.category_name == "MAIN" }
        guard let file = main.first(where: { $0.is_primary == true }) ?? main.first ?? files.first else {
            throw KitError("Mod \(mod) has no downloadable files on Nexus Mods.", hint: "Open the mod page to check.")
        }
        return file
    }

    /// Download URL. Premium accounts get it directly; others need the key/expires of an nxm:// link.
    static func downloadLink(mod: Int, file: Int, key: String, nxm: (key: String, expires: Int)? = nil, session: URLSession) async throws -> URL {
        var url = URLComponents(string: "\(api)/mods/\(mod)/files/\(file)/download_link.json")!
        if let nxm { url.queryItems = [URLQueryItem(name: "key", value: nxm.key), URLQueryItem(name: "expires", value: "\(nxm.expires)")] }
        guard let link = try await call([Link].self, url.string!, key: key, session: session).first else {
            throw KitError("Nexus Mods returned no download server.", hint: "Try again in a few minutes.")
        }
        return link.URI
    }

    /// The website page where non-premium users click "Mod Manager Download".
    public static func filesPage(mod: Int, file: Int?) -> URL {
        URL(string: "https://www.nexusmods.com/cyberpunk2077/mods/\(mod)?tab=files" + (file.map { "&file_id=\($0)&nmm=1" } ?? ""))!
    }
}

// MARK: - Keychain

/// Secrets in the login Keychain (generic passwords, service "CyberModStudio").
public enum Secrets {
    static let service = "CyberModStudio"

    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func set(_ account: String, _ value: String) throws {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KitError("Could not save to the Keychain (error \(status)).",
                           hint: "Unlock your login keychain, or use the NEXUS_API_KEY environment variable instead.")
        }
    }

    public static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
