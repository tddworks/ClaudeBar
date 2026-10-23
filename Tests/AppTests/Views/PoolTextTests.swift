import Foundation
import Testing
import Providers
@testable import ClaudeBar

/// The pool line's words: the sum, past a hundred, across the logins counted.
@Suite
struct PoolTextTests {
    private func pool(_ percents: Double...) throws -> Pool {
        try #require(Pool(shares: percents.enumerated().map { Pool.Share(loginId: "codex.\($0.offset)", percent: $0.element) }))
    }

    @Test func `should say the logins' room together and how many logins it spans`() throws {
        #expect(PoolText.line(for: try pool(62, 88, 90)) == "240% left across 3 logins")
    }

    @Test func `should say a sum past a hundred plainly and in whole percent`() throws {
        #expect(PoolText.line(for: try pool(95.6, 90.2)) == "185% left across 2 logins")
    }
}
