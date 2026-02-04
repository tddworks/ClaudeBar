import Foundation
import Security
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

/// Loads Claude OAuth credentials from file or Keychain.
///
/// Credential resolution order:
/// 1. File: `~/.claude/.credentials.json`
/// 2. Keychain: Service "Claude Code-credentials" (if enabled)
public struct ClaudeCredentialLoader: Sendable {
    private let homeDirectory: String
    private let keychainService: String
    private let useKeychain: Bool

    /// Refresh buffer: 5 minutes before expiration
    private static let refreshBufferMs: Double = 5 * 60 * 1000

    public init(
        homeDirectory: String = NSHomeDirectory(),
        keychainService: String = "Claude Code-credentials",
        useKeychain: Bool = true
    ) {
        self.homeDirectory = homeDirectory
        self.keychainService = keychainService
        self.useKeychain = useKeychain
    }

    /// The path to the credentials file.
    public var credentialsFilePath: String {
        (homeDirectory as NSString).appendingPathComponent(".claude/.credentials.json")
    }

    /// Loads credentials from file or Keychain.
    /// Returns nil if no valid credentials are found.
    public func loadCredentials() -> ClaudeCredentialResult? {
        // Try file first
        if let fileResult = loadFromFile() {
            return fileResult
        }

        // Fallback to Keychain (if enabled)
        if useKeychain, let keychainResult = loadFromKeychain() {
            return keychainResult
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
        case .file:
            saveToFile(updatedData)
        case .keychain:
            saveToKeychain(updatedData)
        }
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
                  let accessToken = oauthDict["accessToken"] as? String,
                  !accessToken.isEmpty else {
                return nil
            }

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthDict = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauthDict["accessToken"] as? String,
              !accessToken.isEmpty else {
            return nil
        }

        let oauth = ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: oauthDict["refreshToken"] as? String,
            expiresAt: oauthDict["expiresAt"] as? Double,
            subscriptionType: oauthDict["subscriptionType"] as? String
        )

        return ClaudeCredentialResult(oauth: oauth, source: .keychain, fullData: json)
    }

    private func saveToKeychain(_ data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) else {
            AppLog.credentials.error("Failed to serialize Claude credentials for Keychain")
            return
        }

        // First, try to update existing item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]

        let update: [String: Any] = [
            kSecValueData as String: jsonData
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = jsonData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            if addStatus != errSecSuccess {
                AppLog.credentials.error("Failed to add Claude credentials to Keychain: \(addStatus)")
            } else {
                AppLog.credentials.info("Added Claude credentials to Keychain")
            }
        } else if updateStatus != errSecSuccess {
            AppLog.credentials.error("Failed to update Claude credentials in Keychain: \(updateStatus)")
        } else {
            AppLog.credentials.info("Updated Claude credentials in Keychain")
        }
    }
}
