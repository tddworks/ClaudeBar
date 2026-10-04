import Foundation
import Mockable
import Providers
@testable import DataSources
import Quotas
import Testing

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

    /// `answers`: path suffix → (status, body); anything else is a 404.
    private func make(running: Bool = true, answers: [String: (Int, String)] = [:], keychain: String? = nil,
                      seen: Seen = Seen()) throws -> Provider {
        let commands = MockCLIExecutor()
        given(commands).locate(.any).willReturn(nil)
        given(commands).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable binary, _, _, _, _, _ in
                CLIResult(output: binary.hasSuffix("pgrep") ? (running ? Self.processLine : "") : Self.lsof)
            }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.add(request)
            let path = request.url?.path ?? ""
            guard let answer = answers.first(where: { path.hasSuffix($0.key) })?.value else { return (Data(), StubbedProvider.response(404)) }
            return (Data(answer.1.utf8), StubbedProvider.response(answer.0))
        }
        let definition = try Providers.builtIn("antigravity")
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, makeCLIExecutor: { _ in commands }, makeCommandExecutor: { _ in commands },
                             network: network, localNetwork: network,
                             processPaths: { running ? ["/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm"] : [] },
                             makeTransport: { _, _, _, _ in MockRPCTransport() },
                             security: { @Sendable arguments in
                                 guard let keychain, arguments.contains("gemini"), arguments.contains("antigravity") else { return (44, "") }
                                 return (0, "go-keyring-base64:" + Data(keychain.utf8).base64EncodedString())
                             },
                             scripts: Providers.builtInScripts, secrets: nil, browserCookies: SystemBrowserCookies(),
                             environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        })
    }

    @Test func `definition keeps Antigravity's identity, with no dashboard`() throws {
        let provider = try make()
        #expect(provider.name == "Antigravity")
        #expect(provider.defaultAccount.isEnabled)
        #expect(provider.defaultAccount.dashboardURL == nil)
        #expect(provider.accountForm.isEmpty)
    }

    // MARK: - The running app

    @Test func `the app's quota summary is its shared pools, with their stated windows`() async throws {
        let seen = Seen()
        let provider = try make(answers: ["RetrieveUserQuotaSummary": (200, #"{"response":\#(Self.summary)}"#)], seen: seen)
        let quotas = try await provider.defaultAccount.refresh().quotas
        #expect(quotas.map(\.quotaType) == [.session, .weekly, .modelSpecific("Claude"), .modelSpecific("Claude Weekly")])
        #expect(quotas.map(\.percentRemaining) == [80, 60, 40, 20])
        // A 5-hour bucket is 5 hours — the probe called the 3p one a week.
        #expect(quotas.map { $0.window?.length } == [18000, 604800, 18000, 604800])
        let request = try #require(seen.requests.first)
        #expect(request.url?.absoluteString == "https://127.0.0.1:42135/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")
        #expect(request.value(forHTTPHeaderField: "X-Codeium-Csrf-Token") == "9f808dbe-cb96-4829")
    }

    @Test func `an older app answers user status: a quota per model, its plan and email`() async throws {
        let snapshot = try await make(answers: ["GetUserStatus": (200, Self.userStatus)]).defaultAccount.refresh()
        #expect(snapshot.quotas.map(\.quotaType) == [.modelSpecific("Claude Sonnet"), .modelSpecific("Gemini Pro")])
        #expect(snapshot.quotas.map(\.percentRemaining) == [75, 50])
        #expect(snapshot.quotas[1].resetsAt == Date(timeIntervalSince1970: 1735689600))
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountTier == .custom("PRO"))
    }

    // MARK: - The app closed: Google, with its saved login

    @Test func `with the app closed, Google's quota is read with the saved login`() async throws {
        let seen = Seen()
        let provider = try make(running: false, answers: [
            "retrieveUserQuotaSummary": (200, Self.summary),
            "loadCodeAssist": (200, #"{"paidTier":{"name":"Ultra"}}"#),
        ], keychain: #"{"token":{"access_token":"ya29.valid","refresh_token":"1//r","expiry":"2030-01-01T00:00:00Z"}}"#, seen: seen)
        let snapshot = try await provider.defaultAccount.refresh()
        #expect(snapshot.quotas.count == 4)
        #expect(snapshot.accountTier == .custom("ULTRA"))
        let first = try #require(seen.requests.first)
        #expect(first.url?.host == "daily-cloudcode-pa.googleapis.com")
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.valid")
    }

    @Test func `a refused saved login asks to sign in again`() async throws {
        let provider = try make(running: false, answers: ["retrieveUserQuotaSummary": (401, "")],
                                keychain: #"{"token":{"access_token":"ya29.stale"}}"#)
        await #expect(throws: UsageError.sessionExpired(hint: "Sign in to Antigravity or run `agy` again.")) {
            try await provider.defaultAccount.refresh()
        }
    }

    @Test func `neither running nor signed in is not available`() async throws {
        #expect(await (try make(running: false)).defaultAccount.isAvailable() == false)
    }

    @Test func `running is available without a saved login`() async throws {
        #expect(await (try make()).defaultAccount.isAvailable())
    }
}
