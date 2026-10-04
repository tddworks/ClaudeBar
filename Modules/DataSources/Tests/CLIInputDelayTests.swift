import Foundation
import Testing
@testable import DataSources

/// A TUI that redraws after its startup paint discards anything typed
/// sooner, so a `cli` call can wait before typing its input.
@Suite
struct CLIInputDelayTests {
    @Test
    func `a stated input delay reaches the terminal`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data(#"{"cli":"tool","input":"/usage","inputDelay":1.5}"#.utf8))
        #expect(call.inputDelay == 1.5)
        #expect((CLIFetcher.system(call) as? DefaultCLIExecutor)?.inputDelay == 1.5)
    }

    @Test
    func `no input delay keeps the terminal's default`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data(#"{"cli":"tool"}"#.utf8))
        #expect(call.inputDelay == nil)
        #expect((CLIFetcher.system(call) as? DefaultCLIExecutor)?.inputDelay == 0.4)
    }

    @Test
    func `the delay survives a round trip`() throws {
        let call = CLICall(cli: "tool", input: "/usage", inputDelay: 1.5)
        #expect(try JSONDecoder().decode(CLICall.self, from: JSONEncoder().encode(call)) == call)
    }
}

