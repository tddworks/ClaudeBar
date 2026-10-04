import Foundation
import Testing
@testable import DataSources

/// `{{system.timeZone}}` is the Mac's time zone, as a browser sends it.
@Suite
struct SystemTemplateTests {
    @Test
    func `the system time zone fills a template without a credential`() {
        #expect(Template.fill("tz={{system.timeZone}}", with: nil) == "tz=\(TimeZone.current.identifier)")
    }
}
