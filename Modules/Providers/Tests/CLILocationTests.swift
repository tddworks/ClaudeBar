import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// *CLI location* — where a provider's CLI lives on this Mac, when it isn't
/// the one ClaudeBar finds on its own (#210). One fact per provider: every
/// login, every CLI data source and Add Account's sign-in run it.
@MainActor
@Suite
struct CLILocationTests {
    private static let path = "/opt/tools/bin/codex-work"

    private func cli(of source: DataSource) -> String? {
        switch source.definition.fetch {
        case .cli(let call): call.cli
        case .jsonRpc(let call): call.cli
        default: nil
        }
    }

    private func login(_ id: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: "", email: "\(id)@example.com",
                              probeConfig: ["codexHome": "/tmp/\(id)", "chatgptAccountId": id])
    }

    @Test
    func `every login's cli data sources run the chosen location`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", accounts: [login("work")], isExecutable: { _ in true })

        try codex.setCLIPath(Self.path)

        for account in codex.accounts {
            let clis = codex.dataSources(for: account).compactMap(cli)
            #expect(!clis.isEmpty)
            #expect(clis.allSatisfy { $0 == Self.path })
        }
        #expect(codex.cliPath == Self.path)
        #expect(stub.settings.cliPath(forProvider: "codex") == Self.path)
    }

    @Test
    func `clearing the location goes back to finding the cli as usual`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", isExecutable: { _ in true })
        try codex.setCLIPath(Self.path)

        try codex.setCLIPath("  ")

        #expect(codex.cliPath == nil)
        #expect(codex.dataSources(for: codex.defaultAccount).compactMap(cli).allSatisfy { $0 == "codex" })
        #expect(stub.settings.cliPath(forProvider: "codex") == nil)
    }

    @Test
    func `a location that isn't a program is refused, and nothing changes`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", isExecutable: { _ in false })

        #expect(throws: UsageError.self) { try codex.setCLIPath("/Users/me/notes.txt") }

        #expect(codex.cliPath == nil)
        #expect(codex.dataSources(for: codex.defaultAccount).compactMap(cli).allSatisfy { $0 == "codex" })
    }

    @Test
    func `a saved location is used after a relaunch`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        try stub.makeProvider("codex", isExecutable: { _ in true }).setCLIPath(Self.path)

        let relaunched = try stub.makeProvider("codex")

        #expect(relaunched.dataSources(for: relaunched.defaultAccount).compactMap(cli).allSatisfy { $0 == Self.path })
    }

    @Test
    func `adding an account signs in with the chosen location`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex", isExecutable: { _ in true })
        try codex.setCLIPath(Self.path)
        let ran = Ran()
        let process = MockSignInProcess()
        given(process).run(executable: .any, arguments: .any, environment: .any, directory: .any, timeout: .any)
            .willProduce { @Sendable executable, _, _, _, _ in
                ran.executable = executable
                return 1
            }

        _ = try? await codex.signIn(with: AccountSignIn(process: process, folders: stub.folders, locate: { $0 }))

        #expect(ran.executable == Self.path)
    }
}

private final class Ran: @unchecked Sendable {
    var executable: String?
}
