import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct MistralAPIUsageProbeParsingTests {

    static let sampleNDJSON = """
    {"json":{"0":[[0],[null,0,0]],"1":[[0],[null,0,1]],"2":[[0],[null,0,2]]}}
    {"json":[0,0,[[{"result":0}],["result",0,3]]]}
    {"json":[3,0,[[{"data":0}],["data",0,4]]]}
    {"json":[4,0,[[{"items":[],"nextCursor":null}]]]}
    {"json":[2,0,[[{"result":0}],["result",0,5]]]}
    {"json":[5,0,[[{"data":0}],["data",0,6]]]}
    {"json":[6,0,[[{"usagePercentage":0.6716472134615384,"quotaChangedThisMonth":false,"paygEnabled":false,"resetAt":"2026-07-01T00:00:00Z"}]]]}
    {"json":[1,0,[[{"result":0}],["result",0,7]]]}
    {"json":[7,0,[[{"data":0}],["data",0,8]]]}
    {"json":[8,0,[[{"vibeApiKey":"xxxx","vibeApiKeyId":"d86364c4-29e6-4a67-a760-84039900aaf1"}]]}
    """

    /// 99.7% used (0-100 scale) = nearly exhausted
    static let sampleNearLimit = """
    {"json":{"0":[[0],[null,0,0]],"1":[[0],[null,0,1]],"2":[[0],[null,0,2]]}}
    {"json":[0,0,[[{"result":0}],["result",0,3]]]}
    {"json":[3,0,[[{"data":0}],["data",0,4]]]}
    {"json":[4,0,[[{"items":[],"nextCursor":null}]]]}
    {"json":[2,0,[[{"result":0}],["result",0,5]]]}
    {"json":[5,0,[[{"data":0}],["data",0,6]]]}
    {"json":[6,0,[[{"usagePercentage":99.7,"quotaChangedThisMonth":false}]]]}
    {"json":[1,0,[[{"result":0}],["result",0,7]]]}
    {"json":[7,0,[[{"data":0}],["data",0,8]]]}
    {"json":[8,0,[[{"vibeApiKey":"sk-test"}]]}
    """

    static let sampleNoUsagePct = """
    {"json":[0,0,[[{"result":0}],["result",0]]]}
    {"json":[8,0,[[{"vibeApiKey":"sk-foo"}]]}
    """

    static let sampleErrorResponse = """
    {"json":{"0":[[0],[null,0,0]],"1":[[0],[null,0,1]]}}
    {"json":[0,0,[[{"result":0}],["result",0,3]]]}
    {"json":[3,0,[[{"data":0}],["data",0,4]]]}
    {"json":[4,0,[[{"error":"Unauthorized"}]]]}
    """

    // MARK: - Parsing Tests

    @Test
    func `parses usagePercentage from NDJSON response`() throws {
        let data = Data(Self.sampleNDJSON.utf8)
        let snapshot = try MistralAPIUsageProbe.parseResponse(data, providerId: "mistral")

        #expect(snapshot.providerId == "mistral")
        #expect(snapshot.quotas.count == 1)

        let quota = snapshot.quotas[0]
        #expect(quota.quotaType == .timeLimit("Monthly"))

        // usagePercentage is 0-100 scale: 0.6716% used → ~99.33% remaining
        #expect(quota.percentRemaining == 99.32835278653846)
        #expect(quota.resetText == "99% remaining")
    }

    @Test
    func `parses resetsAt from resetAt field`() throws {
        let data = Data(Self.sampleNDJSON.utf8)
        let snapshot = try MistralAPIUsageProbe.parseResponse(data, providerId: "mistral")

        let resetsAt = snapshot.quotas[0].resetsAt
        #expect(resetsAt != nil)
        if let resetsAt {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = calendar.dateComponents([.year, .month, .day], from: resetsAt)
            #expect(components.year == 2026)
            #expect(components.month == 7)
            #expect(components.day == 1)
        }
    }

    @Test
    func `parses usagePercentage near limit`() throws {
        let data = Data(Self.sampleNearLimit.utf8)
        let snapshot = try MistralAPIUsageProbe.parseResponse(data, providerId: "mistral")

        #expect(snapshot.quotas.count == 1)
        let quota = snapshot.quotas[0]

        // 99.7% used → 0.2999...% remaining
        #expect(quota.percentRemaining < 0.31)
        #expect(quota.percentRemaining > 0.29)
        #expect(quota.resetText == "0% remaining")
    }

    @Test
    func `throws noData when usagePercentage is missing`() throws {
        let data = Data(Self.sampleNoUsagePct.utf8)

        #expect(throws: ProbeError.noData) {
            try MistralAPIUsageProbe.parseResponse(data, providerId: "mistral")
        }
    }

    @Test
    func `throws parseFailed on invalid JSON`() throws {
        let data = Data("not json".utf8)

        var caughtError: ProbeError?
        do {
            _ = try MistralAPIUsageProbe.parseResponse(data, providerId: "mistral")
        } catch let error as ProbeError {
            caughtError = error
        }
        #expect(caughtError != nil)
        if case .parseFailed = caughtError {
            // expected
        } else {
            Issue.record("Expected parseFailed but got \(String(describing: caughtError))")
        }
    }

    @Test
    func `throws executionFailed on error response`() throws {
        let data = Data(Self.sampleErrorResponse.utf8)

        var caughtError: ProbeError?
        do {
            _ = try MistralAPIUsageProbe.parseResponse(data, providerId: "mistral")
        } catch let error as ProbeError {
            caughtError = error
        }
        #expect(caughtError != nil)
        if case .executionFailed(let message) = caughtError {
            #expect(message.contains("Unauthorized"))
        } else {
            Issue.record("Expected executionFailed but got \(String(describing: caughtError))")
        }
    }
}
