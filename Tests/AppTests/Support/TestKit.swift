import Foundation
import Kit

/// A kit of its own over a fresh home folder — the providers, logins and settings a test sets
/// up on disk, read by the same `ClaudeBarCore.start` the app runs. Nothing touches the real
/// `~/.claudebar`, and nothing is started: no hooks, uploads or refreshes.
enum TestKit {
    /// The bundled provider definitions, as the app ships them.
    static let definitions = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ClaudeBarKit/definitions").path

    /// A kit whose `settings.json` holds `settings`, whose `~/.claudebar/providers` holds `custom`
    /// definitions, and whose `~/.claudebar/extensions` holds `extensions`' manifests, by folder.
    static func start(settings: [String: Any] = [:], custom: [String: String] = [:], extensions: [String: String] = [:]) throws -> ClaudeBarCore {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let folder = home.appendingPathComponent(".claudebar")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("providers"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings).write(to: folder.appendingPathComponent("settings.json"))
        for (id, json) in custom {
            try Data(json.utf8).write(to: folder.appendingPathComponent("providers/\(id).json"))
        }
        for (name, manifest) in extensions {
            let extensionFolder = folder.appendingPathComponent("extensions/\(name)")
            try FileManager.default.createDirectory(at: extensionFolder, withIntermediateDirectories: true)
            try Data(manifest.utf8).write(to: extensionFolder.appendingPathComponent("manifest.json"))
        }
        return ClaudeBarCore.start(definitions: definitions, home: home.path)
    }

    /// A saved login, as `providers.<id>.accounts` keeps it.
    static func login(_ id: String, label: String = "", email: String? = nil, values: [String: String], madeBy: AccountOrigin) -> [String: Any] {
        var login: [String: Any] = ["accountId": id, "label": label, "probeConfig": values, "madeBy": madeBy.tag]
        if let email { login["email"] = email }
        return login
    }

    /// Settings holding `logins` for one provider.
    static func settings(_ providerId: String, logins: [[String: Any]]) -> [String: Any] {
        ["providers": [providerId: ["accounts": logins]]]
    }
}

extension ClaudeBarCore {
    /// The provider `id` names; fails the test when the kit has none.
    func provider(_ id: String) throws -> Provider {
        guard let provider = monitor.providers.provider(id: id) else { throw TestKitError.noProvider(id) }
        return provider
    }
}

enum TestKitError: Error {
    case noProvider(String)
}
