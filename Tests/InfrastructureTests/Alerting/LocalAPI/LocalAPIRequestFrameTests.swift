import Testing
import Foundation
@testable import Infrastructure

/// The bytes a connection has delivered so far, read as one request: still
/// arriving, whole, refused, or abandoned. The server only moves bytes; every
/// rule about when a request is whole lives here, so it is tested here.
@Suite
struct LocalAPIRequestFrameTests {

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    @Test func `should wait for more while the header block is still arriving`() {
        let step = LocalAPIRequestFrame.read(bytes("GET /status HTTP/1.1\r\nHost: 127.0.0.1"), peerDone: false)

        #expect(step == .needMore)
    }

    @Test func `should hand over a GET once its blank line arrives`() throws {
        let step = LocalAPIRequestFrame.read(bytes("GET /status HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"), peerDone: false)

        guard case .whole(.request(let request)) = step else { Issue.record("not whole: \(step)"); return }
        #expect(request.method == "GET")
        #expect(request.path == "/status")
        #expect(request.body.isEmpty)
    }

    @Test func `should wait for the body its Content-Length promises`() {
        let step = LocalAPIRequestFrame.read(bytes("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\":"), peerDone: false)

        #expect(step == .needMore)
    }

    @Test func `should hand over the body its Content-Length promises, and nothing after it`() {
        let step = LocalAPIRequestFrame.read(bytes("POST /mcp HTTP/1.1\r\nContent-Length: 7\r\n\r\n{\"a\":1}trailing"), peerDone: false)

        guard case .whole(.request(let request)) = step else { Issue.record("not whole: \(step)"); return }
        #expect(String(decoding: request.body, as: UTF8.self) == "{\"a\":1}")
    }

    @Test func `should refuse a header block over the cap without waiting for its end`() {
        let huge = "GET / HTTP/1.1\r\nX-Pad: " + String(repeating: "a", count: LocalAPIRequestParser.maxHeaderBytes + 1)

        let step = LocalAPIRequestFrame.read(bytes(huge), peerDone: false)

        #expect(step == .whole(.failed(.oversized)))
    }

    @Test func `should refuse a body it promises over the cap before it arrives`() {
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: \(LocalAPIRequestParser.maxBodyBytes + 1)\r\n\r\n"

        let step = LocalAPIRequestFrame.read(bytes(head), peerDone: false)

        #expect(step == .whole(.failed(.oversized)))
    }

    @Test func `should refuse a Content-Length it cannot read, not wait on it`() {
        let step = LocalAPIRequestFrame.read(bytes("POST /mcp HTTP/1.1\r\nContent-Length: lots\r\n\r\n"), peerDone: false)

        #expect(step == .whole(.failed(.malformed)))
    }

    @Test func `should give up on a peer that hung up before one whole request`() {
        let step = LocalAPIRequestFrame.read(bytes("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\":"), peerDone: true)

        #expect(step == .abandoned)
    }

    @Test func `should still serve a request that arrived whole with the peer's last bytes`() {
        let step = LocalAPIRequestFrame.read(bytes("GET /status HTTP/1.1\r\n\r\n"), peerDone: true)

        guard case .whole(.request) = step else { Issue.record("not whole: \(step)"); return }
    }
}
