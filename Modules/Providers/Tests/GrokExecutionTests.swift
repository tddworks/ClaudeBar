import Testing
import Foundation
import Mockable
import Providers
import DataSources
import Quotas

/// Grok's login file, refresh and accounts through the definition.
@MainActor @Suite("Grok definition execution")
struct GrokExecutionTests {

    private func make(home:URL,network:any NetworkClient = MockNetworkClient()) throws -> Account {
        let provider=Provider(definition:try Providers.builtIn("grok"),settings:InMemoryProviderSettings(),makeDataSource:{source,_ in
            DataSources.make(source,providerId:"grok",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,environment:{_ in nil},homeDirectory:home,now:{Date()})
        })
        return provider.defaultAccount
    }
    private func saved(_ key:String,in home:URL) throws -> String? {
        let data=try Data(contentsOf:home.appendingPathComponent(".grok/auth.json"))
        let json=try JSONSerialization.jsonObject(with:data) as? [String:[String:Any]]
        return json?["https://auth.x.ai::client-123"]?[key] as? String
    }


    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(
        at directory: URL,
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        expiresAt: String = "2099-01-01T00:00:00.000000Z"
    ) throws {
        let grokDir = directory.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokDir, withIntermediateDirectories: true)

        var entry: [String: Any] = [
            "key": accessToken,
            "auth_mode": "oidc",
            "email": "user@example.com",
            "expires_at": expiresAt,
            "oidc_issuer": "https://auth.x.ai",
            "oidc_client_id": "client-123"
        ]
        if let refreshToken {
            entry["refresh_token"] = refreshToken
        }

