import Testing
import Foundation
@testable import Infrastructure

@Suite
struct PortDiscoveryTests {
    @Test
    func `should leave ClaudeBar's port in claudebar-hook-port under the .claude folder`() {
        let path = PortDiscovery.portFilePath
        #expect(path.contains(".claude"))
        #expect(path.hasSuffix("claudebar-hook-port"))
    }

    @Test
    func `should read back the port ClaudeBar left`() throws {
        // Write port
        try PortDiscovery.writePort(19847)

        // Read it back
        let port = PortDiscovery.readPort()
        #expect(port == 19847)

        // Clean up
        PortDiscovery.removePortFile()
    }

    @Test
    func `should find no port once ClaudeBar removes its port file`() throws {
        try PortDiscovery.writePort(12345)
        PortDiscovery.removePortFile()

        let port = PortDiscovery.readPort()
        #expect(port == nil)
    }

    @Test
    func `should find no port when ClaudeBar left no port file`() {
        PortDiscovery.removePortFile()
        let port = PortDiscovery.readPort()
        #expect(port == nil)
    }

    @Test
    func `should read back the port ClaudeBar left on a later write`() throws {
        // The .claude directory should be created if it doesn't exist
        // Since we're writing to ~/.claude/ which likely exists, just verify no error
        try PortDiscovery.writePort(9999)
        let port = PortDiscovery.readPort()
        #expect(port == 9999)

        PortDiscovery.removePortFile()
    }
}
