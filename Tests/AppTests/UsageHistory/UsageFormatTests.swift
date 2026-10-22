import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The one spelling of a usage number in the popover.
@Suite
struct UsageFormatTests {
    @Test func `should write a change with its sign, rounded to a percent`() {
        #expect(UsageFormat.change(0.124) == "+12%")
        #expect(UsageFormat.change(-0.08) == "−8%")
        #expect(UsageFormat.change(0) == "+0%")
    }

    @Test func `should write a working time in hours and minutes, or minutes and seconds under an hour`() {
        #expect(UsageFormat.duration(78_000) == "21h 40m")
        #expect(UsageFormat.duration(330) == "5m 30s")
    }
}
