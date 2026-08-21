import Foundation
import Domain

/// OAuth credentials loaded from Claude credential storage.
public struct ClaudeOAuthCredentials: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Double?  // Milliseconds since epoch
    public var subscriptionType: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Double? = nil,
        subscriptionType: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
    }
}

/// Source of loaded credentials.
public enum CredentialSource: Sendable, Equatable {
    case environment
    case file
    case keychain
}

/// Result of loading credentials.
/// Note: fullData contains the raw JSON for persisting changes, marked @unchecked Sendable
/// because [String: Any] can't conform to Sendable but we only use it within a single context.
public struct ClaudeCredentialResult: @unchecked Sendable {
    public var oauth: ClaudeOAuthCredentials
    public let source: CredentialSource
    public var fullData: [String: Any]

    public init(oauth: ClaudeOAuthCredentials, source: CredentialSource, fullData: [String: Any]) {
        self.oauth = oauth
        self.source = source
        self.fullData = fullData
    }
}

/// Loads Claude OAuth credentials from file, Keychain, or environment.
///
/// Credential resolution order:
/// 1. File: `~/.claude/.credentials.json` (full-scope from `claude login`)
/// 2. Keychain: Service "Claude Code-credentials" (if enabled)
/// 3. Environment: `CLAUDE_CODE_OAUTH_TOKEN` env var (inference-only from `claude setup-token`)
public struct ClaudeCredentialLoader: Sendable {
    private let homeDirectory: String
    private let keychainService: String
    private let useKeychain: Bool
    private let environment: [String: String]

    /// Refresh buffer: 5 minutes before expiration
    private static let refreshBufferMs: Double = 5 * 60 * 1000

    static func keychainSaveArguments(
        service: String,
        account: String,
        password: String
    ) -> [String] {
        [
            "add-generic-password",
            "-U",
            "-s", service,
            "-a", account,
            "-w", password
        ]
    }

    public init(
        homeDirectory: String = NSHomeDirectory(),
        keychainService: String = "Claude Code-credentials",
        useKeychain: Bool = true,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.keychainService = keychainService
        self.useKeychain = useKeychain
        self.environment = environment
    }

    /// The path to the credentials file.
    public var credentialsFilePath: String {
        (homeDirectory as NSString).appendingPathComponent(".claude/.credentials.json")
    }

    /// Loads credentials from file, Keychain, or environment.
    /// Returns nil if no valid credentials are found.
    ///
    /// Priority: file/keychain credentials (full-scope from `claude login`) are preferred
    /// over the `CLAUDE_CODE_OAUTH_TOKEN` env var (inference-only from `claude setup-token`).
    /// This ensures quota monitoring uses full-scope credentials when available,
    /// while still falling back to the env var token if nothing else exists.
    public func loadCredentials() -> ClaudeCredentialResult? {
        // Try file first (full-scope OAuth from `claude login`)
        if let fileResult = loadFromFile() {
            return fileResult
        }

        // Keychain (if enabled)
        if useKeychain, let keychainResult = loadFromKeychain() {
            return keychainResult
        }

        // Fallback to environment variable (setup-token, inference-only scope)
        if let envResult = loadFromEnvironment() {
            return envResult
        }

        return nil
    }

    /// Checks if the token needs to be refreshed (expired or within 5 minutes of expiry).
    public func needsRefresh(_ oauth: ClaudeOAuthCredentials) -> Bool {
        guard let expiresAt = oauth.expiresAt else {
            return true
        }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return nowMs + Self.refreshBufferMs >= expiresAt
    }

