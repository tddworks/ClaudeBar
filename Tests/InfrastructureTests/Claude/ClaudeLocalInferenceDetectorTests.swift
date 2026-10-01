import Foundation
import Testing
@testable import Infrastructure

@Suite
struct ClaudeLocalInferenceDetectorTests {
    /// Writes a temporary `~/.claude.json`, runs `body` against it, then removes the
    /// directory — same `defer`-scoped cleanup the analyzer tests use.
    private func withConfig<T>(_ json: String, _ body: (URL) throws -> T) throws -> T {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let url = tmpDir.appendingPathComponent(".claude.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return try body(url)
    }

    @Test func `missing config file is not local`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".claude.json")
        #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url) == false)
    }

    @Test func `config without a base url is not local`() throws {
        try withConfig(#"{"oauthAccount":{"emailAddress":"a@b.c"}}"#) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url) == false)
        }
    }

    @Test func `env base url on loopback is local`() throws {
        try withConfig(#"{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}"#) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
        }
    }

    @Test func `env base url on ipv4 loopback is local`() throws {
        try withConfig(#"{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:1234/v1"}}"#) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
        }
    }

    @Test func `env base url on a paid gateway is not local`() throws {
        try withConfig(#"{"env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic"}}"#) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url) == false)
        }
    }

    @Test func `provider entry on loopback is local when env is absent`() throws {
        let json = #"{"providers":[{"base_url":"https://api.anthropic.com"},{"base_url":"http://127.0.0.1:8080"}]}"#
        try withConfig(json) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
        }
    }

    @Test func `provider env entry on loopback is local when env is absent`() throws {
        let json = #"{"providers":[{"env":{"ANTHROPIC_BASE_URL":"http://[::1]:11434"}}]}"#
        try withConfig(json) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
        }
    }

    @Test func `a loopback provider does not override a remote env route`() throws {
        // The mixed config: the user is on z.ai today and keeps a local ollama entry
        // around from before. `providers` is a menu, `env` is the route — OR-ing the
        // two would mark the whole two-day window local and zero a real GLM estimate.
        let json = #"""
        {"env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic"},
         "providers":[{"base_url":"https://api.z.ai/api/anthropic"},
                      {"base_url":"http://localhost:11434"}]}
        """#
        try withConfig(json) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url) == false)
        }
    }

    @Test func `a remote provider does not override a loopback env route`() throws {
        let json = #"""
        {"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:11434"},
         "providers":[{"base_url":"https://api.anthropic.com"}]}
        """#
        try withConfig(json) { url in
            #expect(ClaudeLocalInferenceDetector.isLocallyServed(configURL: url))
        }
    }

    @Test(arguments: [
        "http://localhost:11434",
        "http://LOCALHOST:1234",
        "https://models.localhost/v1",
        "http://0.0.0.0:8000",
    ])
    func `loopback urls are recognised`(url: String) {
        #expect(ClaudeLocalInferenceDetector.isLoopback(url))
    }

    @Test(arguments: [
        "https://api.anthropic.com",
        "https://api.z.ai/api/anthropic",
        "http://192.168.1.10:11434",
        "https://my-localhost.example.com/v1",
        "not a url",
    ])
    func `non loopback urls are not`(url: String) {
        #expect(ClaudeLocalInferenceDetector.isLoopback(url) == false)
    }
}
