import Foundation
import Domain

/// Resolves the Command Code API key that the `cmd` CLI uses.
///
/// Lookup order:
/// 1. `COMMAND_CODE_API_KEY` environment variable
/// 2. `COMMANDCODE_API_KEY` environment variable
/// 3. `apiKey` in `~/.commandcode/auth.json`
///
/// The auth file is a flat object written by `cmd login`:
/// ```json
/// { "apiKey": "user_..." }
/// ```
/// Command Code authenticates with a long-lived API key — there is no OAuth
/// token to refresh.
public struct CommandCodeCredentialLoader: Sendable {
    static let envVars = ["COMMAND_CODE_API_KEY", "COMMANDCODE_API_KEY"]

    private let homeDirectory: String
    private let environment: [String: String]

    public init(
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    /// Path to Command Code's `auth.json`.
    public var authFilePath: String {
        (homeDirectory as NSString).appendingPathComponent(".commandcode/auth.json")
    }

    /// Returns the API key, or nil when none is configured.
    public func loadAPIKey() -> String? {
        for name in Self.envVars {
            if let envKey = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return envKey
            }
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
            guard let key = json["apiKey"] as? String else { return nil }
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            AppLog.credentials.error("Failed to load Command Code credentials from file: \(error.localizedDescription)")
            return nil
        }
    }
}
