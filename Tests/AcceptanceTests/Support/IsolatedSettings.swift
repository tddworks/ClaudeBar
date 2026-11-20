import Foundation
import Domain
import Storage

/// The settings the app keeps, in a `settings.json` of its own and with
/// secrets in throwaway defaults — never the person's settings or Keychain.
func isolatedSettings() -> any SettingsFile {
    let id = UUID().uuidString
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-spec-\(id)/settings.json")
    let defaults = UserDefaults(suiteName: "com.claudebar.test.\(id)")!
    return Storage.makeSettings(fileURL: file, secretsIn: defaults)
}
