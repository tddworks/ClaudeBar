import Foundation
import Domain

/// Resolves the OpenCode Go API key that the `opencode` CLI uses for Zen.
///
/// Lookup order:
/// 1. `OPENCODE_API_KEY` environment variable
/// 2. `opencode-go` entry in opencode's auth store
/// 3. `opencode` (shared Zen) entry in opencode's auth store
///
/// The auth store lives at `$XDG_DATA_HOME/opencode/auth.json`
/// (default `~/.local/share/opencode/auth.json`) and is keyed by provider id:
/// ```json
/// {
///   "opencode": { "type": "api", "key": "sk-..." },
///   "anthropic": { "type": "oauth", "access": "...", "refresh": "...", "expires": 0 }
/// }
/// ```
public struct OpenCodeCredentialLoader: Sendable {
    static let envVar = "OPENCODE_API_KEY"
    static let entryKeys = ["opencode-go", "opencode"]

    private let homeDirectory: String
    private let environment: [String: String]

    public init(
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    /// Path to opencode's `auth.json`.
    public var authFilePath: String {
        let dataHome: String
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            dataHome = xdg
        } else {
            dataHome = (homeDirectory as NSString).appendingPathComponent(".local/share")
        }
        return (dataHome as NSString).appendingPathComponent("opencode/auth.json")
    }

    /// Returns the Go API key, or nil when none is configured.
    public func loadAPIKey() -> String? {
        if let envKey = environment[Self.envVar]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return envKey
        }

        let path = authFilePath
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            for entryKey in Self.entryKeys {
                if let entry = json[entryKey] as? [String: Any],
                   let key = entry["key"] as? String,
                   !key.isEmpty {
                    return key
                }
            }
            return nil
        } catch {
            AppLog.credentials.error("Failed to load OpenCode credentials from file: \(error.localizedDescription)")
            return nil
        }
    }
}
