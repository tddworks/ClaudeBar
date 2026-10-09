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
    func `should offer Codex over RPC first, then the API, with a hidden terminal fallback and OpenAI's usage dashboard`() throws {
        let codex = try ProviderFactory.builtIn("codex")

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
    func `should read Codex over RPC until the person picks the API`() throws {
        let rpc = try StubbedProvider(providerId: "codex")
        let api = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { rpc.cleanUp(); api.cleanUp() }

        #expect(try rpc.makeProvider("codex").configuration.activeKind == "rpc")
        #expect(try api.makeProvider("codex").configuration.activeKind == "api")
    }

    // MARK: - RPC

    @Test
    func `should show the session and weekly windows with their resets when Codex answers over RPC`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30,"resetsAt":1735000000,"windowDurationMins":300},"secondary":{"usedPercent":50,"resetsAt":1735500000}}}}"#)
        let codex = try stub.make("codex")

        let usage = try await codex.refreshPlain()

        #expect(usage.providerId == "codex")
        #expect(usage.quota(for: .session)?.percentRemaining == 70)
        #expect(usage.quota(for: .session)?.resetsAt == Date(timeIntervalSince1970: 1735000000))
        #expect(usage.quota(for: .session)?.windowDuration == TimeInterval(300 * 60))
        #expect(usage.quota(for: .weekly)?.percentRemaining == 50)
        #expect(codex.defaultAccount.answeredBy == "rpc")
        #expect(codex.defaultAccount.lastError == nil)
    }

    @Test
    func `should show Codex's usage over RPC when its login is kept in the Keychain, with no auth.json (#525)`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30,"resetsAt":1735000000}}}}"#)
        given(stub.cli).locate(.any).willReturn("/usr/local/bin/codex")
        let codex = try stub.make("codex")

        #expect(await codex.isPlainAvailable())
        let usage = try await codex.refreshPlain()

        #expect(usage.quota(for: .session)?.percentRemaining == 70)
        #expect(codex.defaultAccount.answeredBy == "rpc")
    }

    @Test
    func `should show a free plan's session full, labelled Free plan`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"free"}}}"#)

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quotas.count == 1)
        #expect(usage.quota(for: .session)?.percentRemaining == 100)
        #expect(usage.quota(for: .session)?.resetText == "Free plan")
    }

    @Test
    func `should show Spark's windows after the session and weekly ones`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30,"resetsAt":1735000000},"secondary":{"usedPercent":10}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":30,"resetsAt":1735000000}},"codex_spark":{"limitId":"codex_spark","limitName":"Codex Spark","primary":{"usedPercent":40,"resetsAt":1735100000},"secondary":{"usedPercent":20,"windowDurationMins":10080}}}}}"#)

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quotas.count == 4)
        #expect(usage.quotas[0].quotaType == .session)
        #expect(usage.quotas[2].quotaType == .timeLimit("Spark"))
        #expect(usage.quotas[2].percentRemaining == 60)
        #expect(usage.quotas[3].quotaType == .timeLimit("Spark 7d"))
        #expect(usage.quotas[3].percentRemaining == 80)
        #expect(usage.quotas[3].windowDuration == TimeInterval(10080 * 60))
    }

    @Test
    func `should show neither the main bucket twice nor buckets that have no window`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":30}},"codex_spark":{"limitId":"codex_spark","limitName":"Codex Spark"},"codex_other":{"limitId":"codex_other","limitName":"Other","primary":{"usedPercent":5}}}}}"#)

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quotas.map(\.quotaType) == [.session, .timeLimit("Other")])
        #expect(usage.quotas[1].percentRemaining == 95)
    }

    @Test
    func `should show the terminal's windows, answered by Terminal, when RPC fails`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"error":{"message":"rate limits are unavailable"}}"#)
        stub.answerTerminal("""
        Account: someone@example.com
        5h limit:  [██████░░░░] 80% left (resets 14:00)
        Weekly limit: [███░░░░░░] 35% left
        """)
        let codex = try stub.make("codex")

        let usage = try await codex.refreshPlain()

        #expect(usage.quota(for: .session)?.percentRemaining == 80)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 35)
        #expect(codex.defaultAccount.answeredBy == "tty")
        #expect(codex.defaultAccount.answeredByLabel == "Terminal")
    }

    @Test
    func `should report the RPC failure and keep the last usage when RPC and the terminal both fail`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        // First refresh: initialize, usage, the account. Second: initialize, then an RPC error.
        let answers = [
            #"{"id":1,"result":{}}"#,
            #"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":30}}}}"#,
            #"{"id":3,"result":{"account":null}}"#,
            #"{"id":1,"result":{}}"#,
            #"{"id":2,"error":{"message":"rate limits are unavailable"}}"#,
        ]
        let received = Counter()
        given(stub.transport).send(.any).willReturn(())
        given(stub.transport).close().willReturn(())
        given(stub.transport).receive().willProduce { @Sendable in Data(answers[received.next() - 1].utf8) }
        given(stub.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willThrow(UsageError.executionFailed("TTY not available"))
        let codex = try stub.make("codex")
        let first = try await codex.refreshPlain()

        await #expect(throws: UsageError.self) { try await codex.refreshPlain() }

        #expect(codex.defaultAccount.lastError as? UsageError == .executionFailed("RPC error: rate limits are unavailable"))
        #expect(codex.defaultAccount.lastFailedStep == .fetch)
        #expect(codex.defaultAccount.snapshot == first)
    }

    // MARK: - Terminal

    @Test
    func `should ask to sign in when the terminal says Codex is not logged in`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "tty", providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerTerminal("Error: Not logged in. Please log in with `codex login`.")
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.authenticationRequired) { try await codex.refreshPlain() }
        #expect(codex.defaultAccount.lastFailedStep == .mapping)
    }

    // MARK: - API

    @Test
    func `should show the usage the API's headers report over its body`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"reset_after_seconds":3600}}}"#,
                        headers: ["x-codex-primary-used-percent": "25.5", "x-codex-secondary-used-percent": "40"])

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quota(for: .session)?.percentRemaining == 74.5)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 60)
        #expect(usage.quota(for: .session)?.resetsAt != nil)
    }

    @Test
    func `should show the usage in the API's body when it sends no usage headers`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":15.0,"reset_at":1735000000},"secondary_window":{"used_percent":45.0}}}"#)

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quota(for: .session)?.percentRemaining == 85)
        #expect(usage.quota(for: .session)?.resetsAt == Date(timeIntervalSince1970: 1735000000))
        #expect(usage.quota(for: .weekly)?.percentRemaining == 55)
    }

    @Test
    func `should show Spark's windows after the session and weekly ones when read through the API`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":10},"secondary_window":{"used_percent":20}},"additional_rate_limits":[{"limit_name":"codex_spark","rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":18000},"secondary_window":{"used_percent":40}}}]}"#)

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quotas.map(\.quotaType) == [.session, .weekly, .timeLimit("Spark"), .timeLimit("Spark 7d")])
        #expect(usage.quotas[2].percentRemaining == 70)
        #expect(usage.quotas[2].windowDuration == 18000)
        #expect(usage.quotas[3].percentRemaining == 60)
    }

    @Test
    func `should show the plan and the credits spent from the balance`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10}},"credits":{"has_credits":true,"balance":"900"}}"#,
                        headers: ["x-codex-credits-balance": "750"])

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.accountTier == .custom("PLUS"))
        #expect(usage.costUsage?.totalCost == 250)
        #expect(usage.costUsage?.budget == 1000)
    }

    // https://github.com/tddworks/ClaudeBar/issues/444
    @Test
    func `should show no cost when the account has no credits (#444)`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":604800}},"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}"#)

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.costUsage == nil)
    }

    @Test
    func `should show no quotas, not a failure, when the API reports nothing`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP("{}")

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quotas.isEmpty)
    }

    @Test
    func `should be unavailable and ask to sign in when there is no Codex login for the API`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.make("codex")

        #expect(await codex.isPlainAvailable() == false)
        await #expect(throws: UsageError.authenticationRequired) { try await codex.refreshPlain() }
        #expect(codex.defaultAccount.lastFailedStep == .lookup)
    }

    @Test
    func `should ask to sign in again when the API refuses the login`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth()
        stub.answerHTTP("", status: 401)
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.sessionExpired()) { try await codex.refreshPlain() }
    }

    @Test
    func `should renew an old login and save the new tokens back to Codex's file`() async throws {
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

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.quota(for: .session)?.percentRemaining == 90)
        let tokens = try stub.readCodexAuth()["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "new-token")
        #expect(tokens?["refresh_token"] as? String == "new-refresh-token")
        #expect(tokens?["account_id"] as? String == "acct-1")
    }

    @Test
    func `should ask to sign in again when the saved login can no longer be renewed`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(lastRefresh: Date().addingTimeInterval(-9 * 86400))
        stub.answerHTTP(#"{"error":{"code":"refresh_token_expired"}}"#, status: 400)
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.sessionExpired()) { try await codex.refreshPlain() }
        #expect(codex.defaultAccount.lastFailedStep == .lookup)
    }
}
