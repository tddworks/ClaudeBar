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
    func `finds the colon in an hours-and-minutes countdown`() {
        let text = "4:40"
        let ranges = CountdownColon.ranges(in: text)

        #expect(ranges.count == 1)
        #expect(colons(in: text) == [":"])
        #expect(text[ranges[0]] == ":")
    }

    @Test
    func `finds the colon inside a composed single-window label`() {
        let text = "98% · 4:40"
        let ranges = CountdownColon.ranges(in: text)

        #expect(ranges.count == 1)
        #expect(text[ranges[0]] == ":")
    }

    @Test
    func `finds a colon in each window of a dual-window label`() {
        let ranges = CountdownColon.ranges(in: "5h 12% · 4:40 | 7d 34% · 3:20")

        #expect(ranges.count == 2)
    }

    @Test
    func `finds only the window that is in hours range`() {
        let text = "0h 98% · 4:40 | Fable 22% · 2d"
        let ranges = CountdownColon.ranges(in: text)

        #expect(ranges.count == 1)
        #expect(text[ranges[0]] == ":")
    }

    // MARK: - Labels with nothing to blink

    @Test
    func `returns no ranges for a minutes-only countdown`() {
        #expect(CountdownColon.ranges(in: "98% · 45m").isEmpty)
    }

    @Test
    func `returns no ranges for a days countdown`() {
        #expect(CountdownColon.ranges(in: "22% · 2d").isEmpty)
    }

    @Test
    func `returns no ranges for a label with no duration at all`() {
        #expect(CountdownColon.ranges(in: "98%").isEmpty)
    }

    @Test
    func `returns no ranges for an empty label`() {
        #expect(CountdownColon.ranges(in: "").isEmpty)
    }

    // MARK: - Colons that are not countdowns

    @Test
    func `ignores a colon that is not preceded by a digit`() {
        // A probe-supplied menuBarTitle can carry a colon (e.g. an account
        // discriminator). Only a digit:digit-digit run is a countdown.
        #expect(CountdownColon.ranges(in: "acct:main 12% · 45m").isEmpty)
    }

    @Test
    func `ignores a colon that is not followed by two digits`() {
        #expect(CountdownColon.ranges(in: "4:4m").isEmpty)
        #expect(CountdownColon.ranges(in: "4: 40").isEmpty)
    }

    // MARK: - Range validity

    @Test
    func `ranges address exactly one character each`() {
        let text = "0h 98% · 4:40 | 7d 34% · 3:20"

        for range in CountdownColon.ranges(in: text) {
            #expect(text.distance(from: range.lowerBound, to: range.upperBound) == 1)
        }
    }

    @Test
    func `ranges survive conversion to NSRange for attributed-string use`() {
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
