import Testing
import Providers
import DataSources
import Foundation
import Quotas

@Suite("Kimi API usage")
struct KimiAPIDefinitionParsingTests {

    // MARK: - Full Response Parsing

    @Test
    func `parseResponse extracts weekly and session quotas from valid response`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "2048",
                    "used": "214",
                    "remaining": "1834",
                    "resetTime": "2025-06-09T00:00:00.000Z"
                },
                "limits": [{
                    "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                    "detail": {
                        "limit": "200",
                        "used": "139",
                        "remaining": "61",
                        "resetTime": "2025-06-03T15:30:00.000Z"
                    }
                }]
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        #expect(snapshot.providerId == "kimi")
        #expect(snapshot.quotas.count == 2)

        // Weekly quota
        let weekly = snapshot.quota(for: .weekly)
        #expect(weekly != nil)
        #expect(weekly!.percentRemaining > 89.5)
        #expect(weekly!.percentRemaining < 89.6)
        #expect(weekly!.resetText == "214/2048 requests")
        #expect(weekly!.resetsAt != nil)

        // Session (rate limit) quota
        let session = snapshot.quota(for: .session)
        #expect(session != nil)
        #expect(session!.percentRemaining == 30.5)
        #expect(session!.resetText == "139/200 requests (5h)")
        #expect(session!.resetsAt != nil)
    }

    @Test
    func `parseResponse detects Moderato tier from weekly limit of 2048`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "2048",
                    "used": "100",
                    "remaining": "1948",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        #expect(snapshot.accountTier == .custom("Moderato"))
    }

    @Test
    func `parseResponse detects Andante tier from weekly limit of 1024`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "1024",
                    "used": "50",
                    "remaining": "974",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        #expect(snapshot.accountTier == .custom("Andante"))
    }

    @Test
    func `parseResponse detects Allegretto tier from weekly limit of 7168`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "7168",
                    "used": "500",
                    "remaining": "6668",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        #expect(snapshot.accountTier == .custom("Allegretto"))
    }

    @Test
    func `parseResponse returns nil tier for unknown weekly limit`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "500",
                    "used": "50",
                    "remaining": "450",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        #expect(snapshot.accountTier == nil)
    }

    // MARK: - Missing Limits Array

    @Test
    func `parseResponse handles missing limits array gracefully`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "2048",
                    "used": "214",
                    "remaining": "1834",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quota(for: .weekly) != nil)
        #expect(snapshot.quota(for: .session) == nil)
    }

    // MARK: - Missing used/remaining Fields

    @Test
    func `parseResponse handles missing used field by computing from limit and remaining`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "1000",
                    "remaining": "750",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        // Not one of the weekly plans: "Plan", with no guessed window.
        let weekly = snapshot.quota(for: .timeLimit("Plan"))!
        #expect(weekly.percentRemaining == 75.0)
        #expect(weekly.resetText == "250/1000 requests")
    }

    @Test
    func `parseResponse handles missing remaining field by computing from limit and used`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "1000",
                    "used": "300",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        // Not one of the weekly plans: "Plan", with no guessed window.
        let weekly = snapshot.quota(for: .timeLimit("Plan"))!
        #expect(weekly.percentRemaining == 70.0)
        #expect(weekly.resetText == "300/1000 requests")
    }

    @Test
    func `parseResponse shows no quota when neither used nor remaining is reported`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "2048",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        // Nothing reported is no quota, never a made-up 100% (the Left law).
        #expect(snapshot.quota(for: .weekly) == nil)
    }

    // MARK: - Reset Time Parsing

    @Test
    func `parseResponse parses ISO8601 with fractional seconds`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "1000",
                    "used": "100",
                    "remaining": "900",
                    "resetTime": "2025-06-09T12:30:45.123Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        // Not one of the weekly plans: "Plan", with no guessed window.
        let weekly = snapshot.quota(for: .timeLimit("Plan"))!
        #expect(weekly.resetsAt != nil)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = formatter.date(from: "2025-06-09T12:30:45.123Z")
        #expect(weekly.resetsAt == expected)
    }

    @Test
    func `parseResponse parses ISO8601 without fractional seconds`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "1000",
                    "used": "100",
                    "remaining": "900",
                    "resetTime": "2025-06-09T12:30:45Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        // Not one of the weekly plans: "Plan", with no guessed window.
        let weekly = snapshot.quota(for: .timeLimit("Plan"))!
        #expect(weekly.resetsAt != nil)
    }

    // MARK: - Error Cases

    @Test
    func `parseResponse throws parseFailed for invalid JSON`() throws {
        let json = "not json".data(using: .utf8)!

        #expect(throws: UsageError.self) {
            try KimiDefinitionFixtures.api(json, providerId: "kimi")
        }
    }

    @Test
    func `parseResponse throws parseFailed when FEATURE_CODING scope is missing`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CHAT",
                "detail": {
                    "limit": "1000",
                    "used": "100",
                    "remaining": "900",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        #expect(throws: UsageError.self) {
            try KimiDefinitionFixtures.api(json, providerId: "kimi")
        }
    }

    @Test
    func `parseResponse throws parseFailed for empty usages array`() throws {
        let json = """
        {
            "usages": []
        }
        """.data(using: .utf8)!

        #expect(throws: UsageError.self) {
            try KimiDefinitionFixtures.api(json, providerId: "kimi")
        }
    }

    // MARK: - Edge Cases

    @Test
    func `parseResponse shows no quota for a zero limit`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "0",
                    "used": "0",
                    "remaining": "0",
                    "resetTime": "2025-06-09T00:00:00Z"
                }
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        // A limit of 0 is nothing to show, never a made-up 100% (the Left law).
        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `parseResponse selects 5hour rate limit window`() throws {
        let json = """
        {
            "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                    "limit": "2048",
                    "used": "100",
                    "remaining": "1948",
                    "resetTime": "2025-06-09T00:00:00Z"
                },
                "limits": [
                    {
                        "window": { "duration": 60, "timeUnit": "TIME_UNIT_MINUTE" },
                        "detail": {
                            "limit": "50",
                            "used": "10",
                            "remaining": "40",
                            "resetTime": "2025-06-03T15:00:00Z"
                        }
                    },
                    {
                        "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                        "detail": {
                            "limit": "200",
                            "used": "80",
                            "remaining": "120",
                            "resetTime": "2025-06-03T15:30:00Z"
                        }
                    }
                ]
            }]
        }
        """.data(using: .utf8)!

        let snapshot = try KimiDefinitionFixtures.api(json, providerId: "kimi")

        let session = snapshot.quota(for: .session)!
        #expect(session.percentRemaining == 60.0)
        #expect(session.resetText == "80/200 requests (5h)")
    }
}
