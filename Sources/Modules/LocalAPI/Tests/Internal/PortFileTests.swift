import Foundation
import Testing
@testable import LocalAPI

@Suite
struct PortFileTests {
    @Test
    func `should leave the local API's port in api-port under the .claudebar folder`() {
        #expect(PortFile.localAPI.path.hasSuffix("/.claudebar/api-port"))
    }
}
