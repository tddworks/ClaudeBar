import Testing
import Foundation
@testable import Domain

@Suite
struct CountdownColonTests {

    private func colons(in text: String) -> [String] {
        CountdownColon.ranges(in: text).map { String(text[$0]) }
    }

    // MARK: - Finding the countdown colon

    @Test
    func `should blink the colon of an hours-and-minutes countdown`() {
        let text = "4:40"
        let ranges = CountdownColon.ranges(in: text)

        #expect(ranges.count == 1)
        #expect(colons(in: text) == [":"])
        #expect(text[ranges[0]] == ":")
    }

    @Test
    func `should blink the countdown's colon in a percentage-and-countdown label`() {
        let text = "98% · 4:40"
        let ranges = CountdownColon.ranges(in: text)

        #expect(ranges.count == 1)
        #expect(text[ranges[0]] == ":")
    }

    @Test
    func `should blink the countdown colon of each window in a two-window label`() {
        let ranges = CountdownColon.ranges(in: "5h 12% · 4:40 | 7d 34% · 3:20")

        #expect(ranges.count == 2)
    }

    @Test
    func `should blink only the window counting down in hours and minutes`() {
        let text = "0h 98% · 4:40 | Fable 22% · 2d"
        let ranges = CountdownColon.ranges(in: text)

        #expect(ranges.count == 1)
        #expect(text[ranges[0]] == ":")
    }

    // MARK: - Labels with nothing to blink

    @Test
    func `should blink nothing for a countdown in minutes`() {
        #expect(CountdownColon.ranges(in: "98% · 45m").isEmpty)
    }

    @Test
    func `should blink nothing for a countdown in days`() {
        #expect(CountdownColon.ranges(in: "22% · 2d").isEmpty)
    }

    @Test
    func `should blink nothing for a label without a countdown`() {
        #expect(CountdownColon.ranges(in: "98%").isEmpty)
    }

    @Test
    func `should blink nothing for an empty label`() {
        #expect(CountdownColon.ranges(in: "").isEmpty)
    }

    // MARK: - Colons that are not countdowns

    @Test
    func `should not blink a colon in a provider's own title, like an account name`() {
        // A probe-supplied menuBarTitle can carry a colon (e.g. an account
        // discriminator). Only a digit:digit-digit run is a countdown.
        #expect(CountdownColon.ranges(in: "acct:main 12% · 45m").isEmpty)
    }

    @Test
    func `should not blink a colon that is not followed by two digits`() {
        #expect(CountdownColon.ranges(in: "4:4m").isEmpty)
        #expect(CountdownColon.ranges(in: "4: 40").isEmpty)
    }

    // MARK: - Range validity

    @Test
    func `should blink only the colon character itself`() {
        let text = "0h 98% · 4:40 | 7d 34% · 3:20"

        for range in CountdownColon.ranges(in: text) {
            #expect(text.distance(from: range.lowerBound, to: range.upperBound) == 1)
        }
    }

    @Test
    func `should blink the same colon when the menu bar draws the label as styled text`() {
        // The menu bar renderer dims these ranges inside an NSAttributedString,
        // so the returned ranges must convert cleanly against the same string.
        let text = "0h 98% · 4:40"
        let ranges = CountdownColon.ranges(in: text)
        let nsText = text as NSString

        #expect(ranges.count == 1)
        for range in ranges {
            let nsRange = NSRange(range, in: text)
            #expect(nsRange.length == 1)
            #expect(nsText.substring(with: nsRange) == ":")
        }
    }
}
