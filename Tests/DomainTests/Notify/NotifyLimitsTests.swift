import Testing
import Foundation
@testable import Domain

@Suite
struct NotifyLimitsTests {

    // MARK: - Text

    @Test
    func `text trims surrounding whitespace`() {
        #expect(NotifyLimits.text("  Claude 5h  ", maximum: 24) == "Claude 5h")
    }

    @Test
    func `text drops the NUL the gateway rejects`() {
        #expect(NotifyLimits.text("Claude\0 5h", maximum: 24) == "Claude 5h")
    }

    @Test
    func `text shortens an oversized value to the maximum`() {
        // A long account discriminator should reach the phone shortened, never
        // fail the whole publish.
        #expect(NotifyLimits.text("abcdefghij", maximum: 4) == "abcd")
    }

    @Test
    func `text reports an empty value as nil`() {
        // An absent field must be absent, not sent as "".
        #expect(NotifyLimits.text("", maximum: 24) == nil)
    }

    @Test
    func `text reports a whitespace only value as nil`() {
        #expect(NotifyLimits.text("  \n\t ", maximum: 24) == nil)
    }

    @Test
    func `text passes nil through`() {
        #expect(NotifyLimits.text(nil, maximum: 24) == nil)
    }

    // MARK: - Progress

    @Test
    func `progress clamps a negative percentage to zero`() {
        // A quota can legitimately report a negative remainder when the user is
        // over the limit, and that reads as an empty bar.
        #expect(NotifyLimits.progress(-12) == 0)
    }

    @Test
    func `progress clamps a percentage over one hundred`() {
        #expect(NotifyLimits.progress(140) == 100)
    }

    @Test
    func `progress passes a middle value through`() {
        #expect(NotifyLimits.progress(42) == 42)
    }

    @Test
    func `progress is nil for a missing value`() {
        #expect(NotifyLimits.progress(nil) == nil)
    }

    @Test
    func `progress is nil for a value that is not finite`() {
        #expect(NotifyLimits.progress(Double.nan) == nil)
        #expect(NotifyLimits.progress(Double.infinity) == nil)
    }

    // MARK: - Tint

    @Test
    func `tint accepts six hex digits with and without a leading hash`() {
        #expect(NotifyLimits.tint("59ebad") == "#59EBAD")
        #expect(NotifyLimits.tint("#59ebad") == "#59EBAD")
    }

    @Test
    func `tint accepts eight hex digits with and without a leading hash`() {
        #expect(NotifyLimits.tint("ff59ebad") == "#FF59EBAD")
        #expect(NotifyLimits.tint("#ff59ebad") == "#FF59EBAD")
    }

    @Test
    func `tint rejects a value of the wrong length`() {
        // A bad color is dropped so the rest of the payload still lands.
        #expect(NotifyLimits.tint("#fff") == nil)
        #expect(NotifyLimits.tint("#1234567") == nil)
    }

    @Test
    func `tint rejects a non hex character`() {
        #expect(NotifyLimits.tint("#59ebaz") == nil)
    }
}
