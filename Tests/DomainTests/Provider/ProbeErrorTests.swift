import Testing
import Foundation
@testable import Domain

@Suite("UsageError sessionExpired hint Tests")
struct ProbeErrorTests {

    @Test
    func `sessionExpired with no hint shows generic message`() {
        let error = UsageError.sessionExpired()
        let description = error.localizedDescription
        #expect(description.contains("Session expired"))
        #expect(description.contains("Please log in again"))
    }

    @Test
    func `sessionExpired with hint shows provider-specific message`() {
        let error = UsageError.sessionExpired(hint: "Run `claude` in terminal to log in again.")
        let description = error.localizedDescription
        #expect(description.contains("Session expired"))
        #expect(description.contains("claude"))
    }

    @Test
    func `sessionExpired with alibaba hint shows alibaba message`() {
        let error = UsageError.sessionExpired(hint: "Re-authenticate in Alibaba Cloud console.")
        let description = error.localizedDescription
        #expect(description.contains("Session expired"))
        #expect(description.contains("Alibaba"))
    }

    @Test
    func `sessionExpired equality ignores hint`() {
        let error1 = UsageError.sessionExpired()
        let error2 = UsageError.sessionExpired(hint: "some hint")
        #expect(error1 == error2)
    }

    @Test
    func `sessionExpired without parens matches sessionExpired with nil hint`() {
        // Ensures backward compatibility: .sessionExpired == .sessionExpired()
        let error: UsageError = .sessionExpired()
        #expect(error == .sessionExpired())
    }
}
