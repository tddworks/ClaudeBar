import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// `codex.json`, run through the real `Provider` and `DataSource` over stubbed
/// connections. The fixtures are the ones today's `CodexUsageProbe`,
/// `CodexAPIUsageProbe` and `DefaultCodexRPCClient` tests use: the definition
/// must give the same usage they gave before those types can be deleted.
@MainActor
@Suite
struct CodexDefinitionTests {

    // MARK: - The definition

    @Test
    func `codex json keeps the definition laws`() throws {
        let codex = try Providers.builtIn("codex")

        #expect(codex.id == "codex")
        #expect(codex.profile.name == "Codex")
        #expect(codex.cli == "codex")
        #expect(codex.dataSources.map(\.kind) == ["rpc", "api", "tty"])
        #expect(codex.defaultDataSource == "rpc")
        #expect(codex.dataSource("rpc")?.fallback?.to == "tty")
        #expect(codex.dataSource("tty")?.hidden == true)
        #expect(codex.profile.links.dashboard == URL(string: "https://platform.openai.com/usage"))
    }

    @Test
    func `codex uses rpc until the person picks api`() throws {
        let rpc = try StubbedProvider(providerId: "codex")
        let api = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { rpc.cleanUp(); api.cleanUp() }

        #expect(try rpc.make("codex").provider.activeKind == "rpc")
        #expect(try api.make("codex").provider.activeKind == "api")
    }

    // MARK: - RPC

