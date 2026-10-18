import Testing
import Foundation
@testable import Domain

@Suite
struct NotifyLimitsTests {

    // MARK: - Text

    @Test
    func `should send text to the phone without surrounding spaces`() {
        #expect(NotifyLimits.text("  Claude 5h  ", maximum: 24) == "Claude 5h")
    }

    @Test
    func `should leave out the NUL character Notify! refuses`() {
        #expect(NotifyLimits.text("Claude\0 5h", maximum: 24) == "Claude 5h")
    }

    @Test
    func `should shorten text that is too long rather than fail the publish`() {
        // A long account discriminator should reach the phone shortened, never
        // fail the whole publish.
        #expect(NotifyLimits.text("abcdefghij", maximum: 4) == "abcd")
    }

    @Test
    func `should leave out empty text rather than send it blank`() {
        // An absent field must be absent, not sent as "".
        #expect(NotifyLimits.text("", maximum: 24) == nil)
    }

    @Test
    func `should leave out text that is only whitespace`() {
        #expect(NotifyLimits.text("  \n\t ", maximum: 24) == nil)
    }

    @Test
    func `should leave out text that is missing`() {
        #expect(NotifyLimits.text(nil, maximum: 24) == nil)
    }

    // MARK: - Progress

    @Test
    func `should show an empty bar when a quota is over its limit`() {
        // A quota can legitimately report a negative remainder when the user is
        // over the limit, and that reads as an empty bar.
        #expect(NotifyLimits.progress(-12) == 0)
    }

    @Test
    func `should show a full bar when a percentage is over one hundred`() {
        #expect(NotifyLimits.progress(140) == 100)
    }

    @Test
    func `should show a percentage between zero and one hundred as it is`() {
        #expect(NotifyLimits.progress(42) == 42)
    }

    @Test
    func `should send no bar when the percentage is missing`() {
        #expect(NotifyLimits.progress(nil) == nil)
    }

    @Test
    func `should send no bar when the percentage is not a number or infinite`() {
        #expect(NotifyLimits.progress(Double.nan) == nil)
        #expect(NotifyLimits.progress(Double.infinity) == nil)
    }

    // MARK: - Tint

    @Test
    func `should send a six-digit hex color in uppercase with a leading hash`() {
        #expect(NotifyLimits.tint("59ebad") == "#59EBAD")
        #expect(NotifyLimits.tint("#59ebad") == "#59EBAD")
    }

    @Test
    func `should send an eight-digit hex color in uppercase with a leading hash`() {
        #expect(NotifyLimits.tint("ff59ebad") == "#FF59EBAD")
        #expect(NotifyLimits.tint("#ff59ebad") == "#FF59EBAD")
    }

    @Test
    func `should leave out a color with the wrong number of digits`() {
        // A bad color is dropped so the rest of the payload still lands.
        #expect(NotifyLimits.tint("#fff") == nil)
        #expect(NotifyLimits.tint("#1234567") == nil)
    }

    @Test
    func `should leave out a color with a character that is not hex`() {
        #expect(NotifyLimits.tint("#59ebaz") == nil)
    }
}