    /// Saves updated credentials back to the original source.
    public func saveCredentials(_ result: ClaudeCredentialResult) {
        // Environment credentials are read-only (set via env var, not persisted by us)
        if result.source == .environment {
            return
        }

        var updatedData = result.fullData

        // Update the OAuth section
        var oauthDict: [String: Any] = [
            "accessToken": result.oauth.accessToken
        ]
        if let refreshToken = result.oauth.refreshToken {
            oauthDict["refreshToken"] = refreshToken
        }
        if let expiresAt = result.oauth.expiresAt {
            oauthDict["expiresAt"] = expiresAt
        }
        if let subscriptionType = result.oauth.subscriptionType {
            oauthDict["subscriptionType"] = subscriptionType
        }
        updatedData["claudeAiOauth"] = oauthDict

        switch result.source {
        case .environment:
            return  // Already handled above, but satisfy exhaustive switch
        case .file:
            saveToFile(updatedData)
        case .keychain:
            saveToKeychain(updatedData)
        }
    }

    // MARK: - Private: Environment Operations

    private func loadFromEnvironment() -> ClaudeCredentialResult? {
        guard let rawToken = environment["CLAUDE_CODE_OAUTH_TOKEN"] else {
            return nil
        }

        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }

        let oauth = ClaudeOAuthCredentials(
            accessToken: token,
            refreshToken: nil,
            expiresAt: nil
        )

        return ClaudeCredentialResult(oauth: oauth, source: .environment, fullData: [:])
    }

    // MARK: - Private: File Operations

    private func loadFromFile() -> ClaudeCredentialResult? {
        let path = credentialsFilePath
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauthDict = json["claudeAiOauth"] as? [String: Any],
                  let rawAccessToken = oauthDict["accessToken"] as? String else {
                return nil
            }

            let accessToken = rawAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !accessToken.isEmpty else { return nil }

            let oauth = ClaudeOAuthCredentials(
                accessToken: accessToken,
                refreshToken: oauthDict["refreshToken"] as? String,
                expiresAt: oauthDict["expiresAt"] as? Double,
                subscriptionType: oauthDict["subscriptionType"] as? String
            )

            return ClaudeCredentialResult(oauth: oauth, source: .file, fullData: json)
        } catch {
            AppLog.credentials.error("Failed to load Claude credentials from file: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveToFile(_ data: [String: Any]) {
        let path = credentialsFilePath
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
            AppLog.credentials.info("Saved updated Claude credentials to file")
        } catch {
            AppLog.credentials.error("Failed to save Claude credentials to file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Keychain Operations

    private func loadFromKeychain() -> ClaudeCredentialResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            // Drain before waiting: `waitUntilExit()` first would deadlock if the
            // child ever filled the pipe buffer, since nothing is reading it.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            guard let jsonString = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !jsonString.isEmpty else { return nil }

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let oauthDict = json["claudeAiOauth"] as? [String: Any],
                  let rawAccessToken = oauthDict["accessToken"] as? String else {
                return nil
            }

            let accessToken = rawAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !accessToken.isEmpty else { return nil }

            let oauth = ClaudeOAuthCredentials(
                accessToken: accessToken,
                refreshToken: oauthDict["refreshToken"] as? String,
                expiresAt: oauthDict["expiresAt"] as? Double,
                subscriptionType: oauthDict["subscriptionType"] as? String
            )

            return ClaudeCredentialResult(oauth: oauth, source: .keychain, fullData: json)
        } catch {
            AppLog.credentials.error("Failed to load Claude credentials from Keychain via security CLI: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveToKeychain(_ data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            AppLog.credentials.error("Failed to serialize Claude credentials for Keychain")
            return
        }

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        addProcess.arguments = Self.keychainSaveArguments(
            service: keychainService,
            account: NSUserName(),
            password: jsonString
        )
        addProcess.standardOutput = Pipe()
        addProcess.standardError = Pipe()

        do {
            try addProcess.run()
            addProcess.waitUntilExit()

            if addProcess.terminationStatus == 0 {
                AppLog.credentials.info("Saved Claude credentials to Keychain")
            } else {
                AppLog.credentials.error("Failed to save Claude credentials to Keychain (exit code: \(addProcess.terminationStatus))")
            }
        } catch {
            AppLog.credentials.error("Failed to save Claude credentials to Keychain: \(error.localizedDescription)")
        }
    }
}
