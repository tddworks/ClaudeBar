#if os(Linux)
import Foundation
import Testing
@testable import DataSources

/// Where Linux keeps an app's data: `XDG_DATA_HOME`, or `~/.local/share`
/// (XDG Base Directory spec).
@Suite
struct LinuxApplicationDataTests {
    private let home = URL(fileURLWithPath: "/home/someone", isDirectory: true)

    private func applicationData(_ environment: [String: String]) -> URL? {
        Platform.current.applicationData?(home, { environment[$0] })
    }

    @Test func `should keep app data where XDG_DATA_HOME says`() {
        #expect(applicationData(["XDG_DATA_HOME": "/data/someone"])?.path == "/data/someone")
    }

    @Test func `should keep app data in the home's local share when XDG_DATA_HOME is unset`() {
        #expect(applicationData([:])?.path == "/home/someone/.local/share")
    }

    /// The spec: a relative path in an XDG variable is invalid and is ignored.
    @Test func `should keep app data in the home's local share when XDG_DATA_HOME is relative`() {
        #expect(applicationData(["XDG_DATA_HOME": "data"])?.path == "/home/someone/.local/share")
    }
}
#endif
