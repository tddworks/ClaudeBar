import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("OpenCodeCredentialLoader Tests")
struct OpenCodeCredentialLoaderTests {

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-credential-loader-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Writes `<dataDir>/opencode/auth.json` — the layout opencode uses under `$XDG_DATA_HOME`.
    private func writeAuthFile(dataDirectory: URL, json: [String: Any]) throws {
        let dir = dataDirectory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: dir.appendingPathComponent("auth.json"))
    }

    // MARK: - Path resolution

    @Test
    func `defaults to ~/.local/share/opencode/auth.json`() {
        let loader = OpenCodeCredentialLoader(homeDirectory: "/Users/alice", environment: [:])
        #expect(loader.authFilePath == "/Users/alice/.local/share/opencode/auth.json")
    }

    @Test
    func `honors XDG_DATA_HOME`() {
        let loader = OpenCodeCredentialLoader(
            homeDirectory: "/Users/alice",
            environment: ["XDG_DATA_HOME": "/custom/data"]
        )
        #expect(loader.authFilePath == "/custom/data/opencode/auth.json")
    }

    // MARK: - Key resolution

    @Test
    func `loads api key from opencode-go entry`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeAuthFile(dataDirectory: tempDir, json: [
            "opencode-go": ["type": "api", "key": "go-key-123"]
        ])

        let loader = OpenCodeCredentialLoader(environment: ["XDG_DATA_HOME": tempDir.path])

        #expect(loader.loadAPIKey() == "go-key-123")
    }

    @Test
    func `falls back to shared opencode zen entry`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeAuthFile(dataDirectory: tempDir, json: [
            "anthropic": ["type": "oauth", "access": "a", "refresh": "r", "expires": 0],
            "opencode": ["type": "api", "key": "zen-key-456"]
        ])

        let loader = OpenCodeCredentialLoader(environment: ["XDG_DATA_HOME": tempDir.path])

        #expect(loader.loadAPIKey() == "zen-key-456")
    }

    @Test
    func `prefers opencode-go entry over opencode entry`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeAuthFile(dataDirectory: tempDir, json: [
            "opencode": ["type": "api", "key": "zen-key"],
            "opencode-go": ["type": "api", "key": "go-key"]
        ])

        let loader = OpenCodeCredentialLoader(environment: ["XDG_DATA_HOME": tempDir.path])

        #expect(loader.loadAPIKey() == "go-key")
    }

    @Test
    func `OPENCODE_API_KEY env var wins over auth file`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeAuthFile(dataDirectory: tempDir, json: [
            "opencode-go": ["type": "api", "key": "file-key"]
        ])

        let loader = OpenCodeCredentialLoader(
            environment: ["XDG_DATA_HOME": tempDir.path, "OPENCODE_API_KEY": "env-key"]
        )

        #expect(loader.loadAPIKey() == "env-key")
    }

    @Test
    func `returns nil when auth file missing`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = OpenCodeCredentialLoader(environment: ["XDG_DATA_HOME": tempDir.path])

        #expect(loader.loadAPIKey() == nil)
    }

    @Test
    func `returns nil when entries have no usable key`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeAuthFile(dataDirectory: tempDir, json: [
            "opencode": ["type": "api", "key": ""],
            "openai": ["type": "api", "key": "unrelated"]
        ])

        let loader = OpenCodeCredentialLoader(environment: ["XDG_DATA_HOME": tempDir.path])

        #expect(loader.loadAPIKey() == nil)
    }

    @Test
    func `returns nil when auth file is not valid JSON`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dir = tempDir.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("auth.json"))

        let loader = OpenCodeCredentialLoader(environment: ["XDG_DATA_HOME": tempDir.path])

        #expect(loader.loadAPIKey() == nil)
    }
}
