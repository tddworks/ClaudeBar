#if os(macOS)
import Foundation
import Testing
@testable import DataSources

/// A TUI that redraws after its startup paint discards anything typed
/// sooner, so a `cli` call can wait before typing its input.
@Suite
struct CLIInputDelayTests {
    @Test
    func `should wait the stated delay before typing into the CLI`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data(#"{"cli":"tool","input":"/usage","inputDelay":1.5}"#.utf8))
        #expect(call.inputDelay == 1.5)
        #expect((CLIFetcher.system(programs: MacProcesses(), terminal: MacPty())(call) as? DefaultCLIExecutor)?.inputDelay == 1.5)
    }

    @Test
    func `should wait the terminal's default 0.4 seconds when no delay is stated`() throws {
        let call = try JSONDecoder().decode(CLICall.self, from: Data(#"{"cli":"tool"}"#.utf8))
        #expect(call.inputDelay == nil)
        #expect((CLIFetcher.system(programs: MacProcesses(), terminal: MacPty())(call) as? DefaultCLIExecutor)?.inputDelay == 0.4)
    }

    @Test
    func `should keep the input delay when the definition is written out and read back`() throws {
        let call = CLICall(cli: "tool", input: "/usage", inputDelay: 1.5)
        #expect(try JSONDecoder().decode(CLICall.self, from: JSONEncoder().encode(call)) == call)
    }
}

#endif
