import Testing
import Foundation
@testable import Domain

@Suite
struct ClaudePassTests {

    @Test
    func `creates pass with count and URL`() {
        // Given
        let url = URL(string: "https://claude.ai/referral/ABC123")!

        // When
        let pass = GuestPass(passesRemaining: 3, referralURL: url)

        // Then
        #expect(pass.passesRemaining == 3)
        #expect(pass.referralURL == url)
    }

    @Test
    func `creates pass with URL only when count is unknown`() {
        let url = URL(string: "https://claude.ai/referral/ABC123")!
        let pass = GuestPass(referralURL: url)

        #expect(pass.passesRemaining == nil)
        #expect(pass.referralURL == url)
    }

    @Test
    func `hasPassesAvailable returns true when passes remain`() {
        let pass = GuestPass(
            passesRemaining: 3,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.hasPassesAvailable == true)
    }

    @Test
    func `hasPassesAvailable returns false when no passes remain`() {
        let pass = GuestPass(
            passesRemaining: 0,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.hasPassesAvailable == false)
    }

    @Test
    func `hasPassesAvailable returns true when count is unknown`() {
        let pass = GuestPass(referralURL: URL(string: "https://claude.ai/referral/ABC123")!)

        #expect(pass.hasPassesAvailable == true)
    }

    @Test
    func `displayText formats correctly for multiple passes`() {
        let pass = GuestPass(
            passesRemaining: 3,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.displayText == "3 passes left")
    }

    @Test
    func `displayText formats correctly for single pass`() {
        let pass = GuestPass(
            passesRemaining: 1,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.displayText == "1 pass left")
    }

    @Test
    func `displayText formats correctly for no passes`() {
        let pass = GuestPass(
            passesRemaining: 0,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.displayText == "No passes left")
    }

    @Test
    func `displayText shows share message when count is unknown`() {
        let pass = GuestPass(referralURL: URL(string: "https://claude.ai/referral/ABC123")!)

        #expect(pass.displayText == "Share Claude Code")
    }

    @Test
    func `conforms to Sendable and Equatable`() {
        let pass1 = GuestPass(
            passesRemaining: 3,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )
        let pass2 = GuestPass(
            passesRemaining: 3,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass1 == pass2)
    }
}
