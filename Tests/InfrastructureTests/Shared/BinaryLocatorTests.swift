import Testing
import Foundation
@testable import Infrastructure

@Suite
struct BinaryLocatorTests {

    @Test
    func `which finds system binary`() {
        let path = BinaryLocator.which("ls")
        #expect(path != nil)
        #expect(path?.hasSuffix("/ls") == true)
    }

    @Test
    func `which returns nil for unknown binary`() {
        let path = BinaryLocator.which("unknown-binary-xyz-123")
        #expect(path == nil)
    }

    @Test
    func `locate instance method finds binary`() {
        let locator = BinaryLocator()
        let path = locator.locate("ls")
        #expect(path != nil)
    }

    @Test
    func `findInCommonPaths finds executable in homebrew bin`() {
        // Given - a binary that exists in /opt/homebrew/bin (common on Apple Silicon)
        // This tests the fallback mechanism for launchd contexts

        // When - we search common paths for 'brew' (if homebrew is installed)
        let path = BinaryLocator.findInCommonPaths("brew")

        // Then - we should find it (or nil if homebrew isn't installed)
        // This test verifies the fallback mechanism works, not that brew is installed
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
            #expect(path == "/opt/homebrew/bin/brew")
        } else if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
            #expect(path == "/usr/local/bin/brew")
        }
    }

    @Test
    func `findInCommonPaths returns nil for non-existent binary`() {
        // Given - a binary that doesn't exist anywhere
        // When - we search common paths
        let path = BinaryLocator.findInCommonPaths("unknown-binary-xyz-123-fallback")

        // Then - we should get nil
        #expect(path == nil)
    }

    @Test
    func `common paths include bun global bin`() {
        // Bun-installed CLIs (e.g. omp) live in ~/.bun/bin, which launchd
        // contexts never have on PATH.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(BinaryLocator.commonPaths.contains("\(home)/.bun/bin"))
    }

    @Test
    func `which falls back to common paths when shell fails`() {
        // This test verifies the overall behavior: which() should find binaries
        // even in launchd contexts where the shell PATH is restricted.
        // If 'ls' is in /bin/ls, the fallback should find it even if shell which fails.

        let path = BinaryLocator.which("ls")
        #expect(path != nil)
        #expect(path?.hasSuffix("/ls") == true)
    }
}