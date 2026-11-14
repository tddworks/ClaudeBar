import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// The real `muse usage --json` success shape; failure envelopes below are synthetic.
@MainActor @Suite
struct MetaMuseDefinitionTests {
    private static let captured = #"{"schemaVersion":1,"allowance":{"tier":"Muse Code High Usage","window":{"usedPercent":1,"resetsAtMs":1794651434000},"weekly":{"usedPercent":7,"resetsAtMs":1794787200000},"asOfMs":1794636810548,"source":"mint"},"reason":null,"hint":null}"#

    private func make(_ output: String = captured, exitCode: Int32 = 0, located: Bool = true,
                      executionError: UsageError? = nil) throws -> Provider {
        let definition = try ProviderFactory.builtIn("meta-muse")
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(located ? "/usr/local/bin/muse" : nil)
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable _, args, input, timeout, directory, _ in
                guard args == ["usage", "--json"], input == nil, timeout == 30, directory == nil else {
                    throw UsageError.executionFailed("Unexpected Muse command")
                }
                if let executionError { throw executionError }
                return CLIResult(output: output, exitCode: exitCode)
            }
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, cliExecutor: cli, network: MockNetworkClient(),
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        })
    }

    private func payload(_ allowance: String, version: String = "1") -> String {
        "{\"schemaVersion\":\(version),\"allowance\":\(allowance),\"reason\":null,\"hint\":null}"
    }

    @Test func `should show Muse Code through only its installed CLI and default login`() throws {
        let product = try make()
        let definition = product.definition
        #expect(product.id == "meta-muse")
        #expect(product.name == "Muse Code")
        #expect(product.plainIsInLineup)
        #expect(definition.defaultDataSource == "cli")
        #expect(definition.dataSources.map(\.kind) == ["cli"])
        #expect(definition.dataSources.first?.credential == nil)
        #expect(definition.profile.look.icon == "MetaMuseIcon")
        #expect(definition.profile.links.dashboard == nil)
        #expect(definition.settings.isEmpty)
        #expect(definition.accounts == nil)
        #expect(definition.keyDestinations.isEmpty)
        #expect(try definition.dataSources(forAccount: [:]).isEmpty)
    }

    @Test func `should show 99 percent session and 93 percent weekly left from Muse's allowance`() async throws {
        let usage = try await make().refreshPlain()
        #expect(usage.quotas.count == 2)
        #expect(usage.quota(for: .session)?.percentRemaining == 99)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 93)
        #expect(usage.accountTier == .custom("Muse Code High Usage"))
        #expect(usage.accountEmail == nil)
        #expect(usage.costUsage == nil)
    }

    @Test func `should convert millisecond resets without guessing the session length`() async throws {
        let usage = try await make().refreshPlain()
        #expect(usage.quota(for: .session)?.resetsAt == Date(timeIntervalSince1970: 1_794_651_434))
        #expect(usage.quota(for: .weekly)?.resetsAt == Date(timeIntervalSince1970: 1_794_787_200))
        #expect(usage.quota(for: .session)?.windowDuration == nil)
        #expect(usage.quota(for: .weekly)?.windowDuration == 604_800)
    }

    @Test(arguments: [0.0, 100.0, 17.25])
    func `should keep unused, depleted and fractional allowances`(_ used: Double) async throws {
        let usage = try await make(payload("{\"window\":{\"usedPercent\":\(used)}}")).refreshPlain()
        #expect(usage.quotas.count == 1)
        #expect(usage.quota(for: .session)?.percentRemaining == 100 - used)
        #expect(usage.quota(for: .session)?.resetsAt == nil)
        #expect(usage.accountTier == nil)
    }

    @Test func `should keep a weekly allowance when Muse supplies no session window`() async throws {
        let usage = try await make(payload(#"{"window":null,"weekly":{"usedPercent":20,"resetsAtMs":null}}"#)).refreshPlain()
        #expect(usage.quotas.count == 1)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 80)
        #expect(usage.quota(for: .weekly)?.resetsAt == nil)
    }

    @Test func `should preserve a future plan name and omit a blank tier`() async throws {
        for tier in ["Muse Code Team", "   "] {
            let usage = try await make(payload("{\"tier\":\"\(tier)\",\"window\":{\"usedPercent\":0}}")).refreshPlain()
            #expect(usage.accountTier == (tier == "   " ? nil : .custom(tier)))
        }
    }

    @Test(arguments: ["", "not JSON", "[]", "null", "{}",
                      #"{"schemaVersion":2,"allowance":{"window":{"usedPercent":1}}}"#,
                      #"{"schemaVersion":"1","allowance":{"window":{"usedPercent":1}}}"#,
                      #"{"schemaVersion":1,"allowance":null}"#,
                      #"{"schemaVersion":1,"allowance":[]}"#])
    func `should fail at reading unsupported or missing allowance envelopes`(_ output: String) async throws {
        let product = try make(output)
        await #expect(throws: UsageError.self) { try await product.refresh(product.defaultAccount) }
        #expect(product.defaultAccount.lastFailedStep == .mapping)
    }

    @Test(arguments: [#"{}"#, #"{"window":{}}"#, #"{"window":false}"#,
                      #"{"window":{"usedPercent":true}}"#, #"{"window":{"usedPercent":"1"}}"#,
                      #"{"window":{"usedPercent":-1}}"#, #"{"window":{"usedPercent":101}}"#,
                      #"{"window":{"usedPercent":1,"resetsAtMs":"1794651434000"}}"#,
                      #"{"window":{"usedPercent":1,"resetsAtMs":-1}}"#,
                      #"{"window":{"usedPercent":1},"weekly":[]}"#])
    func `should fail instead of showing malformed windows as healthy`(_ allowance: String) async throws {
        let product = try make(payload(allowance))
        await #expect(throws: UsageError.self) { try await product.refresh(product.defaultAccount) }
        #expect(product.defaultAccount.lastFailedStep == .mapping)
    }

    @Test func `should show Muse's reason and hint when no allowance is available`() async throws {
        let product = try make(#"{"schemaVersion":1,"allowance":null,"reason":"unavailable","hint":"Try again later."}"#)
        await #expect(throws: UsageError.executionFailed("Muse usage: unavailable. Try again later.")) {
            try await product.refreshPlain()
        }
    }

    @Test func `should ask for Muse login when its allowance reports a sign-in failure`() async throws {
        let product = try make(#"{"schemaVersion":1,"allowance":null,"reason":"not_logged_in","hint":"Run muse login."}"#)
        do {
            _ = try await product.refreshPlain()
            Issue.record("Expected a sign-in failure")
        } catch UsageError.sessionExpired(let hint) {
            #expect(hint == "not_logged_in. Run muse login.")
            #expect(product.defaultAccount.lastFailedStep == .mapping)
        }
    }

    @Test func `should say the CLI is missing when Muse is not installed`() async throws {
        let product = try make(located: false)
        #expect(!(await product.isAvailable(product.defaultAccount)))
        await #expect(throws: UsageError.cliNotFound("muse")) { try await product.refreshPlain() }
    }

    @Test func `should report a command failure without disclosing its output`() async throws {
        let product = try make("private command output", exitCode: 1)
        await #expect(throws: UsageError.executionFailed("`muse` exited with code 1")) {
            try await product.refreshPlain()
        }
        #expect(product.defaultAccount.lastFailedStep == .fetch)
    }

    @Test func `should keep a command timeout as a fetching failure`() async throws {
        let product = try make(executionError: .timeout)
        await #expect(throws: UsageError.timeout) { try await product.refreshPlain() }
        #expect(product.defaultAccount.lastFailedStep == .fetch)
    }
}
