import Foundation
import Testing
import DataSources
import Quotas
import Mockable
@testable import Providers

/// A setting's kind owns its rule; a choice's options carry their values.
@Suite
struct SettingTests {
    private func decode(_ json: String) throws -> Setting {
        try JSONDecoder().decode(Setting.self, from: Data(json.utf8))
    }

    private let region = """
    {"id":"region","label":"Region","scope":"account","default":"china",
     "kind":{"choice":[{"id":"china","label":"China","site":"acme.cn"},{"id":"international","label":"International","site":"acme.com"}]}}
    """

    @Test
    func `should fill in the chosen option and every value it carries`() throws {
        let setting = try decode(region)
        #expect(setting.fills(for: "international") == ["region": "international", "region.site": "acme.com"])
    }

    @Test
    func `should own its value and every value its options fill in, and nothing of a setting with a longer name`() throws {
        let setting = try decode(region)

        #expect(setting.isNamed(by: "region"))
        #expect(setting.isNamed(by: "region.site"))
        #expect(!setting.isNamed(by: "regionId"))
        #expect(!setting.isNamed(by: "plan"))
    }

    @Test
    func `should use the default for a blank, or the first option when a choice has no default`() throws {
        #expect(try decode(region).value(from: "  ") == "china")
        let noDefault = try decode(#"{"id":"plan","label":"Plan","kind":{"choice":["pro","max"]}}"#)
        #expect(noDefault.value(from: nil) == "pro")
        #expect(noDefault.value(from: " max ") == "max")
    }

    @Test
    func `should never fill a key into a request except by looking it up`() throws {
        let key = try decode(#"{"id":"apiKey","label":"API key","kind":"secret"}"#)
        #expect(key.fills(for: "sk-1").isEmpty)
    }

    @Test
    func `should refuse a key that comes with a default`() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"id":"apiKey","label":"API key","kind":"secret","default":"sk-0"}"#)
        }
    }

    @Test
    func `should still read settings written in the older form`() throws {
        #expect(try decode(#"{"id":"apiKey","label":"API key","secret":true}"#).kind == .secret)
        #expect(try decode(#"{"id":"region","label":"Region","choices":["a","b"]}"#).kind
            == .choice([Setting.Option(id: "a"), Setting.Option(id: "b")]))
    }

    @Test
    func `should say what is wrong with a choice, text or folder the person entered`() throws {
        let paths = FakePaths(folders: ["/Users/me/.acme-work"])
        #expect(try decode(region).check("mars", paths: paths) == "Choose a Region from the list.")
        #expect(try decode(region).check("china", paths: paths) == nil)
        let profile = try decode(#"{"id":"profile","label":"Profile","kind":{"text":{"pattern":"^[a-z]+$"}}}"#)
        #expect(profile.check("Work 1", paths: paths) == "Enter a valid Profile.")
        let folder = try decode(#"{"id":"home","label":"CLI data folder","kind":{"path":{"mustExist":true}}}"#)
        #expect(folder.check("relative/dir", paths: paths) == "Enter a full path for CLI data folder.")
        #expect(folder.check("/Users/me/missing", paths: paths) == "Choose an existing folder for CLI data folder.")
        #expect(folder.check("/Users/me/.acme-work", paths: paths) == nil)
        #expect(folder.check("", paths: paths) == "Fill in CLI data folder.")
    }

    @Test func `should expand path defaults before checking their location and existence`() throws {
        let folder = try decode(#"{"id":"home","label":"Folder","kind":{"path":{"mustExist":true}}}"#)
        let paths = FakePaths(folders: ["/Users/me/work"], aliases: [
            "${ACME_HOME:-~/work}": "/Users/me/work", "${MISSING}": "/Users/me/missing",
            "${RELATIVE}": "relative/work"
        ])
        #expect(folder.check("${ACME_HOME:-~/work}", paths: paths) == nil)
        #expect(folder.check("${MISSING}", paths: paths) == "Choose an existing folder for Folder.")
        #expect(folder.check("${RELATIVE}", paths: paths) == "Enter a full path for Folder.")
        #expect(folder.check("${UNSET}", paths: paths) == "Enter a full path for Folder.")
    }

    @Test
    func `should find a login's folder among its values, and no folder for a choice`() throws {
        let folder = try decode(#"{"id":"home","label":"Folder","scope":"account","kind":"path"}"#)
        #expect(folder.path(in: ["home": "/Users/me/work"]) == "/Users/me/work")
        #expect(try decode(region).path(in: ["region": "china"]) == nil)
    }

    @Test
    func `should treat two spellings of one folder as the same place, but never two equal choices`() throws {
        let paths = FakePaths(folders: [], aliases: ["~/.acme": "/Users/me/.acme"])
        let folder = try decode(#"{"id":"home","label":"Folder","kind":"path"}"#)
        #expect(folder.isSamePlace("~/.acme", as: "/Users/me/.acme", paths: paths))
        #expect(try decode(region).isSamePlace("china", as: "china", paths: paths) == false)
    }

    @Test
    func `should keep a setting as written when it is saved and read back`() throws {
        let setting = try decode(region)
        #expect(try JSONDecoder().decode(Setting.self, from: JSONEncoder().encode(setting)) == setting)
    }
}

/// The file system as a test needs it: these folders exist, and these
/// spellings are the same place.
struct FakePaths: PathChecking {
    var folders: Set<String>
    var aliases: [String: String] = [:]

    func expanded(_ path: String) -> String { aliases[path] ?? path }
    func isFolder(_ path: String) -> Bool { folders.contains(canonical(path)) }
    func canonical(_ path: String) -> String { aliases[path] ?? path }
}

@MainActor @Suite struct DefaultPathIsolationTests {
    struct Paths: PathChecking {
        func isFolder(_ path: String) -> Bool { true }
        func canonical(_ path: String) -> String { expanded(path) }
        func expanded(_ path: String) -> String {
            DataSources.expandPath(path, homeDirectory: URL(fileURLWithPath: "/Users/me"), environment: { _ in nil })
        }
    }
    private func provider(_ id: String, accounts: [ProviderAccountConfig] = []) throws -> Provider {
        Provider(definition: try ProviderFactory.builtIn(id), settings: InMemoryProviderSettings(), accounts: accounts,
            makeDataSource: { source, login in
                DataSources.make(source, providerId: login, cliExecutor: MockCLIExecutor(), network: MockNetworkClient(),
                    makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { _ in nil },
                    homeDirectory: URL(fileURLWithPath: "/Users/me"), now: { Date() })
            }, paths: Paths())
    }
    @Test(arguments: [("gemini", "home", "~"), ("kiro", "home", "~"), ("grok", "directory", "~/.grok"), ("kimi", "home", "~/.kimi")])
    func `should reject an added login that reuses the default folder`(_ entry: (String, String, String)) throws {
        let account = try provider(entry.0)
        #expect(throws: UsageError.self) { try account.accounts.add(filling: [entry.1: entry.2]) }
        #expect(account.accounts.count == 1)
    }
    @Test func `should restore a saved tilde path as an absolute folder`() throws {
        let owner = try provider("kiro", accounts: [ProviderAccountConfig(
            accountId: "work", label: "Work", probeConfig: ["home": "~/work"], madeBy: .form)])
        let account = try #require(owner.accounts.first { $0.accountId == "work" })
        #expect(account.values["home"] == "/Users/me/work")
    }
    @Test func `should restore a signed-in folder as the absolute path its CLI needs`() throws {
        let owner = try provider("codex", accounts: [ProviderAccountConfig(
            accountId: "work", label: "Work", probeConfig: ["folder": "~/work", "accountId": "work-id"], madeBy: .folder)])
        let account = try #require(owner.accounts.first { $0.accountId == "work" })
        #expect(account.values["folder"] == "/Users/me/work")
        let rpc = try #require(owner.dataSources(for: account).first { $0.kind == "rpc" })
        guard case .jsonRpc(let call) = rpc.definition.fetch else {
            Issue.record("Expected an RPC fetch")
            return
        }
        #expect(call.environment.set["CODEX_HOME"] == "/Users/me/work")
    }
    @Test func `should validate a blank path default after expansion`() throws {
        let owner = try provider("kimi")
        try owner.configuration.set("home", to: "/Users/me/other")
        let added = try owner.accounts.add(filling: [:])
        #expect(added.values["home"] == "/Users/me/.kimi")
    }
    @Test func `should reject a blank default that duplicates another login folder`() throws {
        let owner = try provider("kimi")
        #expect(throws: UsageError.executionFailed("Choose a separate folder for Signed-in Kimi Folder — another Kimi login uses this one.")) {
            try owner.accounts.add(filling: [:])
        }
    }
    @Test func `should save a tilde path as the absolute folder the CLI needs`() throws {
        let owner = try provider("kiro")
        let account = try owner.accounts.add(filling: ["home": "~/work"])
        #expect(account.values["home"] == "/Users/me/work")
    }
}
