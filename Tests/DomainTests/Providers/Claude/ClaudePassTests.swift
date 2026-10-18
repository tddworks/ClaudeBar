import Testing
import Foundation
@testable import Domain

@Suite
struct ClaudePassTests {

    @Test
    func `should keep how many guest passes are left and the link to share`() {
        // Given
        let url = URL(string: "https://claude.ai/referral/ABC123")!

        // When
        let pass = GuestPass(passesRemaining: 3, referralURL: url)

        // Then
        #expect(pass.passesRemaining == 3)
        #expect(pass.referralURL == url)
    }

    @Test
    func `should keep the link to share when the number of passes left is unknown`() {
        let url = URL(string: "https://claude.ai/referral/ABC123")!
        let pass = GuestPass(referralURL: url)

        #expect(pass.passesRemaining == nil)
        #expect(pass.referralURL == url)
    }

    @Test
    func `should have passes to share when some are left`() {
        let pass = GuestPass(
            passesRemaining: 3,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.hasPassesAvailable == true)
    }

    @Test
    func `should have no passes to share when none are left`() {
        let pass = GuestPass(
            passesRemaining: 0,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.hasPassesAvailable == false)
    }

    @Test
    func `should offer passes to share when the number left is unknown`() {
        let pass = GuestPass(referralURL: URL(string: "https://claude.ai/referral/ABC123")!)

        #expect(pass.hasPassesAvailable == true)
    }

    @Test
    func `should print 3 passes left`() {
        let pass = GuestPass(
            passesRemaining: 3,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.displayText == "3 passes left")
    }

    @Test
    func `should print 1 pass left`() {
        let pass = GuestPass(
            passesRemaining: 1,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.displayText == "1 pass left")
    }

    @Test
    func `should print No passes left when none are left`() {
        let pass = GuestPass(
            passesRemaining: 0,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )

        #expect(pass.displayText == "No passes left")
    }

    @Test
    func `should print Share Claude Code when the number left is unknown`() {
        let pass = GuestPass(referralURL: URL(string: "https://claude.ai/referral/ABC123")!)

        #expect(pass.displayText == "Share Claude Code")
    }

    @Test
    func `should treat two passes with the same count and link as the same`() {
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
