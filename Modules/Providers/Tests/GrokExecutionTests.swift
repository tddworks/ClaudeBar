import Testing
import Foundation
import Mockable
import Providers
import DataSources
import Quotas
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Grok's login file, refresh and accounts through the definition.
@MainActor @Suite("Grok definition execution")
struct GrokExecutionTests {

    private func make(home:URL,network:any NetworkClient = MockNetworkClient()) throws -> Provider {
        let provider=Provider(definition:try ProviderFactory.builtIn("grok"),settings:InMemoryProviderSettings(),makeDataSource:{source,_ in
            DataSources.make(source,providerId:"grok",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,environment:{_ in nil},homeDirectory:home,now:{Date()})
        })
        return provider
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
    func `should be available when the Grok CLI has a login on this Mac`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let provider = try make(home:tempDir)

        #expect(await provider.isPlainAvailable() == true)
    }

    @Test
    func `should be unavailable when the Grok CLI has no login on this Mac`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let provider = try make(home:tempDir)

        #expect(await provider.isPlainAvailable() == false)
    }

    // MARK: - Probe Tests

    @Test
    func `should ask to sign in when the Grok CLI has no login`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let provider = try make(home:tempDir)

        await #expect(throws: UsageError.authenticationRequired) {
            try await provider.refreshPlain()
        }
    }

    @Test
    func `should show the login's email, weekly credits and Build when Grok answers`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn((Self.billingJSON, httpResponse(200)))

        let provider = try make(home:tempDir,network:mockNetwork)

        let snapshot = try await provider.refreshPlain()

        #expect(snapshot.providerId == "grok")
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 4.0)
        #expect(snapshot.quota(for: .modelSpecific("Build"))?.percentRemaining == 16.0)
    }

    @Test(arguments: [401,403])
    func `should renew a refused login, show the usage and save the new tokens back to Grok's file`(_ rejectedStatus: Int) async throws {
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

        let provider = try make(home:tempDir,network:mockNetwork)

        let snapshot = try await provider.refreshPlain()

        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 4.0)
        // The refreshed token was written back for the next provider
        #expect(try saved("key",in:tempDir) == "fresh-token")
        #expect(try saved("refresh_token",in:tempDir) == "fresh-refresh-token")
    }

    @Test
    func `should renew an expired login before asking and save it back`() async throws {
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

        let provider = try make(home:tempDir,network:mockNetwork)

        let snapshot = try await provider.refreshPlain()

        #expect(snapshot.quotas.count == 2)
        #expect(try saved("key",in:tempDir) == "fresh-token")
    }

    @Test
    func `should ask to run grok login again when the login can't be renewed`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Expired token forces a refresh; the refresh endpoint rejects it
        try createAuthFile(at: tempDir, expiresAt: "2020-01-01T00:00:00.000000Z")

        let mockNetwork = MockNetworkClient()
        let errorResponse = """
        {"error": "invalid_grant"}
        """.data(using: .utf8)!
        given(mockNetwork).request(.any).willReturn((errorResponse, httpResponse(400)))

        let provider = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.sessionExpired(hint: "Run `grok login` in terminal to log in again.")) {
            try await provider.refreshPlain()
        }
    }

    @Test
    func `should ask to run grok login again when the renewed login is still refused`() async throws {
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

        let provider = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.sessionExpired(hint: "Run `grok login` in terminal to log in again.")) {
            try await provider.refreshPlain()
        }
    }

    @Test
    func `should fail when the network is down`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willThrow(URLError(.notConnectedToInternet))

        let provider = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.self) {
            try await provider.refreshPlain()
        }
    }

    @Test
    func `should report the HTTP error when Grok answers 500`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn((Data(), httpResponse(500)))

        let provider = try make(home:tempDir,network:mockNetwork)

        await #expect(throws: UsageError.executionFailed("HTTP error: 500")) {
            try await provider.refreshPlain()
        }
    }
    @Test func `should read each added login from its own Grok folder, keep its name, and never fall back to the default login`() async throws {
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
        let definition=try ProviderFactory.builtIn("grok"), settings=InMemoryProviderSettings()
        let factory: @MainActor () -> Provider = {
            Provider(definition:definition,settings:settings,accounts:settings.accounts(forProvider:"grok"),makeDataSource:{source,_ in
                DataSources.make(source,providerId:"grok",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,environment:{_ in nil},homeDirectory:personal,now:{Date()})
            })
        }
        let provider=factory()
        #expect(provider.defaultAccount.displayName == "Grok")
        #expect(throws:UsageError.self) { try provider.accounts.add(filling:["directory":"relative/path"]) }
        let account=try provider.accounts.add(filling:["directory":work.appendingPathComponent(".grok").path])
        provider.accounts.rename(account,to:"Work")
        #expect((try await provider.refreshPlain()).quotas[0].percentRemaining == 90)
        #expect((try await provider.refresh(account)).quotas[0].percentRemaining == 40)
        let restored=factory(), restoredWork=try #require(restored.accounts.first {$0.id == account.id})
        #expect(restoredWork.displayName == "Work")
        #expect((try await restored.refresh(restoredWork)).quotas[0].percentRemaining == 40)
        try FileManager.default.removeItem(at:work.appendingPathComponent(".grok/auth.json"))
        await #expect(throws:UsageError.authenticationRequired) { try await restored.refresh(restoredWork) }
        #expect((try await restored.refreshPlain()).quotas[0].percentRemaining == 90)
        restored.accounts.remove(restoredWork)
        #expect(FileManager.default.fileExists(atPath:work.path))
        #expect(settings.accounts(forProvider:"grok").isEmpty)
    }

    @Test func `should renew a login with its own issuer, and keep its renewal token when none comes back`() async throws {
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
        _ = try await make(home:root,network:network).refreshPlain()
        #expect(try saved("key",in:root) == "fresh")
        #expect(try saved("refresh_token",in:root) == "refresh&a+b")
    }
    @Test func `should ask for the key again when a login with nothing to renew with is refused`() async throws {
        let root=try makeTemporaryDirectory()
        defer {try? FileManager.default.removeItem(at:root)}
        try createAuthFile(at:root,refreshToken:nil)
        let network=MockNetworkClient()
        given(network).request(.any).willReturn((Data(),httpResponse(401)))
        let provider=try make(home:root,network:network)
        // Nothing to refresh with, as for any API-key login: Key needed.
        await #expect(throws:UsageError.authenticationRequired) {try await provider.refreshPlain()}
    }

}
