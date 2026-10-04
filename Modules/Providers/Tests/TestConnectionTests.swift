import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// *Test Connection* — the active data source looks up its key and fetches,
/// stopping before mapping, so a person sees what came back or which step failed.
@MainActor
@Suite
struct TestConnectionTests {
    @Test
    func `a connection that answers shows its status`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(accountId: "me")
        stub.answerHTTP(#"{"anything":"unmapped"}"#)
        let codex = try stub.make("codex").provider

        let result = await codex.testConnection()

        #expect(try result.get().status == 200)
    }

    @Test
    func `a connection with no key names the lookup step`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.make("codex").provider

        let result = await codex.testConnection()

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure")
            return
        }
        #expect(error.step == .lookup)
    }

    @Test
    func `a successful test checks a CLI session for later background refreshes`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20}}}}"#)
        let codex = try stub.make("codex").provider

        _ = await codex.testConnection()

        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == true)
    }
}

/// The fallback a definition lets the person switch off — Claude's API → CLI.
@MainActor
@Suite
struct FallbackSettingTests {
    @Test
    func `a switchable fallback is on until turned off, and saved as the provider's setting`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let settings = InMemoryProviderSettings()
        let provider = try claude.provider(settings: settings).provider

        #expect(provider.isFallbackEnabled(from: "api"))

        provider.setFallbackEnabled(false, from: "api")

        #expect(provider.isFallbackEnabled(from: "api") == false)
        #expect(settings.isOn("cliFallbackEnabled", forProvider: "claude") == false)
    }

    @Test
    func `a fixed fallback is always on and can't be switched`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let provider = try claude.provider().provider

        provider.setFallbackEnabled(false, from: "cli")

        #expect(provider.isFallbackEnabled(from: "cli"))
    }
}