    @Test
    func `rpc reads the session and weekly windows`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30,"resetsAt":1735000000,"windowDurationMins":300},"secondary":{"usedPercent":50,"resetsAt":1735500000}}}}"#)
        let codex = try stub.make("codex")

        let usage = try await codex.refresh()

        #expect(usage.providerId == "codex")
        #expect(usage.quota(for: .session)?.percentRemaining == 70)
        #expect(usage.quota(for: .session)?.resetsAt == Date(timeIntervalSince1970: 1735000000))
        #expect(usage.quota(for: .session)?.windowDuration == TimeInterval(300 * 60))
        #expect(usage.quota(for: .weekly)?.percentRemaining == 50)
        #expect(codex.answeredBy == "rpc")
        #expect(codex.lastError == nil)
    }

    @Test
    func `rpc gives a free plan its session at full`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"free"}}}"#)

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quotas.count == 1)
        #expect(usage.quota(for: .session)?.percentRemaining == 100)
        #expect(usage.quota(for: .session)?.resetText == "Free plan")
    }

    @Test
    func `rpc adds the extra buckets after session and weekly`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30,"resetsAt":1735000000},"secondary":{"usedPercent":10}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":30,"resetsAt":1735000000}},"codex_spark":{"limitId":"codex_spark","limitName":"Codex Spark","primary":{"usedPercent":40,"resetsAt":1735100000},"secondary":{"usedPercent":20,"windowDurationMins":10080}}}}}"#)

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quotas.count == 4)
        #expect(usage.quotas[0].quotaType == .session)
        #expect(usage.quotas[2].quotaType == .timeLimit("Spark"))
        #expect(usage.quotas[2].percentRemaining == 60)
        #expect(usage.quotas[3].quotaType == .timeLimit("Spark 7d"))
        #expect(usage.quotas[3].percentRemaining == 80)
        #expect(usage.quotas[3].windowDuration == TimeInterval(10080 * 60))
    }

    @Test
    func `rpc skips the main bucket and buckets without windows`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":30}},"codex_spark":{"limitId":"codex_spark","limitName":"Codex Spark"},"codex_other":{"limitId":"codex_other","limitName":"Other","primary":{"usedPercent":5}}}}}"#)

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quotas.map(\.quotaType) == [.session, .timeLimit("Other")])
        #expect(usage.quotas[1].percentRemaining == 95)
    }

    @Test
    func `when rpc fails the terminal answers`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"error":{"message":"Authentication required"}}"#)
        stub.answerTerminal("""
        Account: someone@example.com
        5h limit:  [██████░░░░] 80% left (resets 14:00)
        Weekly limit: [███░░░░░░] 35% left
        """)
        let codex = try stub.make("codex")

        let usage = try await codex.refresh()

        #expect(usage.quota(for: .session)?.percentRemaining == 80)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 35)
        #expect(codex.answeredBy == "tty")
        #expect(codex.answeredByLabel == "Terminal")
    }

    @Test
    func `when rpc and the terminal both fail the rpc failure is reported and the last usage kept`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        // First refresh: initialize, usage, the account. Second: initialize, then an RPC error.
        let answers = [
            #"{"id":1,"result":{}}"#,
            #"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30}}}}"#,
            #"{"id":3,"result":{"account":null}}"#,
            #"{"id":1,"result":{}}"#,
            #"{"id":2,"error":{"message":"Authentication required"}}"#,
        ]
        let received = Counter()
        given(stub.transport).send(.any).willReturn(())
        given(stub.transport).close().willReturn(())
        given(stub.transport).receive().willProduce { @Sendable in Data(answers[received.next() - 1].utf8) }
        given(stub.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willThrow(UsageError.executionFailed("TTY not available"))
        let codex = try stub.make("codex")
        let first = try await codex.refresh()

        await #expect(throws: UsageError.self) { try await codex.refresh() }

        #expect(codex.lastError as? UsageError == .executionFailed("RPC error: Authentication required"))
        #expect(codex.lastFailedStep == .fetch)
        #expect(codex.snapshot == first)
    }

    // MARK: - Terminal

    @Test
    func `the terminal says when codex is not logged in`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "tty", providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerTerminal("Error: Not logged in. Please log in with `codex login`.")
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.authenticationRequired) { try await codex.refresh() }
        #expect(codex.lastFailedStep == .mapping)
    }

    // MARK: - API

    @Test
    func `api prefers the usage headers`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"reset_after_seconds":3600}}}"#,
                        headers: ["x-codex-primary-used-percent": "25.5", "x-codex-secondary-used-percent": "40"])

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quota(for: .session)?.percentRemaining == 74.5)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 60)
        #expect(usage.quota(for: .session)?.resetsAt != nil)
    }

    @Test
    func `api falls back to the body without headers`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":15.0,"reset_at":1735000000},"secondary_window":{"used_percent":45.0}}}"#)

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quota(for: .session)?.percentRemaining == 85)
        #expect(usage.quota(for: .session)?.resetsAt == Date(timeIntervalSince1970: 1735000000))
        #expect(usage.quota(for: .weekly)?.percentRemaining == 55)
    }

    @Test
    func `api adds extra limits after session and weekly`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":10},"secondary_window":{"used_percent":20}},"additional_rate_limits":[{"limit_name":"codex_spark","rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":18000},"secondary_window":{"used_percent":40}}}]}"#)

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quotas.map(\.quotaType) == [.session, .weekly, .timeLimit("Spark"), .timeLimit("Spark 7d")])
        #expect(usage.quotas[2].percentRemaining == 70)
        #expect(usage.quotas[2].windowDuration == 18000)
        #expect(usage.quotas[3].percentRemaining == 60)
    }

    @Test
    func `api reads the plan and the credits`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10}},"credits":{"has_credits":true,"balance":"900"}}"#,
                        headers: ["x-codex-credits-balance": "750"])

        let usage = try await stub.make("codex").refresh()

        #expect(usage.accountTier == .custom("PLUS"))
        #expect(usage.costUsage?.totalCost == 250)
        #expect(usage.costUsage?.budget == 1000)
    }

    // https://github.com/tddworks/ClaudeBar/issues/444
    @Test
    func `api without credits shows no cost`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":604800}},"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}"#)

        let usage = try await stub.make("codex").refresh()

        #expect(usage.costUsage == nil)
    }

    @Test
    func `api with nothing to say is no usage, not a failure`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP("{}")

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quotas.isEmpty)
    }

    @Test
    func `api without a key says so at the lookup step`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.make("codex")

        #expect(await codex.isAvailable() == false)
        await #expect(throws: UsageError.authenticationRequired) { try await codex.refresh() }
        #expect(codex.lastFailedStep == .lookup)
    }

    @Test
    func `api refused even after a refresh means log in again`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP("", status: 401)
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.sessionExpired()) { try await codex.refresh() }
    }

    @Test
    func `api refreshes an old token, uses it, and writes it back`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(token: "old-token", accountId: "acct-1", lastRefresh: Date().addingTimeInterval(-9 * 86400))
        given(stub.network).request(.any).willProduce { @Sendable request in
            if request.url?.absoluteString.contains("oauth/token") == true {
                return (Data(#"{"access_token":"new-token","refresh_token":"new-refresh-token"}"#.utf8), StubbedProvider.response(200))
            }
            let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer new-token"
            return (Data(#"{"rate_limit":{"primary_window":{"used_percent":10.0}}}"#.utf8), StubbedProvider.response(authorized ? 200 : 401))
        }

        let usage = try await stub.make("codex").refresh()

        #expect(usage.quota(for: .session)?.percentRemaining == 90)
        let tokens = try stub.readCodexAuth()["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "new-token")
        #expect(tokens?["refresh_token"] as? String == "new-refresh-token")
        #expect(tokens?["account_id"] as? String == "acct-1")
    }

    @Test
    func `an expired refresh token means log in again`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(lastRefresh: Date().addingTimeInterval(-9 * 86400))
        stub.answerHTTP(#"{"error":{"code":"refresh_token_expired"}}"#, status: 400)
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.sessionExpired()) { try await codex.refresh() }
        #expect(codex.lastFailedStep == .lookup)
    }
}
