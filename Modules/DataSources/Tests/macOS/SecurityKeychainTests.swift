#if os(macOS)
import Foundation
import Testing
@testable import DataSources

/// The Mac's secret store is its Keychain, asked through the `security` tool:
/// an item by service and, when given, account; with no account, a save names
/// the person, as Claude Code's own item does.
@Suite
struct SecurityKeychainTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [[String]] = []
        func append(_ arguments: [String]) { lock.withLock { calls.append(arguments) } }
        var all: [[String]] { lock.withLock { calls } }
    }

    private func keychain(answering status: Int32 = 0, _ output: String = "", calls: Calls) -> SecurityKeychain {
        SecurityKeychain(run: { arguments in
            calls.append(arguments)
            return (status, output)
        })
    }

    @Test func `should read an item's password by its service, and its account when it has one`() {
        let calls = Calls()
        let keychain = keychain(answering: 0, "secret\n", calls: calls)

        let any = keychain.password(service: "gh:github.com", account: nil)
        let named = keychain.password(service: "gh:github.com", account: "octocat")

        #expect(calls.all == [
            ["find-generic-password", "-s", "gh:github.com", "-w"],
            ["find-generic-password", "-s", "gh:github.com", "-a", "octocat", "-w"],
        ])
        #expect(any == "secret\n")
        #expect(named == "secret\n")
    }

    @Test func `should find no password when security can't find the item`() {
        #expect(keychain(answering: 44, calls: Calls()).password(service: "Missing", account: nil) == nil)
    }

    @Test func `should save over the item with the person's name as its account when it names none`() {
        let calls = Calls()
        let keychain = keychain(calls: calls)

        let kept = keychain.save("{}", service: "Some-credentials", account: nil)
        _ = keychain.save("{}", service: "Some-credentials", account: "octocat")

        #expect(kept)
        #expect(calls.all == [
            ["add-generic-password", "-U", "-s", "Some-credentials", "-a", NSUserName(), "-w", "{}"],
            ["add-generic-password", "-U", "-s", "Some-credentials", "-a", "octocat", "-w", "{}"],
        ])
    }

    @Test func `should say a save wasn't kept when security fails`() {
        #expect(!keychain(answering: 1, calls: Calls()).save("{}", service: "Some-credentials", account: nil))
    }
}
#endif
