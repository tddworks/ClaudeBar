import Testing
import Foundation
@testable import DataSources

/// The login-shell lookup the App hands the engine: what the app already has
/// in its own environment is answered from there.
@Suite
struct LoginShellLookupFactoryTests {
    @Test
    func `should answer a variable the app was started with from its own environment`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PATH"])

        #expect(DataSources.makeLoginShellLookup()("PATH") == path)
    }
}
