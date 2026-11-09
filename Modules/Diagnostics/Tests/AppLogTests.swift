import Foundation
import Testing
@testable import Diagnostics

/// Where the app's log goes: the person's file, except in a test run.
@Suite
struct AppLogTests {
    @Test
    func `should keep a test run's lines out of the person's log`() {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path

        #expect(AppLog.logFileURL.standardizedFileURL.path.hasPrefix(temporary))
    }
}