        let auth: [String: Any] = ["https://auth.x.ai::client-123": entry]
        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        try data.write(to: grokDir.appendingPathComponent("auth.json"))
    }

    private nonisolated static let billingJSON = """
    {
      "config": {
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-07-23T05:09:24.881042+00:00",
          "end": "2026-07-30T05:09:24.881042+00:00"
        },
        "creditUsagePercent": 96.0,
        "productUsage": [
          {"product": "GrokBuild", "usagePercent": 84.0}
        ]
      }
    }
    """.data(using: .utf8)!

    private nonisolated func httpResponse(_ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when credentials exist`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let probe = try make(home:tempDir)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when credentials missing`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let probe = try make(home:tempDir)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Tests

    @Test
    func `probe throws authenticationRequired when no credentials`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let probe = try make(home:tempDir)

        await #expect(throws: UsageError.authenticationRequired) {
            try await probe.refresh()
        }
    }

    @Test
    func `probe returns snapshot with account email on success`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn((Self.billingJSON, httpResponse(200)))

        let probe = try make(home:tempDir,network:mockNetwork)

        let snapshot = try await probe.refresh()

        #expect(snapshot.providerId == "grok")
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 4.0)
        #expect(snapshot.quota(for: .modelSpecific("Build"))?.percentRemaining == 16.0)
    }

    @Test(arguments: [401,403])
    func `probe refreshes rejected tokens and retries`(_ rejectedStatus: Int) async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, accessToken: "stale-token")

        let mockNetwork = MockNetworkClient()
        let refreshResponse = """
        {"access_token": "fresh-token", "refresh_token": "fresh-refresh-token", "expires_in": 3600}
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willProduce { @Sendable request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth2/token") {
                return (refreshResponse, self.httpResponse(200))
            }
            let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if token.contains("fresh-token") {
                return (Self.billingJSON, self.httpResponse(200))
            }
            return (Data(), self.httpResponse(rejectedStatus))
        }

        let probe = try make(home:tempDir,network:mockNetwork)

        let snapshot = try await probe.refresh()

        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 4.0)
        // The refreshed token was written back for the next probe
        #expect(try saved("key",in:tempDir) == "fresh-token")
        #expect(try saved("refresh_token",in:tempDir) == "fresh-refresh-token")
    }

    @Test
    func `probe proactively refreshes expired token`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, accessToken: "expired-token", expiresAt: "2020-01-01T00:00:00.000000Z")

        let mockNetwork = MockNetworkClient()
        let refreshResponse = """
        {"access_token": "fresh-token", "expires_in": 3600}
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willProduce { @Sendable request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth2/token") {
                return (refreshResponse, self.httpResponse(200))
            }
            return (Self.billingJSON, self.httpResponse(200))
        }

        let probe = try make(home:tempDir,network:mockNetwork)

        let snapshot = try await probe.refresh()

        #expect(snapshot.quotas.count == 2)
        #expect(try saved("key",in:tempDir) == "fresh-token")
    }

    @Test
    func `probe throws sessionExpired when refresh is rejected`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Expired token forces a refresh; the refresh endpoint rejects it
        try createAuthFile(at: tempDir, expiresAt: "2020-01-01T00:00:00.000000Z")

        let mockNetwork = MockNetworkClient()
        let errorResponse = """
        {"error": "invalid_grant"}
        """.data(using: .utf8)!
        given(mockNetwork).request(.any).willReturn((errorResponse, httpResponse(400)))

        let probe = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.sessionExpired(hint: "Run `grok login` in terminal to log in again.")) {
            try await probe.refresh()
        }
    }

    @Test
    func `probe throws sessionExpired when token stays rejected after refresh`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let refreshResponse = """
        {"access_token": "fresh-token", "expires_in": 3600}
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willProduce { @Sendable request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth2/token") {
                return (refreshResponse, self.httpResponse(200))
            }
            return (Data(), self.httpResponse(401))
        }

        let probe = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.sessionExpired(hint: "Run `grok login` in terminal to log in again.")) {
            try await probe.refresh()
        }
    }

    @Test
    func `probe throws executionFailed on network error`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willThrow(URLError(.notConnectedToInternet))

        let probe = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.self) {
            try await probe.refresh()
        }
    }

    @Test
    func `probe throws executionFailed on HTTP 500`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn((Data(), httpResponse(500)))

        let probe = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.executionFailed("HTTP error: 500")) {
            try await probe.refresh()
        }
    }
    @Test func `independent auth folders never borrow the default login and keep their names`() async throws {
        let personal = try makeTemporaryDirectory(), work = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at:personal); try? FileManager.default.removeItem(at:work) }
        try createAuthFile(at:personal,accessToken:"personal-token")
        try createAuthFile(at:work,accessToken:"work-token")
        let network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            let token=request.value(forHTTPHeaderField:"Authorization")
            #expect(token == "Bearer personal-token" || token == "Bearer work-token")
            let used=token == "Bearer personal-token" ? 10 : 60
            return (Data("{\"creditUsagePercent\":\(used)}".utf8),self.httpResponse(200))
        }
        let definition=try Providers.builtIn("grok"), settings=InMemoryProviderSettings()
        let factory: @MainActor () -> Provider = {
            Provider(definition:definition,settings:settings,accounts:settings.accounts(forProvider:"grok"),makeDataSource:{source,_ in
                DataSources.make(source,providerId:"grok",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,environment:{_ in nil},homeDirectory:personal,now:{Date()})
            })
        }
        let provider=factory()
        #expect(provider.defaultAccount.displayName == "Grok")
        #expect(throws:UsageError.self) { try provider.addAccount(filling:["directory":"relative/path"]) }
        let account=try provider.addAccount(filling:["directory":work.appendingPathComponent(".grok").path])
        provider.rename(account,to:"Work")
        #expect((try await provider.defaultAccount.refresh()).quotas[0].percentRemaining == 90)
        #expect((try await account.refresh()).quotas[0].percentRemaining == 40)
        let restored=factory(), restoredWork=try #require(restored.accounts.first {$0.id == account.id})
        #expect(restoredWork.displayName == "Work")
        #expect((try await restoredWork.refresh()).quotas[0].percentRemaining == 40)
        try FileManager.default.removeItem(at:work.appendingPathComponent(".grok/auth.json"))
        await #expect(throws:UsageError.authenticationRequired) { try await restoredWork.refresh() }
        #expect((try await restored.defaultAccount.refresh()).quotas[0].percentRemaining == 90)
        restored.remove(restoredWork)
        #expect(FileManager.default.fileExists(atPath:work.path))
        #expect(settings.accounts(forProvider:"grok").isEmpty)
    }

    @Test func `refresh uses the selected record issuer and optional client and retains an omitted refresh token`() async throws {
        let root=try makeTemporaryDirectory()
        defer {try? FileManager.default.removeItem(at:root)}
        try createAuthFile(at:root,accessToken:"old",refreshToken:"refresh&a+b",expiresAt:"2020-01-01T00:00:00Z")
        let file=root.appendingPathComponent(".grok/auth.json")
        var document=try #require(try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:[String:Any]])
        document["https://auth.x.ai::client-123"]?["oidc_issuer"]="https://tenant.test/base/"
        document["https://auth.x.ai::client-123"]?["oidc_client_id"]=nil
        try JSONSerialization.data(withJSONObject:document).write(to:file)
        let network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            if request.httpMethod == "POST" {
                #expect(request.url?.absoluteString == "https://tenant.test/base/oauth2/token")
                #expect(request.value(forHTTPHeaderField:"Content-Type") == "application/x-www-form-urlencoded")
                let body=String(decoding:request.httpBody ?? Data(),as:UTF8.self)
                #expect(body.contains("refresh_token=refresh%26a%2Bb"))
                #expect(!body.contains("client_id="))
                return (Data(#"{"access_token":"fresh","refresh_token":"","expires_in":3600}"#.utf8),self.httpResponse(200))
            }
            #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer fresh")
            return (Self.billingJSON,self.httpResponse(200))
        }
        _ = try await make(home:root,network:network).refresh()
        #expect(try saved("key",in:root) == "fresh")
        #expect(try saved("refresh_token",in:root) == "refresh&a+b")
    }
    @Test func `an API login without a refresh token needs its key again when rejected`() async throws {
        let root=try makeTemporaryDirectory()
        defer {try? FileManager.default.removeItem(at:root)}
        try createAuthFile(at:root,refreshToken:nil)
        let network=MockNetworkClient()
        given(network).request(.any).willReturn((Data(),httpResponse(401)))
        let account=try make(home:root,network:network)
        // Nothing to refresh with, as for any API-key login: Key needed.
        await #expect(throws:UsageError.authenticationRequired) {try await account.refresh()}
    }

}
