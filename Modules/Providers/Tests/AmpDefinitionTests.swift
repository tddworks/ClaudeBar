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
        let definition = try ProviderFactory.builtIn("ampcode")
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
                makeTransport: { _,_,_,_ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                secrets: vault.scoped(to: login), environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }
    private func parse(_ output: String) async throws -> UsageSnapshot { try await make(output).refreshPlain() }

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
    func `should show the free tier as money left of its ceiling, $17.59 of $20`() async throws {
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
    func `should show the email the person is signed in as`() async throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try await parse(text)

        // Then
        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `should show 0% left when the free tier is spent`() async throws {
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
    func `should show free tier and individual credits as separate quotas`() async throws {
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
    func `should show individual credits as $50 left, with no percentage`() async throws {
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
    func `should show individual credits as $0 left, with no percentage, when they are spent`() async throws {
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
    func `should keep the free tier's dollars so the card shows them`() async throws {
        let freeQuota = try await parse(Self.sampleOutputZeroRemaining).quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota?.left == .money(Money(0, currency: "USD"), of: Money(20, currency: "USD")))
        #expect(freeQuota?.dollarRemaining == 0)
    }

    @Test
    func `should show individual credits alone when there is no free tier`() async throws {
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
    func `should name the free tier quota Free`() async throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try await parse(text)

        // Then
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        if let freeQuota, case .modelSpecific(let name) = freeQuota.quotaType.shape {
            #expect(name == "Free")
        } else {
            Issue.record("Expected modelSpecific quota type")
        }
    }

    @Test
    func `should tag the usage and every quota as Amp's`() async throws {
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
    func `should fail when Amp prints nothing`() async throws {
        // Given
        let text = ""

        // When/Then
        await #expect(throws: UsageError.self) {
            try await parse(text)
        }
    }

    @Test
    func `should fail when Amp prints something that is not its usage`() async throws {
        // Given
        let text = "some random text that is not amp usage output"

        // When/Then
        await #expect(throws: UsageError.self) {
            try await parse(text)
        }
    }
    @Test func `should be unavailable and say the CLI is not found when Amp is not installed`() async throws {
        let product = try make(Self.sampleOutput, located: false)
        let account = product.defaultAccount
        #expect(!(await product.isAvailable(account)))
        await #expect(throws: UsageError.cliNotFound("AmpCode")) { try await product.refresh(account) }
    }
    @Test func `should fail when Amp exits with an error`() async throws {
        await #expect(throws: UsageError.executionFailed("`amp` exited with code 1")) {
            try await make(Self.sampleOutput, exitCode: 1).refreshPlain()
        }
    }
    @Test func `should show an added account only by its own key, never the default CLI login`() async throws {
        let vault = MemoryVault()
        let provider = try make(Self.sampleOutput, vault: vault)
        let work = try provider.accounts.add(filling: ["apiKey": "work-key"])
        #expect(work.isEnabled)
        #expect(try await provider.refresh(work).quotas.count == 2)
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.authenticationRequired) { try await provider.refresh(work) }
        #expect(try await provider.refreshPlain().quotas.count == 2)
    }

    @Test func `should report a failure while running as it happened`() async throws {
        await #expect(throws: UsageError.executionFailed("timeout")) {
            try await make(Self.sampleOutput, executionError: .executionFailed("timeout")).refreshPlain()
        }
    }

}
