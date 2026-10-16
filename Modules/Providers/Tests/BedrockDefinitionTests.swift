import Foundation
import Mockable
import Providers
@testable import DataSources
import Quotas
import Testing

/// Bedrock as data: today's CloudWatch token sums, priced from the Bedrock
/// price list, as one cost with a line per model. The daily budget judges
/// that cost; it is never a quota.
@MainActor @Suite
struct BedrockDefinitionTests {
    final class Seen: @unchecked Sendable { var regions: [String] = []; var profiles: [String?] = [] }

    private func make(regions: String? = nil, profile: String? = nil, budget: String? = nil,
                      sums: [String: [String: [String: Double]]] = ["us-east-1": [
                          "anthropic.claude-sonnet-4": ["InputTokenCount": 1_000_000, "OutputTokenCount": 200_000, "Invocations": 40],
                          "us.amazon.nova-pro-v1:0": ["InputTokenCount": 500_000, "OutputTokenCount": 0, "Invocations": 10],
                      ]],
                      seen: Seen = Seen(), zone: any TimeZoneSource = Platform.current.timeZone,
                      now: Date = Date()) throws -> Provider {
        let client = MockCloudWatchClient()
        given(client).sums(namespace: .value("AWS/Bedrock"), dimension: .value("ModelId"), metrics: .any, region: .any, profile: .any, from: .any, to: .any)
            .willProduce { @Sendable _, _, _, region, profile, _, _ in
                seen.regions.append(region)
                seen.profiles.append(profile)
                return sums[region] ?? [:]
            }
        let catalog = MockPriceCatalog()
        given(catalog).prices(service: .value("AmazonBedrock"), ids: .any).willReturn([
            "anthropic.claude-sonnet-4": ["input": "3", "output": "15", "per": "1000000", "name": "Claude Sonnet 4"],
            "us.amazon.nova-pro-v1:0": ["input": "0.8", "output": "3.2", "per": "1000000", "name": "Nova Pro"],
        ])
        let settings = InMemoryProviderSettings()
        settings.setValue(regions, "regions", forProvider: "bedrock")
        settings.setValue(profile, "awsProfile", forProvider: "bedrock")
        settings.setValue(budget, "dailyBudget", forProvider: "bedrock")
        let definition = try ProviderFactory.builtIn("bedrock")
        var platform = Platform.current
        platform.timeZone = zone
        return Provider(definition: definition, settings: settings, makeDataSource: { [platform] source, _ in
            DataSources.make(source, providerId: definition.id, platform: platform, network: MockNetworkClient(),
                             cloudWatch: client, priceCatalog: catalog, scripts: ProviderFactory.builtInScripts,
                             environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory,
                             now: { now })
        })
    }

    @Test func `should keep Bedrock's name and dashboard, off until the person turns it on`() throws {
        let provider = try make()
        #expect(provider.name == "AWS Bedrock")
        #expect(!provider.plainIsInLineup)
        #expect(provider.plainDashboardURL?.absoluteString == "https://console.aws.amazon.com/bedrock/home")
    }

    @Test func `should show today's spend as one exact cost with a line per model, largest first`() async throws {
        let usage = try await make().refreshPlain()
        let cost = try #require(usage.costUsage)
        // 1M × $3 + 0.2M × $15 = $6; 0.5M × $0.80 = $0.40.
        #expect(cost.totalCost == Decimal(string: "6.4")!)
        #expect(cost.lines.map(\.label) == ["Claude Sonnet 4", "Nova Pro"])
        #expect(cost.lines.map(\.amount) == [6, Decimal(string: "0.4")!])
        #expect(cost.lines.first?.detail == "1.2M tokens · 40 calls")
        #expect(cost.resetText == "Today")
        // Money gone is never a quota.
        #expect(usage.quotas.isEmpty)
    }

    @Test func `should end today at the person's next midnight, even on the day their clocks move`() async throws {
        // 2026-03-08 12:00 in Los Angeles, the day it moves to summer time: 23 hours long.
        let now = Date(timeIntervalSince1970: 1_772_996_400)
        let usage = try await make(zone: Zones.losAngeles, now: now).refreshPlain()
        // 2026-03-09 00:00 PDT.
        #expect(usage.costUsage?.resetsAt == Date(timeIntervalSince1970: 1_773_039_600))
    }

    @Test func `should judge the cost against the daily budget, never as a quota`() async throws {
        let usage = try await make(budget: "10").refreshPlain()
        let cost = try #require(usage.costUsage)
        #expect(cost.budget == 10)
        #expect(cost.budgetStatusFromBuiltIn == BudgetStatus.from(cost: Decimal(string: "6.4")!, budget: 10))
        #expect(usage.quotas.isEmpty)
    }

    @Test func `should ask every region the person named, with their profile`() async throws {
        let seen = Seen()
        _ = try await make(regions: "us-east-1, eu-west-1", profile: "work", seen: seen).refreshPlain()
        #expect(seen.regions == ["us-east-1", "eu-west-1"])
        #expect(seen.profiles == ["work", "work"])
    }

    @Test func `should use the default credentials in us-east-1 when the person names no profile or region`() async throws {
        let seen = Seen()
        _ = try await make(seen: seen).refreshPlain()
        #expect(seen.regions == ["us-east-1"])
        #expect(seen.profiles == [nil])
    }

    @Test func `should show a model with no known price as a line of nothing, and say so`() async throws {
        let usage = try await make(sums: ["us-east-1": ["acme.mystery": ["InputTokenCount": 10, "Invocations": 1]]]).refreshPlain()
        let line = try #require(usage.costUsage?.lines.first)
        #expect(line.amount == 0)
        #expect(line.detail == "10 tokens · 1 calls · no price known")
    }

    @Test func `should show $0 when nothing was used today, not a missing cost`() async throws {
        let usage = try await make(sums: [:]).refreshPlain()
        #expect(usage.costUsage?.totalCost == 0)
        #expect(usage.costUsage?.lines.isEmpty == true)
    }
}
