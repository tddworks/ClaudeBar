#if os(macOS)
import Foundation
import Mockable
import Testing
@testable import DataSources

/// The Mac reads command lines with `pgrep` and listening ports with `lsof`,
/// and names both for Import's disclosure.
@Suite
struct MacLocalServersTests {
    final class Asked: @unchecked Sendable { var argv: [[String]] = [] }

    private func servers(answering output: String, asked: Asked = Asked()) -> MacLocalServers {
        let runner = MockCLIExecutor()
        given(runner).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, args, _, _, _, _ in
                asked.argv.append([binary] + args)
                return CLIResult(output: output)
            }
        return MacLocalServers(runner: runner)
    }

    @Test func `should read each command line pgrep lists with its pid`() async {
        let asked = Asked()
        let lines = await servers(answering: "42 /opt/acme/acme_server --app acme\n\n77 /usr/bin/acme_server -x\n", asked: asked)
            .commandLines(naming: ["acme_server", "acme-ls"])
        #expect(lines == [ProgramLine(pid: 42, text: "/opt/acme/acme_server --app acme"),
                          ProgramLine(pid: 77, text: "/usr/bin/acme_server -x")])
        #expect(asked.argv == [["/usr/bin/pgrep", "-a", "-lf", "acme_server|acme-ls"]])
    }

    @Test func `should read no command line when pgrep finds none`() async {
        let runner = MockCLIExecutor()
        given(runner).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willThrow(UsageError.timeout)
        #expect(await MacLocalServers(runner: runner).commandLines(naming: ["acme_server"]).isEmpty)
    }

    @Test func `should read each port lsof lists as listening, once, in order`() async {
        let asked = Asked()
        let lsof = """
        acme 42 me 11u IPv4 0x1 0t0 TCP 127.0.0.1:5002 (LISTEN)
        acme 42 me 10u IPv4 0x1 0t0 TCP 127.0.0.1:5001 (LISTEN)
        acme 42 me 12u IPv6 0x1 0t0 TCP [::1]:5001 (LISTEN)
        """
        #expect(await servers(answering: lsof, asked: asked).ports(of: 42) == [5001, 5002])
        #expect(asked.argv == [["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "42"]])
    }

    @Test func `should name pgrep and lsof as the commands a local server runs`() {
        let process = LocalServerCall.Process(names: ["acme_server"])
        #expect(LocalServers(MacLocalServers(runner: MockCLIExecutor())).commands(for: process) == [
            ["/usr/bin/pgrep", "-a", "-lf", "acme_server"],
            ["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "{{pid}}"],
        ])
    }
}
#endif
