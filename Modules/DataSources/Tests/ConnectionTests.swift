import Foundation
import Testing
@testable import DataSources

/// Each fetch case answers for itself: where it may send a key, what it runs.
@Suite
struct ConnectionTests {
    @Test
    func `an http fetch names its url and runs nothing`() {
        let fetch = Fetch.http(HTTPRequest(url: "https://acme.test/usage"))
        #expect(fetch.connection.urls == ["https://acme.test/usage"])
        #expect(fetch.connection.commands.isEmpty)
    }

    @Test
    func `http steps name every step's url`() {
        let fetch = Fetch.httpSteps(HTTPSteps(steps: [
            HTTPStep(name: "a", request: HTTPRequest(url: "https://a.test")),
            HTTPStep(name: "b", request: HTTPRequest(url: "https://b.test")),
        ]))
        #expect(fetch.connection.urls == ["https://a.test", "https://b.test"])
    }

    @Test
    func `a command, a terminal cli and json-rpc name the argv they run`() {
        #expect(Fetch.command(CommandCall(cli: "acme", args: ["usage"])).connection.commands == [["acme", "usage"]])
        #expect(Fetch.cli(CLICall(cli: "acme", args: ["--tui"])).connection.commands == [["acme", "--tui"]])
        #expect(Fetch.jsonRpc(JSONRPCCall(cli: "acme", args: ["serve"], call: "usage")).connection.commands == [["acme", "serve"]])
    }

    @Test
    func `the CLI location replaces only the CLI it names`() {
        let fetch = Fetch.command(CommandCall(cli: "acme", args: ["usage"]))
        #expect(fetch.runningCLI("acme", at: "/opt/acme") == .command(CommandCall(cli: "/opt/acme", args: ["usage"])))
        #expect(fetch.runningCLI("other", at: "/opt/other") == fetch)
        #expect(Fetch.file(FileCall(path: "~/x")).runningCLI("acme", at: "/opt/acme") == .file(FileCall(path: "~/x")))
    }
}
