import Testing
import Foundation
@testable import Domain

@Suite("UsageError sessionExpired hint Tests")
struct ProbeErrorTests {

    @Test
    func `should tell the person their session expired and to log in again when the provider gives no hint`() {
        let error = UsageError.sessionExpired()
        let description = error.localizedDescription
        #expect(description.contains("Session expired"))
        #expect(description.contains("Please log in again"))
    }

    @Test
    func `should tell the person how to log in again with the provider's own hint when the session expired`() {
        let error = UsageError.sessionExpired(hint: "Run `claude` in terminal to log in again.")
        let description = error.localizedDescription
        #expect(description.contains("Session expired"))
        #expect(description.contains("claude"))
    }

    @Test
    func `should point the person to the Alibaba Cloud console when an Alibaba session expired`() {
        let error = UsageError.sessionExpired(hint: "Re-authenticate in Alibaba Cloud console.")
        let description = error.localizedDescription
        #expect(description.contains("Session expired"))
        #expect(description.contains("Alibaba"))
    }

    @Test
    func `should treat two expired sessions as the same problem whatever their hints say`() {
        let error1 = UsageError.sessionExpired()
        let error2 = UsageError.sessionExpired(hint: "some hint")
        #expect(error1 == error2)
    }

    @Test
    func `should treat an expired session without a hint as the same problem as one with no hint given`() {
        // Ensures backward compatibility: .sessionExpired == .sessionExpired()
        let error: UsageError = .sessionExpired()
        #expect(error == .sessionExpired())
    }
}
