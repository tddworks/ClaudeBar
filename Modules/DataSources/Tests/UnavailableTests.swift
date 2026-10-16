import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Mockable
import Quotas
import Testing
@testable import DataSources

/// A case whose connection the platform has none of fails at its own step,
/// naming the case and the platform (MODULAR_DESIGN §10), never as no key, no
/// usage or a program that isn't installed. These go through the real factory
/// with `Platform.bare`, so every platform checks what Windows does today.
@Suite
struct UnavailableTests {
    private let network = MockNetworkClient()

    private func source(_ fetch: Fetch = .http(HTTPRequest(url: "https://acme.test")),
                        mapping: Mapping = .usage(UsageMapping()), credential: CredentialLookup? = nil,
                        platform: Platform = .bare) -> DataSource {
        DataSources.make(DataSourceDefinition(kind: "acme", credential: credential, fetch: fetch, mapping: mapping),
                         providerId: "acme", platform: platform, network: network, environment: { _ in nil },
                         homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
    }

    private static func unavailable(_ step: DataSourceError.Step, _ what: String) -> DataSourceError {
        DataSourceError(step, .executionFailed("\(what) isn't available on \(Platform.bare.name) yet."))
    }

    @Test(arguments: [
        (CredentialLookup.keychain(KeychainCredential(service: "acme", fields: ["token": "$"])), "Reading a Keychain item"),
        (.browserCookies(BrowserCookieCredential(domains: ["acme.test"], names: ["session"])), "Reading a browser's cookies"),
        (.browserStorage(BrowserStorageCredential(origin: "https://acme.test", values: [:])), "Reading a browser's storage"),
    ])
    func `should fail at finding the key, naming the lookup, and never ask the server`(_ lookup: CredentialLookup, _ what: String) async {
        let source = source(credential: lookup)

        await #expect(throws: Self.unavailable(.lookup, what)) {
            try await source.fetchUsage()
        }
        verify(network).request(.any).called(0)
    }

    @Test(arguments: [
        (Fetch.cli(CLICall(cli: "acme", args: ["usage"])), "Running acme"),
        (.command(CommandCall(cli: "acme", args: ["usage"])), "Running acme"),
        (.jsonRpc(JSONRPCCall(cli: "acme", args: ["app-server"], call: "account/rateLimits/read")), "Running acme"),
        (.script(ScriptCall(run: "usage.sh", folder: "~/acme")), "Running a script"),
        (.localServer(LocalServerCall(app: "Acme", process: .init(names: ["acme-server"]), paths: ["/usage"])),
         "Reading a local server"),
    ])
    func `should count as set up and fail at fetching, naming what it would run or read`(_ fetch: Fetch, _ what: String) async {
        let source = source(fetch)

        #expect(await source.isReady())
        await #expect(throws: Self.unavailable(.fetch, what)) {
            try await source.fetchUsage()
        }
    }

    @Test
    func `should fail at fetching when the platform runs the CLI but can't draw its screen`() async {
        var platform = Platform.bare
        platform.runCLI = { _ in MockCLIExecutor() }
        let source = source(.cli(CLICall(cli: "acme", screen: .rendered)), platform: platform)

        await #expect(throws: Self.unavailable(.fetch, "Rendering acme's screen")) {
            try await source.fetchUsage()
        }
    }
}
