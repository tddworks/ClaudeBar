import Foundation
import Testing
@testable import Diagnostics

/// Where the app's log goes: the person's file, except in a test run, which
/// writes a file of its own (#690).
@Suite
struct AppLogTests {
    private let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path

    @Test
    func `should keep a test run's lines out of the person's log`() {
        #expect(AppLog.logFileURL.standardizedFileURL.path.hasPrefix(temporary))
    }

    @Test
    func `should give each test run a log of its own`() {
        let one = AppLog.logFileURL(testRun: true)
        let other = AppLog.logFileURL(testRun: true)

        #expect(one != other)
        #expect(one.lastPathComponent == "ClaudeBar.log")
    }

    /// Where people share one temporary folder (Linux's `/tmp`), a folder
    /// every run shares would belong to the first user's run, and another
    /// user's run couldn't write in it.
    @Test
    func `should put a test run's log in a folder of its own, right in the temporary folder`() {
        let folder = AppLog.logFileURL(testRun: true).deletingLastPathComponent()

        #expect(folder.deletingLastPathComponent().standardizedFileURL.path == temporary)
    }

    #if !os(Windows)
    /// Its lines can name paths, so only the person running the tests reads them.
    @Test
    func `should keep a test run's log folder to the person running the tests`() throws {
        let folder = AppLog.logFileURL.deletingLastPathComponent()

        let permissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int

        #expect(permissions == 0o700)
    }
    #endif

    @Test
    func `should keep the person's log where it always was outside a test run`() {
        let person = AppLog.logFileURL(testRun: false)

        #if os(macOS)
        #expect(person.pathComponents.suffix(4) == ["Library", "Logs", "ClaudeBar", "ClaudeBar.log"])
        #else
        #expect(person.pathComponents.suffix(3) == ["ClaudeBar", "Logs", "ClaudeBar.log"])
        #endif
        #expect(!person.standardizedFileURL.path.hasPrefix(temporary))
    }

    /// What each runner passes, as captured from inside a test (#690).
    @Test(arguments: [
        ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper",
         "--test-bundle-path", "/tmp/argv/.build/out/Products/Debug/ATests.xctest/Contents/MacOS/ATests",
         "/tmp/argv/.build/out/Products/Debug/ATests.xctest/Contents/MacOS/ATests", "--testing-library", "swift-testing"],
        ["/Applications/Xcode.app/Contents/Developer/usr/bin/xctest", "/tmp/argv/.build/out/Products/Debug/ATests.xctest"],
        [#"H:\workspace\argv\.build\x86_64-unknown-windows-msvc\debug\ArgvPackageTests.xctest"#, "--testing-library", "swift-testing"],
        [#"H:\workspace\argv\.build\x86_64-unknown-windows-msvc\debug\ArgvPackageTests.xctest"#],
        ["/work/argv/.build/x86_64-unknown-linux-gnu/debug/ArgvPackageTests.xctest", "--testing-library", "swift-testing"],
    ])
    func `should recognise a test run from what swift test passes`(arguments: [String]) {
        #expect(AppLog.isTestRun(arguments: arguments, environment: [:]))
    }

    @Test
    func `should recognise a test run Xcode started`() {
        let environment = ["XCTestConfigurationFilePath": "/tmp/AppTests.xctestconfiguration"]

        #expect(AppLog.isTestRun(arguments: ["/tmp/DerivedData/ClaudeBar.app/Contents/MacOS/ClaudeBar"], environment: environment))
    }

    @Test(arguments: [
        ["/Applications/ClaudeBar.app/Contents/MacOS/ClaudeBar"],
        [#"C:\Users\someone\AppData\Local\ClaudeBarWindows\current\ClaudeBar.exe"#],
        [#"C:\Users\someone\AppData\Local\ClaudeBarWindows\current\claudebar-upload.exe"#],
        ["/home/someone/.local/share/claudebar/claudebar-probe", "--json"],
    ])
    func `should not take the app or its helpers for a test run`(arguments: [String]) {
        #expect(!AppLog.isTestRun(arguments: arguments, environment: [:]))
    }
}
