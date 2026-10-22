import Testing
import Foundation
@testable import Infrastructure

/// The wire's edge: raw bytes become a request value or a named refusal, an
/// answer value becomes bytes a client can read. The caps live here, so they
/// are guarded here.
@Suite
struct HTTPRequestTests {

    // MARK: - Parsing

    @Test func `should parse a GET into method path query headers and no body`() throws {
        let head = Data("GET /usage/days?n=7&flags HTTP/1.1\r\nHost: 127.0.0.1:19848\r\nAccept: application/json\r\n\r\n".utf8)

        let request = try HTTPRequestParser.parse(headerBlock: head, body: Data())

        #expect(request.method == "GET")
        #expect(request.path == "/usage/days")
        #expect(request.query == ["n": "7", "flags": ""])
        #expect(request.header("HOST") == "127.0.0.1:19848")
        #expect(request.headers["accept"] == "application/json")
        #expect(request.body.isEmpty)
    }

    @Test func `should keep the first of repeated headers under one lowercased name`() throws {
        let head = Data("GET / HTTP/1.1\r\nX-Trace: first\r\nx-trace: second\r\n\r\n".utf8)

        let request = try HTTPRequestParser.parse(headerBlock: head, body: Data())

        #expect(request.header("x-trace") == "first")
    }

    @Test func `should parse a POST with the body the server accumulated`() throws {
        let head = Data("POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\n\r\n".utf8)
        let body = Data(#"{"jsonrpc":"2.0"}"#.utf8)

        let request = try HTTPRequestParser.parse(headerBlock: head, body: body)

        #expect(request.method == "POST")
        #expect(request.path == "/mcp")
        #expect(request.body == body)
    }

    @Test func `should refuse a request line that is not method target version`() {
        #expect(throws: HTTPParseError.malformed) {
            try HTTPRequestParser.parse(headerBlock: Data("GARBAGE\r\n\r\n".utf8), body: Data())
        }
    }

    @Test func `should refuse a target that does not start with a slash`() {
        #expect(throws: HTTPParseError.malformed) {
            try HTTPRequestParser.parse(headerBlock: Data("GET nope HTTP/1.1\r\n\r\n".utf8), body: Data())
        }
    }

    @Test func `should refuse a header line without a colon`() {
        #expect(throws: HTTPParseError.malformed) {
            try HTTPRequestParser.parse(headerBlock: Data("GET / HTTP/1.1\r\nBadHeader\r\n\r\n".utf8), body: Data())
        }
    }

    @Test func `should refuse anything but HTTP/1.x`() {
        #expect(throws: HTTPParseError.unsupportedProtocol) {
            try HTTPRequestParser.parse(headerBlock: Data("GET / HTTP/2\r\n\r\n".utf8), body: Data())
        }
    }

    @Test func `should refuse a chunked body`() {
        let head = Data("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)

        #expect(throws: HTTPParseError.chunkedUnsupported) {
            try HTTPRequestParser.parse(headerBlock: head, body: Data())
        }
    }

    @Test func `should refuse a body over the cap`() {
        let head = Data("POST /mcp HTTP/1.1\r\n\r\n".utf8)
        let body = Data(count: HTTPRequestParser.maxBodyBytes + 1)

        #expect(throws: HTTPParseError.oversized) {
            try HTTPRequestParser.parse(headerBlock: head, body: body)
        }
    }

    @Test func `should want no body when the header block names no length`() {
        let head = Data("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)

        #expect(HTTPRequestParser.pendingBodyLength(headerBlockPrefix: head) == 0)
    }

    @Test func `should read the wanted body length from content length`() {
        let head = Data("POST /mcp HTTP/1.1\r\nContent-Length: 42\r\n\r\n".utf8)

        #expect(HTTPRequestParser.pendingBodyLength(headerBlockPrefix: head) == 42)
    }

    @Test func `should want nothing while the header block is still arriving`() {
        let partial = Data("POST /mcp HTTP/1.1\r\nContent-Length: 42\r\n".utf8)

        #expect(HTTPRequestParser.pendingBodyLength(headerBlockPrefix: partial) == nil)
    }

    @Test func `should call a header block over the cap while it is still arriving`() {
        let accumulated = Data(count: HTTPRequestParser.maxHeaderBytes + 1)

        #expect(HTTPRequestParser.isHeaderOverCap(accumulated))
    }

    @Test func `should not refuse a finished header block however large it was`() {
        let finished = Data(count: HTTPRequestParser.maxHeaderBytes + 1) + Data("GET / HTTP/1.1\r\n\r\n".utf8)

        #expect(!HTTPRequestParser.isHeaderOverCap(finished))
    }

    // MARK: - Serializing

    @Test func `should write the status line the headers the blank line and the body`() {
        let response = HTTPResponse(status: 404, headers: ["Allow": "GET"], body: Data("nope".utf8))

        let text = String(decoding: HTTPResponseSerializer.serialize(response), as: UTF8.self)

        #expect(text.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        #expect(text.contains("Allow: GET\r\n"))
        #expect(text.contains("Content-Length: 4\r\n"))
        #expect(text.contains("Content-Type: application/json; charset=utf-8\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\nnope"))
    }

    @Test func `should write no content type for an empty body`() {
        let response = HTTPResponse(status: 202)

        let text = String(decoding: HTTPResponseSerializer.serialize(response), as: UTF8.self)

        #expect(text.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
        #expect(text.contains("Content-Length: 0\r\n"))
        #expect(!text.contains("Content-Type"))
    }

    @Test func `should keep a content type the response named itself`() {
        let response = HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("hi".utf8))

        let text = String(decoding: HTTPResponseSerializer.serialize(response), as: UTF8.self)

        #expect(text.contains("Content-Type: text/plain\r\n"))
        #expect(!text.contains("application/json"))
    }

    @Test func `should name the reason phrase of the statuses this surface sends`() {
        #expect(HTTPResponseSerializer.reasonPhrase(200) == "OK")
        #expect(HTTPResponseSerializer.reasonPhrase(202) == "Accepted")
        #expect(HTTPResponseSerializer.reasonPhrase(400) == "Bad Request")
        #expect(HTTPResponseSerializer.reasonPhrase(404) == "Not Found")
        #expect(HTTPResponseSerializer.reasonPhrase(405) == "Method Not Allowed")
        #expect(HTTPResponseSerializer.reasonPhrase(413) == "Payload Too Large")
        #expect(HTTPResponseSerializer.reasonPhrase(505) == "HTTP Version Not Supported")
        #expect(HTTPResponseSerializer.reasonPhrase(418) == "Status")
    }

    @Test func `should shape every answer with a body as one JSON object`() throws {
        let answer = HTTPResponse.json(["error": "not found"], status: 404)

        #expect(answer.status == 404)
        let value = try #require(JSONSerialization.jsonObject(with: answer.body) as? [String: String])
        #expect(value == ["error": "not found"])
    }

    @Test func `should shape a refusal as one error object with the message quoted`() throws {
        let refusal = HTTPResponse.error(405, "method \"not allowed\"")

        #expect(refusal.status == 405)
        let value = try #require(JSONSerialization.jsonObject(with: refusal.body) as? [String: String])
        #expect(value["error"] == "method \"not allowed\"")
    }
}
