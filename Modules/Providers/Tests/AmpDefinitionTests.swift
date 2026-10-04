import Testing
import Foundation
import Mockable
import Providers
import DataSources
import Quotas

/// Amp as data: `amp usage --no-color` run as a command, read by
/// `amp-usage.js` — the old probe's screens, quota for quota, with the free
/// tier as money of its ceiling.
@MainActor @Suite
struct AmpDefinitionTests {

    private func make(_ output: String, exitCode: Int32 = 0, executionError: UsageError? = nil, located: Bool = true, vault: MemoryVault = MemoryVault()) throws -> Provider {
        let definition = try Providers.builtIn("ampcode")
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(located ? "/usr/local/bin/amp" : nil)
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable _, args, input, timeout, directory, _ in
                #expect(args == ["usage", "--no-color"])
                #expect(timeout == 8)
                #expect(input == nil)
                #expect(directory == nil)
                if let executionError { throw executionError }
                return CLIResult(output: output, exitCode: exitCode)
            }
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: cli, network: MockNetworkClient(),
                makeTransport: { _,_,_,_ in MockRPCTransport() }, scripts: Providers.builtInScripts,
                secrets: vault.scoped(to: login), environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }
    private func parse(_ output: String) async throws -> UsageSnapshot { try await make(output).defaultAccount.refresh() }

    // MARK: - Sample Data

    static let sampleOutput = """
    Signed in as user@example.com (username)
    Amp Free: $17.59/$20 remaining (replenishes +$0.83/hour) [+100% bonus for 19 more days] - https://ampcode.com/settings#amp-free
    Individual credits: $0 remaining - https://ampcode.com/settings
    """


    static let sampleOutputZeroRemaining = """
    Signed in as user@example.com (username)
    Amp Free: $0/$20 remaining (replenishes +$0.83/hour) - https://ampcode.com/settings#amp-free
    Individual credits: $0 remaining - https://ampcode.com/settings
    """

    static let sampleOutputWithIndividualCredits = """
    Signed in as user@example.com (username)
    Amp Free: $17.59/$20 remaining (replenishes +$0.83/hour) [+100% bonus for 19 more days] - https://ampcode.com/settings#amp-free
    Individual credits: $50 remaining - https://ampcode.com/settings
    """

    static let sampleOutputIndividualCreditsOnly = """
    Signed in as user@example.com (username)
    Individual credits: $50 remaining - https://ampcode.com/settings
    """

    // MARK: - Parsing Tests

    @Test
    func `parses free tier credits into money of its ceiling`() async throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try await parse(text)

        // Then - $17.59/$20 = 87.95%
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota != nil)
        #expect(freeQuota!.left == .money(Money(Decimal(string: "17.59")!, currency: "USD"), of: Money(20, currency: "USD")))
        #expect(freeQuota!.percentLeft == 87.95)
    }

    @Test
    func `extracts account email`() async throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try await parse(text)

        // Then
        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `handles zero remaining with total`() async throws {
        // Given
        let text = Self.sampleOutputZeroRemaining

        // When
        let snapshot = try await parse(text)

        // Then - $0/$20 = 0%
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota != nil)
        #expect(freeQuota!.percentLeft == 0.0)
    }

    @Test
    func `parses both free and individual credits as separate quotas`() async throws {
        // Given - both lines present with non-zero values
        let text = Self.sampleOutputWithIndividualCredits

        // When
        let snapshot = try await parse(text)

        // Then - both quotas parsed
        #expect(snapshot.quotas.count == 2)
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        let creditsQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(freeQuota != nil)
        #expect(creditsQuota != nil)
    }

    @Test
    func `individual credits has dollarRemaining set`() async throws {
        // Given
        let text = Self.sampleOutputWithIndividualCredits

        // When
        let snapshot = try await parse(text)

        // Then - $50 remaining with no cap
        let creditsQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(creditsQuota?.dollarRemaining == 50)
        #expect(creditsQuota?.percentLeft == nil)
    }

    @Test
    func `individual credits zero remaining has dollarRemaining zero`() async throws {
        // Given - "$0 remaining" with no denominator
        let text = Self.sampleOutput

        // When
        let snapshot = try await parse(text)

        // Then
        let creditsQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(creditsQuota?.dollarRemaining == 0)
        #expect(creditsQuota?.percentLeft == nil)
    }

    @Test
    func `free tier quota keeps its dollars, so the card shows them`() async throws {
        let freeQuota = try await parse(Self.sampleOutputZeroRemaining).quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota?.left == .money(Money(0, currency: "USD"), of: Money(20, currency: "USD")))
        #expect(freeQuota?.dollarRemaining == 0)
    }

    @Test
    func `individual credits only is valid snapshot`() async throws {
        // Given - no free tier line, only individual credits
        let text = Self.sampleOutputIndividualCreditsOnly

        // When
        let snapshot = try await parse(text)

        // Then
        #expect(snapshot.quotas.count == 1)
        let individualQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(individualQuota != nil)
        #expect(individualQuota?.dollarRemaining == 50)
    }

    @Test
    func `maps to correct QuotaType`() async throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try await parse(text)

        // Then
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        if let freeQuota, case .modelSpecific(let name) = freeQuota.quotaType {
            #expect(name == "Free")
        } else {
            Issue.record("Expected modelSpecific quota type")
        }
    }

    @Test
    func `sets providerId correctly`() async throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try await parse(text)

        // Then
        #expect(snapshot.providerId == "ampcode")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "ampcode" })
    }

    // MARK: - Error Handling Tests

    @Test
    func `throws parseFailed on empty output`() async throws {
        // Given
        let text = ""

        // When/Then
        await #expect(throws: UsageError.self) {
            try await parse(text)
        }
    }

    @Test
    func `throws parseFailed on garbage output`() async throws {
        // Given
        let text = "some random text that is not amp usage output"

        // When/Then
        await #expect(throws: UsageError.self) {
            try await parse(text)
        }
    }
    @Test func `missing binary keeps the legacy error`() async throws {
        let account = try make(Self.sampleOutput, located: false).defaultAccount
        #expect(!(await account.isAvailable()))
        await #expect(throws: UsageError.cliNotFound("AmpCode")) { try await account.refresh() }
    }
    @Test func `nonzero exit cannot become usage`() async throws {
        await #expect(throws: UsageError.executionFailed("`amp` exited with code 1")) {
            try await make(Self.sampleOutput, exitCode: 1).defaultAccount.refresh()
        }
    }
    @Test func `added account cannot use a default CLI login without its own key`() async throws {
        let vault = MemoryVault()
        let provider = try make(Self.sampleOutput, vault: vault)
        let work = try provider.addAccount(filling: ["apiKey": "work-key"])
        #expect(work.isEnabled)
        #expect(try await work.refresh().quotas.count == 2)
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.authenticationRequired) { try await work.refresh() }
        #expect(try await provider.defaultAccount.refresh().quotas.count == 2)
    }

    @Test func `a failure while running is reported as it happened`() async throws {
        await #expect(throws: UsageError.executionFailed("timeout")) {
            try await make(Self.sampleOutput, executionError: .executionFailed("timeout")).defaultAccount.refresh()
        }
    }

}
