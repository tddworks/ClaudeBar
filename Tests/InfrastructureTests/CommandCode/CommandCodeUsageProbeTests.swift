import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("CommandCodeUsageProbe Tests")
struct CommandCodeUsageProbeTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("commandcode-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(at directory: URL, apiKey: String = "user_test") throws {
        let commandCodeDir = directory.appendingPathComponent(".commandcode", isDirectory: true)
        try FileManager.default.createDirectory(at: commandCodeDir, withIntermediateDirectories: true)
        try Data(#"{ "apiKey": "\#(apiKey)" }"#.utf8)
            .write(to: commandCodeDir.appendingPathComponent("auth.json"))
    }

    private func loader(home: URL) -> CommandCodeCredentialLoader {
        CommandCodeCredentialLoader(homeDirectory: home.path, environment: [:])
    }

    private static let whoamiJSON = """
    {
      "user": { "id": 7, "userName": "alice", "name": "Alice Anderson" },
      "org": { "id": 42 }
    }
    """.data(using: .utf8)!

    private static let creditsJSON = CommandCodeUsageProbeParsingTests.sampleResponse.data(using: .utf8)!

    private func httpResponse(_ statusCode: Int, path: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.commandcode.ai\(path)")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    /// Routes whoami and credits by URL path.
    private func mockNetwork(
        whoami: (Data, Int) = (whoamiJSON, 200),
        credits: (Data, Int) = (creditsJSON, 200)
    ) -> (MockNetworkClient, CapturedRequests) {
        let network = MockNetworkClient()
        let captured = CapturedRequests()
        given(network).request(.any).willProduce { request in
            captured.append(request)
            let path = request.url?.path ?? ""
            let route = path.contains("whoami") ? whoami : credits
            return (route.0, self.httpResponse(route.1, path: path))
        }
        return (network, captured)
    }

    final class CapturedRequests: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URLRequest] = []

        func append(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(request)
        }

        var all: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when an api key exists`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir))

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when no api key exists`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir))

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Tests

    @Test
    func `probe throws authenticationRequired when no api key`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let probe = CommandCodeUsageProbe(
            credentialLoader: loader(home: tempDir),
            networkClient: MockNetworkClient()
        )

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe returns snapshot with quotas and account label`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let (network, _) = mockNetwork()

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "commandcode")
        #expect(snapshot.accountEmail == "alice")
        #expect(snapshot.quota(for: .session)?.percentRemaining == 75)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 75)
        #expect(snapshot.quota(for: .timeLimit("Credits"))?.dollarRemaining == 8.5)
    }

    @Test
    func `probe sends the bearer key and the org id query`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, apiKey: "user_secret")
        let (network, captured) = mockNetwork()

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)
        _ = try await probe.probe()

        let requests = captured.all
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer user_secret" })
        #expect(requests.first?.url?.path == "/alpha/whoami")

        let creditsURL = try #require(requests.last?.url)
        #expect(creditsURL.path == "/alpha/billing/credits")
        #expect(creditsURL.query?.contains("orgId=42") == true)
    }

    @Test
    func `probe omits org id when whoami has none`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let whoami = #"{ "user": { "userName": "alice" } }"#.data(using: .utf8)!
        let (network, captured) = mockNetwork(whoami: (whoami, 200))

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)
        let snapshot = try await probe.probe()

        #expect(snapshot.accountEmail == "alice")
        #expect(captured.all.last?.url?.query == nil)
    }

    @Test
    func `probe falls back to the user name when userName is absent`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let whoami = #"{ "user": { "name": "Alice Anderson" } }"#.data(using: .utf8)!
        let (network, _) = mockNetwork(whoami: (whoami, 200))

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)

        #expect(try await probe.probe().accountEmail == "Alice Anderson")
    }

    @Test
    func `probe throws sessionExpired when whoami rejects the key`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let (network, captured) = mockNetwork(whoami: (Data(), 401))

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)

        await #expect(throws: ProbeError.sessionExpired(hint: "Run `cmd login` or set COMMAND_CODE_API_KEY.")) {
            try await probe.probe()
        }
        // A rejected whoami must not continue to the credits call
        #expect(captured.all.count == 1)
    }

    @Test
    func `probe throws sessionExpired when credits rejects the key`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let (network, _) = mockNetwork(credits: (Data(), 403))

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)

        await #expect(throws: ProbeError.sessionExpired(hint: "Run `cmd login` or set COMMAND_CODE_API_KEY.")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on HTTP 500`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let (network, _) = mockNetwork(credits: (Data(), 500))

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)

        await #expect(throws: ProbeError.executionFailed("HTTP error: 500")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on network error`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let network = MockNetworkClient()
        given(network).request(.any).willThrow(URLError(.notConnectedToInternet))

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws parseFailed when a 200 body is not a JSON object`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)
        let (network, _) = mockNetwork(credits: (Data("not json".utf8), 200))

        let probe = CommandCodeUsageProbe(credentialLoader: loader(home: tempDir), networkClient: network)

        await #expect(throws: ProbeError.parseFailed("Failed to parse Command Code response as JSON")) {
            try await probe.probe()
        }
    }
}
