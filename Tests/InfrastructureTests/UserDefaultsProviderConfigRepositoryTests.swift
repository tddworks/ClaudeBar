import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("UserDefaultsProviderConfigRepository Tests")
struct UserDefaultsProviderConfigRepositoryTests {

    private let testSuiteName = "com.claudebar.test.config.\(UUID().uuidString)"

    private func makeRepository() -> UserDefaultsProviderConfigRepository {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        return UserDefaultsProviderConfigRepository(userDefaults: defaults)
    }

    private func cleanupDefaults() {
        UserDefaults().removePersistentDomain(forName: testSuiteName)
    }

    // MARK: - Z.ai Config Path Tests

    @Test
    func `zaiConfigPath returns empty string when not set`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        let path = repository.zaiConfigPath()

        #expect(path.isEmpty)
    }

    @Test
    func `zaiConfigPath returns stored value when set`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let testPath = "/custom/path/to/settings.json"
        repository.setZaiConfigPath(testPath)

        let path = repository.zaiConfigPath()

        #expect(path == testPath)
    }

    @Test
    func `setZaiConfigPath persists value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let testPath = "~/.claude/custom.json"

        repository.setZaiConfigPath(testPath)
        let retrieved = repository.zaiConfigPath()

        #expect(retrieved == testPath)
    }

    @Test
    func `setZaiConfigPath can update existing value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        
        repository.setZaiConfigPath("/path/one")
        #expect(repository.zaiConfigPath() == "/path/one")

        repository.setZaiConfigPath("/path/two")
        #expect(repository.zaiConfigPath() == "/path/two")
    }

    @Test
    func `zaiConfigPath supports empty string reset`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        
        repository.setZaiConfigPath("/some/path")
        #expect(!repository.zaiConfigPath().isEmpty)

        repository.setZaiConfigPath("")
        #expect(repository.zaiConfigPath().isEmpty)
    }

    // MARK: - GLM Auth Env Var Tests

    @Test
    func `glmAuthEnvVar returns empty string when not set`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        let envVar = repository.glmAuthEnvVar()

        #expect(envVar.isEmpty)
    }

    @Test
    func `glmAuthEnvVar returns stored value when set`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let testEnvVar = "GLM_AUTH_TOKEN"
        repository.setGlmAuthEnvVar(testEnvVar)

        let envVar = repository.glmAuthEnvVar()

        #expect(envVar == testEnvVar)
    }

    @Test
    func `setGlmAuthEnvVar persists value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let testEnvVar = "CUSTOM_GLM_TOKEN"

        repository.setGlmAuthEnvVar(testEnvVar)
        let retrieved = repository.glmAuthEnvVar()

        #expect(retrieved == testEnvVar)
    }

    @Test
    func `setGlmAuthEnvVar can update existing value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        
        repository.setGlmAuthEnvVar("OLD_VAR")
        #expect(repository.glmAuthEnvVar() == "OLD_VAR")

        repository.setGlmAuthEnvVar("NEW_VAR")
        #expect(repository.glmAuthEnvVar() == "NEW_VAR")
    }

    @Test
    func `glmAuthEnvVar supports empty string reset`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        
        repository.setGlmAuthEnvVar("SOME_VAR")
        #expect(!repository.glmAuthEnvVar().isEmpty)

        repository.setGlmAuthEnvVar("")
        #expect(repository.glmAuthEnvVar().isEmpty)
    }

    // MARK: - Copilot Auth Env Var Tests

    @Test
    func `copilotAuthEnvVar returns empty string when not set`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        let envVar = repository.copilotAuthEnvVar()

        #expect(envVar.isEmpty)
    }

    @Test
    func `copilotAuthEnvVar returns stored value when set`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let testEnvVar = "GITHUB_TOKEN"
        repository.setCopilotAuthEnvVar(testEnvVar)

        let envVar = repository.copilotAuthEnvVar()

        #expect(envVar == testEnvVar)
    }

    @Test
    func `setCopilotAuthEnvVar persists value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let testEnvVar = "CUSTOM_GH_TOKEN"

        repository.setCopilotAuthEnvVar(testEnvVar)
        let retrieved = repository.copilotAuthEnvVar()

        #expect(retrieved == testEnvVar)
    }

    @Test
    func `setCopilotAuthEnvVar can update existing value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        
        repository.setCopilotAuthEnvVar("OLD_TOKEN")
        #expect(repository.copilotAuthEnvVar() == "OLD_TOKEN")

        repository.setCopilotAuthEnvVar("NEW_TOKEN")
        #expect(repository.copilotAuthEnvVar() == "NEW_TOKEN")
    }

    @Test
    func `copilotAuthEnvVar supports empty string reset`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        
        repository.setCopilotAuthEnvVar("SOME_TOKEN")
        #expect(!repository.copilotAuthEnvVar().isEmpty)

        repository.setCopilotAuthEnvVar("")
        #expect(repository.copilotAuthEnvVar().isEmpty)
    }

    // MARK: - Isolation Tests

    @Test
    func `config settings are isolated from each other`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setZaiConfigPath("/path/to/config")
        repository.setGlmAuthEnvVar("GLM_TOKEN")
        repository.setCopilotAuthEnvVar("GH_TOKEN")

        #expect(repository.zaiConfigPath() == "/path/to/config")
        #expect(repository.glmAuthEnvVar() == "GLM_TOKEN")
        #expect(repository.copilotAuthEnvVar() == "GH_TOKEN")
    }

    @Test
    func `changing one setting does not affect others`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setZaiConfigPath("/original/path")
        repository.setGlmAuthEnvVar("ORIGINAL_GLM")
        
        repository.setZaiConfigPath("/updated/path")

        #expect(repository.zaiConfigPath() == "/updated/path")
        #expect(repository.glmAuthEnvVar() == "ORIGINAL_GLM")
    }

    // MARK: - Persistence Tests

    @Test
    func `values persist across repository instances`() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defer { cleanupDefaults() }

        let repository1 = UserDefaultsProviderConfigRepository(userDefaults: defaults)
        repository1.setZaiConfigPath("/persistent/path")
        repository1.setGlmAuthEnvVar("PERSISTENT_GLM")
        repository1.setCopilotAuthEnvVar("PERSISTENT_GH")

        let repository2 = UserDefaultsProviderConfigRepository(userDefaults: defaults)
        
        #expect(repository2.zaiConfigPath() == "/persistent/path")
        #expect(repository2.glmAuthEnvVar() == "PERSISTENT_GLM")
        #expect(repository2.copilotAuthEnvVar() == "PERSISTENT_GH")
    }

    @Test
    func `shared singleton instance is accessible`() {
        #expect(UserDefaultsProviderConfigRepository.shared != nil)
    }

    // MARK: - Edge Cases

    @Test
    func `handles special characters in paths`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let pathWithSpaces = "/path with spaces/to/settings.json"

        repository.setZaiConfigPath(pathWithSpaces)

        #expect(repository.zaiConfigPath() == pathWithSpaces)
    }

    @Test
    func `handles special characters in environment variable names`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let envVarWithUnderscores = "MY_CUSTOM_DEEP_TOKEN_VAR"

        repository.setGlmAuthEnvVar(envVarWithUnderscores)

        #expect(repository.glmAuthEnvVar() == envVarWithUnderscores)
    }

    @Test
    func `handles long path strings`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }
        let longPath = String(repeating: "/very/long/path/", count: 20)

        repository.setZaiConfigPath(longPath)

        #expect(repository.zaiConfigPath() == longPath)
    }
}
