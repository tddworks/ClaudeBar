import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

/// A worker reports a fact; the data source's `errors` says what it means.
@Suite
struct ErrorFactsTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func decode(_ errors: String, fetch: String = #"{"http":{"url":"https://acme.test/usage"}}"#) throws -> DataSourceDefinition {
        try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        {"kind":"api","fetch":\(fetch),"mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}},
         "errors":\(errors)}
        """.utf8))
    }

    private func make(_ definition: DataSourceDefinition, status: Int, headers: [String: String] = [:]) -> DataSource {
        let network = MockNetworkClient()
        let response = HTTPURLResponse(url: URL(string: "https://acme.test")!, statusCode: status, httpVersion: nil, headerFields: headers)!
        given(network).request(.any).willReturn((Data("{}".utf8), response))
        return DataSources.make(definition, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
                                makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { _ in nil },
                                homeDirectory: FileManager.default.temporaryDirectory, now: { Self.now })
    }

    private func reason(_ source: DataSource) async -> UsageError? {
        do {
            _ = try await source.fetchUsage()
            return nil
        } catch {
            return (error as? DataSourceError)?.reason
        }
    }

    @Test
    func `a status the definition names becomes the reason it says`() async throws {
        let source = make(try decode(#"{"http.404":"subscriptionRequired"}"#), status: 404)
        #expect(await reason(source) == .subscriptionRequired)
    }

    @Test
    func `http default covers every other status that is not an answer`() async throws {
        let source = make(try decode(#"{"http.default":{"executionFailed":"Acme is down"}}"#), status: 502)
        #expect(await reason(source) == .executionFailed("Acme is down"))
    }

    @Test
    func `a status no rule names keeps the worker's own wording`() async throws {
        let source = make(try decode(#"{"http.404":"noData"}"#), status: 500)
        #expect(await reason(source) == .executionFailed("HTTP error: 500"))
    }

    @Test
    func `a 429 stays a rate limit whatever the definition says`() async throws {
        let source = make(try decode(#"{"http.default":{"executionFailed":"busy"}}"#), status: 429, headers: ["Retry-After": "60"])
        #expect(await reason(source) == .rateLimited(retryAt: Self.now.addingTimeInterval(60)))
    }

    @Test
    func `a status the request accepts is an answer, not a failure`() async throws {
        let definition = try decode("{}", fetch: #"{"http":{"url":"https://acme.test/usage","acceptedStatuses":[200,404]}}"#)
        let source = make(definition, status: 404)
        let response = try await source.fetchResponse()
        #expect(response.status == 404)
    }

    @Test
    func `a 429 stays a rate limit even when a request lists it as accepted`() async throws {
        let definition = try decode("{}", fetch: #"{"http":{"url":"https://acme.test/usage","acceptedStatuses":[200,429]}}"#)
        let source = make(definition, status: 429, headers: ["Retry-After": "30"])
        #expect(await reason(source) == .rateLimited(retryAt: Self.now.addingTimeInterval(30)))
    }

    @Test(arguments: [#"{"http.429":"noData"}"#, #"{"http.abc":"noData"}"#, #"{"cli.exit":"noData"}"#])
    func `an unknown fact or a 429 rule is refused`(_ errors: String) {
        #expect(throws: DecodingError.self) { try decode(errors) }
    }

    @Test
    func `a CLI's facts are worded by their names`() async throws {
        let executor = MockCLIExecutor()
        given(executor).locate(.any).willReturn("/usr/local/bin/acme")
        given(executor).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "", exitCode: 3))
        let definition = try decode(#"{"cli.nonzero":{"sessionExpired":"Run acme login."}}"#, fetch: #"{"command":{"cli":"acme"}}"#)
        let source = DataSources.make(definition, providerId: "acme", cliExecutor: executor, network: MockNetworkClient(),
                                      makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { _ in nil },
                                      homeDirectory: FileManager.default.temporaryDirectory, now: { Self.now })

        #expect(await reason(source) == .sessionExpired(hint: "Run acme login."))
    }

    @Test
    func `errors round-trip by their names`() throws {
        let definition = try decode(#"{"http.404":"noData","cli.missing":{"cliNotFound":"acme"}}"#)
        #expect(definition.errors == [.httpStatus(404): .noData, .cliMissing: .cliNotFound("acme")])
        let again = try JSONDecoder().decode(DataSourceDefinition.self, from: JSONEncoder().encode(definition))
        #expect(again == definition)
    }
}
