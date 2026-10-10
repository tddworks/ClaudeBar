import Foundation
import Mockable
import Providers
@testable import DataSources
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Antigravity as data: the running app's own server, found through its
/// process, or — with the app closed — Google's quota with the login it saved
/// in the Keychain. The old probe's fixtures, quota for quota.
@MainActor @Suite
struct AntigravityDefinitionTests {
    nonisolated static let processLine = "26416 /Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm --csrf_token 9f808dbe-cb96-4829 --extension_server_port 58445 --app_data_dir antigravity"
    nonisolated static let lsof = "language 26416 me 10u IPv4 0x1 0t0 TCP 127.0.0.1:42135 (LISTEN)"
    nonisolated static let summary = #"{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"gemini-5h","remainingFraction":0.8,"resetTime":"2025-01-01T05:00:00Z"},{"bucketId":"gemini-weekly","remainingFraction":0.6,"resetTime":"2025-01-07T00:00:00Z"}]},{"displayName":"Claude & others","buckets":[{"bucketId":"3p-5h","remainingFraction":0.4},{"bucketId":"3p-weekly","remainingFraction":0.2},{"bucketId":"gemini-image-5h","remainingFraction":1.0}]}]}"#
    nonisolated static let userStatus = #"{"userStatus":{"email":"user@example.com","planStatus":{"planInfo":{"planName":"Pro"}},"cascadeModelConfigData":{"clientModelConfigs":[{"label":"Claude Sonnet","quotaInfo":{"remainingFraction":0.75,"resetTime":"2025-01-01T00:00:00Z"}},{"label":"Gemini Pro","quotaInfo":{"remainingFraction":0.5,"resetTime":"1735689600"}},{"label":"No Quota Model"}]}}}"#

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        func add(_ request: URLRequest) { lock.withLock { stored.append(request) } }
        var requests: [URLRequest] { lock.withLock { stored } }
    }

    /// The Keychain item `agy` keeps its login in; running `agy` renews it.
    final class Login: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        init(_ value: String?) { stored = value }
        var value: String? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    /// `answers`: path suffix → (status, body); anything else is a 404.
    /// `renewed`: the login `agy` saves when it runs — nil when `agy` isn't installed.
    private func make(running: Bool = true, answers: [String: (Int, String)] = [:], keychain: String? = nil,
                      renewed: String? = nil, seen: Seen = Seen()) throws -> Provider {
        let login = Login(keychain)
        let commands = MockCLIExecutor()
        given(commands).locate(.any).willProduce { @Sendable binary in
            binary == "agy" && renewed != nil ? "/Users/me/.local/bin/agy" : nil
        }
        given(commands).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable binary, _, _, _, _, _ in
                if binary == "agy" {
                    login.value = renewed
                    return CLIResult(output: "")
                }
                return CLIResult(output: binary.hasSuffix("pgrep") ? (running ? Self.processLine : "") : Self.lsof)
            }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.add(request)
            let path = request.url?.path ?? ""
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.stale" { return (Data(), StubbedProvider.response(401)) }
            guard let answer = answers.first(where: { path.hasSuffix($0.key) })?.value else { return (Data(), StubbedProvider.response(404)) }
            return (Data(answer.1.utf8), StubbedProvider.response(answer.0))
        }
        let definition = try ProviderFactory.builtIn("antigravity")
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, cliExecutor: commands, network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() },
                             security: { @Sendable arguments in
                                 guard let keychain = login.value, arguments.contains("gemini"), arguments.contains("antigravity") else { return (44, "") }
                                 return (0, "go-keyring-base64:" + Data(keychain.utf8).base64EncodedString())
                             },
                             scripts: ProviderFactory.builtInScripts, environment: { _ in nil },
                             homeDirectory: FileManager.default.temporaryDirectory,
                             processPaths: { running ? ["/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm"] : [] },
                             now: { Date() })
        })
    }

    @Test func `should keep Antigravity's name, on by default, with no dashboard and no account form`() throws {
        let provider = try make()
        #expect(provider.name == "Antigravity")
        #expect(provider.defaultAccount.isEnabled)
        #expect(provider.plainDashboardURL == nil)
        #expect(provider.accounts.form.isEmpty)
    }

    // MARK: - The running app

    @Test(.needsScriptEngine) func `should show the running app's shared pools with their stated windows`() async throws {
        let seen = Seen()
        let provider = try make(answers: ["RetrieveUserQuotaSummary": (200, #"{"response":\#(Self.summary)}"#)], seen: seen)
        let quotas = try await provider.refreshPlain().quotas
        #expect(quotas.map(\.quotaType) == [.session, .weekly, .modelSpecific("Claude"), .modelSpecific("Claude Weekly")])
        #expect(quotas.map(\.percentRemaining) == [80, 60, 40, 20])
        // A 5-hour bucket is 5 hours — the probe called the 3p one a week.
        #expect(quotas.map { $0.window?.length } == [18000, 604800, 18000, 604800])
        let request = try #require(seen.requests.first)
        #expect(request.url?.absoluteString == "https://127.0.0.1:42135/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
        #expect(request.value(forHTTPHeaderField: "X-Codeium-Csrf-Token") == "9f808dbe-cb96-4829")
    }

    @Test(.needsScriptEngine) func `should show a quota per model with the plan and email when an older app answers`() async throws {
        let snapshot = try await make(answers: ["GetUserStatus": (200, Self.userStatus)]).refreshPlain()
        #expect(snapshot.quotas.map(\.quotaType) == [.modelSpecific("Claude Sonnet"), .modelSpecific("Gemini Pro")])
        #expect(snapshot.quotas.map(\.percentRemaining) == [75, 50])
        #expect(snapshot.quotas[1].resetsAt == Date(timeIntervalSince1970: 1735689600))
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountTier == .custom("PRO"))
    }

    // MARK: - The app closed: Google, with its saved login

    @Test(.needsScriptEngine) func `should show Google's quota with the saved login when the app is closed`() async throws {
        let seen = Seen()
        let provider = try make(running: false, answers: [
            "retrieveUserQuotaSummary": (200, Self.summary),
            "loadCodeAssist": (200, #"{"paidTier":{"name":"Ultra"}}"#),
        ], keychain: #"{"token":{"access_token":"ya29.valid","refresh_token":"1//r","expiry":"2030-01-01T00:00:00Z"}}"#, seen: seen)
        let snapshot = try await provider.refreshPlain()
        #expect(snapshot.quotas.count == 4)
        #expect(snapshot.accountTier == .custom("ULTRA"))
        let first = try #require(seen.requests.first)
        #expect(first.url?.host == "daily-cloudcode-pa.googleapis.com")
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.valid")
    }

    @Test func `should ask to sign in when the saved login is refused and agy isn't there to renew it`() async throws {
        let provider = try make(running: false, answers: ["retrieveUserQuotaSummary": (401, "")],
                                keychain: #"{"token":{"access_token":"ya29.stale"}}"#)
        await #expect(throws: UsageError.authenticationRequired) {
            try await provider.refreshPlain()
        }
    }

    @Test(.needsScriptEngine) func `should run agy to renew a saved login Google refuses, then show the quota`() async throws {
        let seen = Seen()
        let provider = try make(running: false, answers: ["retrieveUserQuotaSummary": (200, Self.summary)],
                                keychain: #"{"token":{"access_token":"ya29.stale","refresh_token":"1//r"}}"#,
                                renewed: #"{"token":{"access_token":"ya29.fresh","refresh_token":"1//r"}}"#, seen: seen)
        let snapshot = try await provider.refreshPlain()
        #expect(snapshot.quotas.count == 4)
        #expect(seen.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.fresh")
    }

    @Test func `should ask to sign in again when agy's renewed login is refused too`() async throws {
        let provider = try make(running: false, answers: ["retrieveUserQuotaSummary": (401, "")],
                                keychain: #"{"token":{"access_token":"ya29.stale"}}"#,
                                renewed: #"{"token":{"access_token":"ya29.revoked"}}"#)
        await #expect(throws: UsageError.sessionExpired(hint: "Sign in to Antigravity or run `agy` again.")) {
            try await provider.refreshPlain()
        }
    }

    @Test func `should be unavailable when the app is neither running nor signed in`() async throws {
        #expect(try await make(running: false).isPlainAvailable() == false)
    }

    @Test func `should be available when the app is running without a saved login`() async throws {
        #expect(try await make().isPlainAvailable())
    }
}
