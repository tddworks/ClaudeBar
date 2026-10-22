import Testing
import Foundation
@testable import Infrastructure

/// THE MINIMUM MCP: one JSON-RPC message in, one answer out. The handshake
/// echoes a version we serve, a notification earns silence, the tool table is
/// the route list read twice, and an unknown tool is a protocol error —
/// never a read.
@Suite
struct MCPKernelTests {

    private let info = MCPServerInfo(name: "claudebar", version: "9.9.9")

    /// Two stub tools: one plain, one taking `n`, so arguments are observable
    /// in the answer.
    private var tools: [MCPTool] {
        [
            MCPTool(name: "quota_status", description: "One line") { _ in
                "{\"status\": \"healthy\"}"
            },
            MCPTool(name: "usage_days", description: "Days") { arguments in
                "n=\(arguments?["n"]?.intValue ?? 30)"
            },
        ]
    }

    private func decode(_ body: Data) -> MCPInbound {
        MCPKernel.decode(body)
    }

    /// The request form of one method, with a string id.
    private func request(_ method: String, params: String = "{}") -> Data {
        Data(#"{"jsonrpc":"2.0","id":"a1","method":"\#(method)","params":\#(params)}"#.utf8)
    }

    private func result(_ reply: MCPReply) -> MCPValue? {
        if case let .result(value) = reply { return value }
        return nil
    }

    private func error(_ reply: MCPReply) -> (code: Int, message: String)? {
        if case let .error(code, message) = reply { return (code, message) }
        return nil
    }

    // MARK: - Decoding

    @Test func `should read a request with an id a method and params`() {
        let body = request("tools/call", params: #"{"name":"quota_status"}"#)

        guard case let .request(id, method, params) = decode(body) else {
            Issue.record("expected a request"); return
        }
        #expect(id == .string("a1"))
        #expect(method == "tools/call")
        #expect(params["name"]?.stringValue == "quota_status")
    }

    @Test func `should read a message without an id as a notification`() {
        let body = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)

        guard case let .notification(method) = decode(body) else {
            Issue.record("expected a notification"); return
        }
        #expect(method == "notifications/initialized")
    }

    @Test func `should read a null id as a notification`() {
        let body = Data(#"{"jsonrpc":"2.0","id":null,"method":"notifications/initialized"}"#.utf8)

        guard case let .notification(method) = decode(body) else {
            Issue.record("expected a notification"); return
        }
        #expect(method == "notifications/initialized")
    }

    @Test func `should default the params of a request that names none`() {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)

        guard case let .request(_, _, params) = decode(body) else {
            Issue.record("expected a request"); return
        }
        #expect(params == .emptyObject)
    }

    @Test func `should refuse a body that is not JSON as a parse error`() {
        let refusal = malformed(Data("nope".utf8))

        #expect(refusal?.code == MCPKernel.parseErrorCode)
        #expect(refusal?.message.contains("not JSON") == true)
    }

    @Test func `should refuse a batch as one invalid request`() {
        let batch = Data(#"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","id":2,"method":"ping"}]"#.utf8)

        let refusal = malformed(batch)

        #expect(refusal?.code == MCPKernel.invalidRequestCode)
        #expect(refusal?.message.contains("one JSON-RPC message") == true)
    }

    @Test func `should refuse a message without jsonrpc 2.0 or a method`() {
        #expect(malformed(Data(#"{"id":1,"method":"ping"}"#.utf8))?.code == MCPKernel.invalidRequestCode)
        #expect(malformed(Data(#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#.utf8))?.code == MCPKernel.invalidRequestCode)
        #expect(malformed(Data(#"{"jsonrpc":"2.0","id":1}"#.utf8))?.code == MCPKernel.invalidRequestCode)
    }

    /// The refusal a body earns, or `nil` when it decoded fine.
    private func malformed(_ body: Data) -> (code: Int, message: String)? {
        if case let .malformed(code, message) = decode(body) { return (code, message) }
        return nil
    }

    // MARK: - Handshake

    @Test func `should echo a protocol version it serves`() async {
        let body = request("initialize", params: #"{"protocolVersion":"2025-03-26"}"#)
        let inbound = MCPKernel.decode(body)

        guard case let .request(id, method, params) = inbound else {
            Issue.record("expected a request"); return
        }
        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(result(reply)?["protocolVersion"]?.stringValue == "2025-03-26")
    }

    @Test func `should answer its own protocol version to one it does not serve`() async {
        let body = request("initialize", params: #"{"protocolVersion":"1999-01-01"}"#)
        guard case let .request(id, method, params) = decode(body) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(result(reply)?["protocolVersion"]?.stringValue == MCPKernel.protocolVersion)
    }

    @Test func `should answer its own protocol version when none is asked`() async {
        guard case let .request(id, method, params) = decode(request("initialize")) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(result(reply)?["protocolVersion"]?.stringValue == MCPKernel.protocolVersion)
    }

    @Test func `should name itself with the tools capability in the handshake`() async {
        guard case let .request(id, method, params) = decode(request("initialize")) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)
        let value = result(reply)

        #expect(value?["serverInfo"]?["name"]?.stringValue == "claudebar")
        #expect(value?["serverInfo"]?["version"]?.stringValue == "9.9.9")
        #expect(value?["capabilities"]?["tools"] == .emptyObject)
    }

    @Test func `should answer a ping with an empty result`() async {
        guard case let .request(id, method, params) = decode(request("ping")) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(result(reply) == .emptyObject)
    }

    // MARK: - Tools

    @Test func `should list one tool per route with its schema`() async {
        guard case let .request(id, method, params) = decode(request("tools/list")) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)
        let listed = result(reply)?["tools"]?.elements ?? []

        #expect(listed.count == 2)
        #expect(listed[0]["name"]?.stringValue == "quota_status")
        #expect(listed[0]["description"]?.stringValue == "One line")
        #expect(listed[0]["inputSchema"] == .emptyObject)
        #expect(listed[1]["name"]?.stringValue == "usage_days")
    }

    @Test func `should answer a tool call with the payload as text content`() async {
        let body = request("tools/call", params: #"{"name":"quota_status"}"#)
        guard case let .request(id, method, params) = decode(body) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)
        let content = result(reply)?["content"]?.elements ?? []

        #expect(content.count == 1)
        #expect(content[0]["type"]?.stringValue == "text")
        #expect(content[0]["text"]?.stringValue == "{\"status\": \"healthy\"}")
    }

    @Test func `should pass the call's arguments to the tool`() async {
        let withArguments = request("tools/call", params: #"{"name":"usage_days","arguments":{"n":7}}"#)
        guard case let .request(id, method, params) = decode(withArguments) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(result(reply)?["content"]?.elements[0]["text"]?.stringValue == "n=7")
    }

    @Test func `should hand a tool call without arguments no arguments`() async {
        let bare = request("tools/call", params: #"{"name":"usage_days"}"#)
        guard case let .request(id, method, params) = decode(bare) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(result(reply)?["content"]?.elements[0]["text"]?.stringValue == "n=30")
    }

    @Test func `should refuse an unknown tool as invalid params`() async {
        let body = request("tools/call", params: #"{"name":"reboot_the_mac"}"#)
        guard case let .request(id, method, params) = decode(body) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(error(reply)?.code == MCPKernel.invalidParamsCode)
        #expect(error(reply)?.message.contains("reboot_the_mac") == true)
    }

    @Test func `should refuse a tool call without a name as invalid params`() async {
        let body = request("tools/call", params: "{}")
        guard case let .request(id, method, params) = decode(body) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(error(reply)?.code == MCPKernel.invalidParamsCode)
    }

    @Test func `should refuse a method it does not speak`() async {
        let body = request("resources/list")
        guard case let .request(id, method, params) = decode(body) else {
            Issue.record("expected a request"); return
        }

        let reply = await MCPKernel.handle(id: id, method: method, params: params, serverInfo: info, tools: tools)

        #expect(error(reply)?.code == MCPKernel.methodNotFoundCode)
        #expect(error(reply)?.message.contains("resources/list") == true)
    }

    // MARK: - JSON values

    @Test func `should round trip a value through its bytes`() {
        let value = MCPValue.object([
            "number": .number(42),
            "float": .number(0.5),
            "bool": .bool(true),
            "null": .null,
            "string": .string("héllo \"quoted\""),
            "array": .array([.string("a"), .number(1)]),
            "object": .object(["nested": .bool(false)]),
        ])

        #expect(MCPValue.parse(value.encoded()) == value)
    }

    @Test func `should read a boolean as a boolean never a number`() {
        let value = MCPValue.parse(Data(#"{"on":true,"off":false,"one":1}"#.utf8))

        #expect(value?["on"] == .bool(true))
        #expect(value?["off"] == .bool(false))
        #expect(value?["one"] == .number(1))
    }

    @Test func `should read a whole number exactly`() {
        let value = MCPValue.parse(Data(#"{"n":7,"half":3.5}"#.utf8))

        #expect(value?["n"]?.intValue == 7)
        #expect(value?["half"]?.intValue == nil)
    }

    @Test func `should find a pair by key on an object and nowhere else`() {
        let value = MCPValue.parse(Data(#"{"a":{"b":1}}"#.utf8))

        #expect(value?["a"]?["b"]?.intValue == 1)
        #expect(value?["a"]?["missing"] == nil)
        #expect(value?["b"] == nil)
        #expect(MCPValue.string("a")["a"] == nil)
        #expect(MCPValue.number(1)["a"] == nil)
    }

    @Test func `should refuse bytes that are not JSON`() {
        #expect(MCPValue.parse(Data("<html>".utf8)) == nil)
    }

    @Test func `should write an array of numbers as one line with sorted keys`() {
        let value = MCPValue.object(["b": .number(1), "a": .array([.number(2)])])

        #expect(String(decoding: value.encoded(), as: UTF8.self) == #"{"a":[2],"b":1}"#)
    }
}

extension MCPValue {
    /// The value's array, or empty — how a test reads a listed set.
    var elements: [MCPValue] {
        if case let .array(values) = self { return values }
        return []
    }
}
