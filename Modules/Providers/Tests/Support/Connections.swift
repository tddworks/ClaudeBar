import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// Builds a built-in `Provider` whose data sources run on stubbed connections,
/// so a definition is tested end to end — lookup, fetch, mapping, lifecycle —
/// without a network, a CLI or the person's home directory.
@MainActor
struct StubbedProvider {
    let network = MockNetworkClient()
    let cli = MockCLIExecutor()
    let transport = MockRPCTransport()
    /// Every CLI started for JSON-RPC: its arguments and environment.
    let launches = Launches()
    /// The login folders adding and removing accounts makes and deletes.
    let folders = InMemoryLoginFolders()
    /// Which login new terminal sessions start with — *In use*.
    let loginsInUse = InMemoryLoginsInUse()
    let home: URL
    let settings: InMemoryProviderSettings
    var environment: [String: String] = [:]

    init(dataSourceKind: String? = nil, providerId: String) throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("providers-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        settings = InMemoryProviderSettings(dataSourceKinds: dataSourceKind.map { [providerId: $0] } ?? [:])
    }

    /// The provider with its default login and every login in `accounts`,
    /// its data sources on the stubbed connections.
    func makeProvider(
        _ id: String,
        accounts: [ProviderAccountConfig] = [],
        isExecutable: @escaping @Sendable (String) -> Bool = { _ in true },
        locate: @escaping @Sendable (String) -> String? = { $0 }
    ) throws -> Provider {
        let transport = self.transport
        let launches = self.launches
        let environment = self.environment
        let cli = self.cli
        let network = self.network
        let home = self.home
        let definition = try ProviderFactory.builtIn(id)
        return Provider(
            definition: definition,
            settings: settings,
            accounts: accounts,
            makeDataSource: {
                DataSources.make(
                    $0,
                    providerId: definition.id,
                    cliExecutor: cli,
                    network: network,
                    makeTransport: { _, arguments, environment, _ in
                        launches.record(arguments, environment)
                        return transport
                    },
                    environment: { environment[$0] },
                    homeDirectory: home,
                    now: { Date() }
                )
            },
            folders: folders,
            loginsInUse: loginsInUse,
            isExecutable: isExecutable,
            locate: locate
        )
    }

    /// The provider, with its plain login.
    func make(_ id: String) throws -> Provider {
        try makeProvider(id)
    }

    /// The provider with one saved login added, and that login — ask the
    /// provider about it (a login never refers to its provider).
    func makeAdded(_ id: String, account: ProviderAccountConfig) throws -> (provider: Provider, login: Account) {
        let provider = try makeProvider(id, accounts: [account])
        return (provider, try #require(provider.accounts.first { $0.accountId == account.accountId }))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Stubbing helpers

    /// Answers each JSON-RPC request with its own id: `initialize` with
    /// nothing, `account/read` with `account`, anything else with `answer` —
    /// however many times the provider starts the CLI.
    nonisolated func answerRPC(_ answer: String, account: String = #"{"id":3,"result":{"account":null}}"#) {
        let lastRequest = LastRequest()
        given(transport).send(.any).willProduce { @Sendable data in
            lastRequest.set(data)
        }
        given(transport).close().willReturn(())
        given(transport).receive().willProduce { @Sendable in
            let (id, method) = lastRequest.get()
            let reply = switch method {
            case "initialize": #"{"id":1,"result":{}}"#
            case "account/read": account
            default: answer
            }
            var message = (try? JSONSerialization.jsonObject(with: Data(reply.utf8))) as? [String: Any] ?? [:]
            message["id"] = id
            return try! JSONSerialization.data(withJSONObject: message)
        }
    }

    nonisolated func answerHTTP(_ body: String, status: Int = 200, headers: [String: String] = [:]) {
        given(network).request(.any).willReturn((Data(body.utf8), Self.response(status, headers)))
    }

    nonisolated func answerTerminal(_ screen: String) {
        given(cli).locate(.any).willReturn("/usr/local/bin/codex")
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: screen))
    }

    nonisolated static func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    /// Writes `~/.codex/auth.json` in the stubbed home directory.
    func writeCodexAuth(token: String = "test-access-token", accountId: String? = nil, lastRefresh: Date = Date()) throws {
        let directory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var tokens: [String: Any] = ["access_token": token, "refresh_token": "test-refresh-token"]
        if let accountId { tokens["account_id"] = accountId }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let auth: [String: Any] = ["tokens": tokens, "last_refresh": formatter.string(from: lastRefresh)]
        try JSONSerialization.data(withJSONObject: auth).write(to: directory.appendingPathComponent("auth.json"))
    }

    func readCodexAuth() throws -> [String: Any] {
        let url = home.appendingPathComponent(".codex/auth.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }
}

/// Counts calls across a mock's closure.
final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// The CLIs a test's provider started, in order.
final class Launches: @unchecked Sendable {
    private var all: [(arguments: [String], environment: [String: String]?)] = []
    private let lock = NSLock()

    func record(_ arguments: [String], _ environment: [String: String]?) {
        lock.lock()
        defer { lock.unlock() }
        all.append((arguments, environment))
    }

    var last: (arguments: [String], environment: [String: String]?)? {
        lock.lock()
        defer { lock.unlock() }
        return all.last
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return all.count
    }
}

/// The last JSON-RPC request a fake transport was sent.
final class LastRequest: @unchecked Sendable {
    private var id = 0
    private var method = ""
    private let lock = NSLock()

    func set(_ data: Data) {
        let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        lock.lock()
        defer { lock.unlock() }
        if let id = message["id"] as? Int, let method = message["method"] as? String {
            self.id = id
            self.method = method
        }
    }

    func get() -> (id: Int, method: String) {
        lock.lock()
        defer { lock.unlock() }
        return (id, method)
    }
}
