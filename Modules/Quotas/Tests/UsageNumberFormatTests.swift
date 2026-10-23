import Testing
@testable import Quotas

/// The one spelling of a usage number — a count, a share, a change — so the
/// chart, the card and a webhook's message never print the same figure two ways.
@Suite
struct UsageNumberFormatTests {
    @Test func `should write a count in thousands, millions or billions with one decimal at most`() {
        #expect(UsageNumberFormat.count(500) == "500")
        #expect(UsageNumberFormat.count(1_200) == "1.2K")
        #expect(UsageNumberFormat.count(19_500_000) == "19.5M")
        #expect(UsageNumberFormat.count(2_000_000_000) == "2B")
    }

    @Test func `should write a share as a whole percent`() {
        #expect(UsageNumberFormat.share(0.62) == "62%")
        #expect(UsageNumberFormat.share(1) == "100%")
    }

    @Test func `should write a change with its sign, rounded to a percent`() {
        #expect(UsageNumberFormat.change(0.124) == "+12%")
        #expect(UsageNumberFormat.change(-0.08) == "\u{2212}8%")
        #expect(UsageNumberFormat.change(0) == "+0%")
    }

    @Test func `should write a fall too small to round to a percent as no change`() {
        #expect(UsageNumberFormat.change(-0.001) == "+0%")
    }
}
