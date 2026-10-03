import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for provider-level settings in JSONSettingsRepository.
@Suite("JSONSettingsRepository Provider Settings Tests")
struct JSONSettingsRepositoryProviderTests {

    private func makeRepository() -> (JSONSettingsRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)
        let repo = JSONSettingsRepository(store: store)
        return (repo, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Provider Enabled State

    @Test
    func `isEnabled defaults to true`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isEnabled(forProvider: "claude") == true)
    }

    @Test
    func `isEnabled with custom default returns that default`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isEnabled(forProvider: "copilot", defaultValue: false) == false)
    }

    @Test
    func `setEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        #expect(repo.isEnabled(forProvider: "claude") == false)
    }

    @Test
    func `providers have independent enabled state`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        repo.setEnabled(true, forProvider: "codex")

        #expect(repo.isEnabled(forProvider: "claude") == false)
        #expect(repo.isEnabled(forProvider: "codex") == true)
    }

    // MARK: - Custom Card URL

    @Test
    func `customCardURL defaults to nil`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `setCustomCardURL persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == "https://claude.owo.nz/")
    }

    @Test
    func `setCustomCardURL nil removes value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL(nil, forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `setCustomCardURL empty string removes value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL("", forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `customCardURL is per provider`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL("https://codex.example.com/", forProvider: "codex")

        #expect(repo.customCardURL(forProvider: "claude") == "https://claude.owo.nz/")
        #expect(repo.customCardURL(forProvider: "codex") == "https://codex.example.com/")
        #expect(repo.customCardURL(forProvider: "gemini") == nil)
    }

    // MARK: - Claude Settings

    @Test
    func `claudeProbeMode defaults to cli`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeProbeMode() == .cli)
    }

    @Test
    func `setClaudeProbeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeProbeMode(.api)
        #expect(repo.claudeProbeMode() == .api)
    }

    @Test
    func `setClaudeProbeMode persists localFile value`() {
        // Issue #198: the Local File mode for Claude Desktop users persists
        // like the other modes — the raw String storage needs no change.
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeProbeMode(.localFile)
        #expect(repo.claudeProbeMode() == .localFile)
    }

    @Test
    func `claudeCliFallbackEnabled defaults to true`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeCliFallbackEnabled() == true)
    }

    @Test
    func `setClaudeCliFallbackEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeCliFallbackEnabled(false)
        #expect(repo.claudeCliFallbackEnabled() == false)
    }

    // MARK: - Codex Settings

    @Test
    func `codexProbeMode defaults to rpc`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.codexProbeMode() == .rpc)
    }

    @Test
    func `setCodexProbeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCodexProbeMode(.api)
        #expect(repo.codexProbeMode() == .api)
    }

    // MARK: - Kimi Settings

    @Test
    func `kimiProbeMode defaults to cli`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.kimiProbeMode() == .cli)
    }

    @Test
    func `setKimiProbeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setKimiProbeMode(.api)
        #expect(repo.kimiProbeMode() == .api)
    }

    // MARK: - Zai Settings

    @Test
    func `zaiConfigPath defaults to empty string`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.zaiConfigPath() == "")
    }

    @Test
    func `setZaiConfigPath persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setZaiConfigPath("/custom/path")
        #expect(repo.zaiConfigPath() == "/custom/path")
    }

    @Test
    func `glmAuthEnvVar defaults to empty string`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.glmAuthEnvVar() == "")
    }

    @Test
    func `setGlmAuthEnvVar persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setGlmAuthEnvVar("GLM_TOKEN")
        #expect(repo.glmAuthEnvVar() == "GLM_TOKEN")
    }

    // MARK: - Copilot Settings

    @Test
    func `copilotProbeMode defaults to billing`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.copilotProbeMode() == .billing)
    }

    @Test
    func `setCopilotProbeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCopilotProbeMode(.copilotAPI)
        #expect(repo.copilotProbeMode() == .copilotAPI)
    }

    @Test
    func `copilotAuthEnvVar defaults to empty string`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.copilotAuthEnvVar() == "")
    }

    @Test
    func `copilotMonthlyLimit defaults to nil`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.copilotMonthlyLimit() == nil)
    }

    @Test
    func `setCopilotMonthlyLimit persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCopilotMonthlyLimit(100)
        #expect(repo.copilotMonthlyLimit() == 100)
    }

    // MARK: - Bedrock Settings

    @Test
    func `awsProfileName defaults to empty string`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.awsProfileName() == "")
    }

    @Test
    func `bedrockRegions defaults to us-east-1`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.bedrockRegions() == ["us-east-1"])
    }

    @Test
    func `setBedrockRegions persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setBedrockRegions(["us-west-2", "eu-west-1"])
        #expect(repo.bedrockRegions() == ["us-west-2", "eu-west-1"])
    }

    @Test
    func `bedrockDailyBudget defaults to nil`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.bedrockDailyBudget() == nil)
    }

    @Test
    func `setBedrockDailyBudget persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setBedrockDailyBudget(25.50)
        #expect(repo.bedrockDailyBudget() == 25.50)
    }

    // MARK: - Hook Settings

    @Test
    func `isHookEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isHookEnabled() == false)
    }

    @Test
    func `setHookEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setHookEnabled(true)
        #expect(repo.isHookEnabled() == true)
    }

    @Test
    func `hookPort defaults to 19847`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.hookPort() == HookConstants.defaultPort)
    }

    @Test
    func `setHookPort persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setHookPort(8080)
        #expect(repo.hookPort() == 8080)
    }

    // MARK: - MiniMax Settings

    @Test
    func `minimaxRegion defaults to china`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.minimaxRegion() == .china)
    }

    @Test
    func `setMinimaxRegion persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setMinimaxRegion(.international)
        #expect(repo.minimaxRegion() == .international)
    }

}
