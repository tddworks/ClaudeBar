import Testing
import Foundation
@testable import Infrastructure

/// The port a local server tells its scripts — the hooks' and the local API's.
@Suite
struct PortFileTests {
    /// A port file of the test's own, so a running ClaudeBar's is never touched.
    private let file = PortFile(path: FileManager.default.temporaryDirectory
        .appendingPathComponent("portfile-\(UUID().uuidString)/port").path)

    @Test
    func `should leave the hooks' port in claudebar-hook-port under the .claude folder`() {
        #expect(PortFile.hooks.path.contains("/.claude/"))
        #expect(PortFile.hooks.path.hasSuffix("claudebar-hook-port"))
    }

    @Test
    func `should leave the local API's port in api-port under the .claudebar folder`() {
        #expect(PortFile.localAPI.path.hasSuffix("/.claudebar/api-port"))
    }

    @Test
    func `should read back the port ClaudeBar left`() throws {
        try file.write(19847)

        #expect(file.read() == 19847)
        file.remove()
    }

    @Test
    func `should find no port once ClaudeBar removes its port file`() throws {
        try file.write(12345)
        file.remove()

        #expect(file.read() == nil)
    }

    @Test
    func `should find no port when ClaudeBar left no port file`() {
        #expect(file.read() == nil)
    }

    @Test
    func `should read back the port ClaudeBar left on a later write`() throws {
        try file.write(12345)
        try file.write(9999)

        #expect(file.read() == 9999)
        file.remove()
    }
}
