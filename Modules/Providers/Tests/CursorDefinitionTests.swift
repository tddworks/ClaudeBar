import Foundation
import Testing
import Providers
@testable import DataSources
import Quotas
import Mockable
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


/// Cursor as data: the Cursor app's own login read from its database (or an
/// added account's saved token), the user id taken from the token's `sub`
/// claim, and `cursor-usage.js` — the old probe's responses, quota for quota.
@MainActor @Suite("Cursor definition")
struct CursorDefinitionTests {
    private final class CookieCapture: @unchecked Sendable {
        let lock=NSLock(); private var value:String?
        func set(_ value:String?) { lock.lock(); defer {lock.unlock()}; self.value=value }
        func get() -> String? { lock.lock(); defer {lock.unlock()}; return value }
    }
    /// Adds a login by its token, then refreshes it — asked of its provider.
    private func refreshAdded(_ data:Data, token:String, capture:CookieCapture = CookieCapture()) async throws -> UsageSnapshot {
        let definition=try ProviderFactory.builtIn("cursor"), vault=MemoryVault(), network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            #expect(request.url?.absoluteString == "https://cursor.com/api/usage-summary")
            #expect(request.httpMethod == "GET" && request.timeoutInterval == 15)
            capture.set(request.value(forHTTPHeaderField:"Cookie"))
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        let provider=Provider(definition:definition,settings:InMemoryProviderSettings(),makeDataSource:{ source,login in
            DataSources.make(source,providerId:"cursor",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,secrets:vault.scoped(to:login),environment:{_ in nil},homeDirectory:FileManager.default.temporaryDirectory,now:{Date()})
        },vault:vault)
        let added = try provider.accounts.add(filling:["accessToken":token])
        return try await provider.refresh(added)
    }
    private func parse(_ data:Data) async throws -> UsageSnapshot {
        try await refreshAdded(data,token:"header.eyJzdWIiOiJmaXh0dXJlLXVzZXIifQ.signature")
    }
    private func userID(_ token:String) async throws -> String {
        let capture=CookieCapture()
        _ = try await refreshAdded(Data(#"{"isUnlimited":true}"#.utf8),token:token,capture:capture)
        let cookie=try #require(capture.get())
        #expect(cookie.hasPrefix("WorkosCursorSessionToken="))
        #expect(cookie.hasSuffix("::"+token))
        return String(cookie.dropFirst("WorkosCursorSessionToken=".count).dropLast(token.count+2))
    }


    // MARK: - Real API Response

    @Test
    func `should show an Ultra plan's monthly requests, then its Auto and API pools on the billing cycle`() async throws {
        // Actual response from cursor.com/api/usage-summary
        let json = """
        {
            "billingCycleStart": "2026-02-06T03:34:49.000Z",
            "billingCycleEnd": "2026-03-06T03:34:49.000Z",
            "membershipType": "ultra",
            "limitType": "user",
            "isUnlimited": false,
            "autoModelSelectedDisplayMessage": "You've used 1% of your included total usage",
            "namedModelSelectedDisplayMessage": "You've used 1% of your included API usage",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 326,
                    "limit": 40000,
                    "remaining": 39674,
                    "breakdown": { "included": 40000, "bonus": 0, "total": 40000 },
                    "autoPercentUsed": 0.033,
                    "apiPercentUsed": 0.586,
                    "totalPercentUsed": 0.815
                },
                "onDemand": {
                    "enabled": false,
                    "used": 0,
                    "limit": null,
                    "remaining": null
                }
            },
            "teamUsage": {}
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.providerId.hasPrefix("cursor."))
        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.accountTier == .custom("ULTRA"))

        let monthly = snapshot.quotas[0]
        #expect(monthly.quotaType == .timeLimit("Monthly"))
        #expect(monthly.quotaType.quotaKey == "time:Monthly")
        #expect(abs(monthly.percentRemaining - 99.185) < 0.01)
        #expect(monthly.resetText == "326/40000 requests")
        #expect(monthly.resetsAt != nil)
        #expect(monthly.windowDuration == nil)

        let auto = snapshot.quotas[1]
        #expect(auto.quotaType == .timeLimit("Auto"))
        #expect(abs(auto.percentRemaining - 99.967) < 0.01)
        #expect(auto.resetText == nil)
        #expect(auto.resetsAt == monthly.resetsAt)
        #expect(auto.windowDuration == TimeInterval(28 * 24 * 3600))

        let api = snapshot.quotas[2]
        #expect(api.quotaType == .timeLimit("API"))
        #expect(abs(api.percentRemaining - 99.414) < 0.01)
        #expect(api.resetText == nil)
        #expect(api.resetsAt == monthly.resetsAt)
        #expect(api.windowDuration == TimeInterval(28 * 24 * 3600))
    }

    // MARK: - Plan Usage

    @Test
    func `should show a Pro plan's monthly requests used out of its limit`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "billingCycleEnd": "2025-02-01T00:00:00Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123,
                    "limit": 500,
                    "remaining": 377
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.providerId.hasPrefix("cursor."))
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.accountTier == .custom("PRO"))

        let quota = snapshot.quotas[0]
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(abs(quota.percentRemaining - 75.4) < 0.1)
        #expect(quota.resetText == "123/500 requests")
        #expect(quota.resetsAt != nil)
    }

    @Test
    func `should show on-demand spend beside the monthly requests when on-demand is enabled`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 400,
                    "limit": 500,
                    "remaining": 100
                },
                "onDemand": {
                    "enabled": true,
                    "used": 25,
                    "limit": 100,
                    "remaining": 75
                }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 2)

        let plan = snapshot.quotas.first { $0.quotaType == .timeLimit("Monthly") }
        #expect(plan != nil)
        #expect(abs(plan!.percentRemaining - 20.0) < 0.1)
        #expect(plan!.resetText == "400/500 requests")

        let onDemand = snapshot.quotas.first { $0.quotaType == .timeLimit("On-Demand") }
        #expect(onDemand != nil)
        #expect(abs(onDemand!.percentRemaining - 75.0) < 0.1)
    }

    @Test
    func `should show no requests left when the plan is used up`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 500,
                    "limit": 500,
                    "remaining": 0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 0)
        #expect(snapshot.quotas[0].resetText == "500/500 requests")
    }

    @Test
    func `should measure a Pro plan with bonus credits against its whole capacity, not show it empty`() async throws {
        // Regression: a Pro user with bonus credits. The `used`/`limit` fields describe
        // only the *included* base (2000/2000 = maxed), but `breakdown.total` shows the
        // real capacity (9770 incl. 7770 bonus) and `totalPercentUsed` shows true usage
        // (28.32%). The old logic derived percentRemaining from used/limit -> 0% -> EMPTY.
        // Correct behavior: ~71.68% remaining, NOT depleted.
        let json = """
        {
            "billingCycleStart": "2026-06-25T03:47:17.000Z",
            "billingCycleEnd": "2026-07-25T03:47:17.000Z",
            "membershipType": "pro",
            "limitType": "user",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 2000,
                    "limit": 2000,
                    "remaining": 0,
                    "breakdown": { "included": 2000, "bonus": 7770, "total": 9770 },
                    "autoPercentUsed": 23.05,
                    "apiPercentUsed": 63.44,
                    "totalPercentUsed": 28.32
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            },
            "teamUsage": {}
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 3)
        let monthly = snapshot.quotas[0]
        #expect(monthly.quotaType == .timeLimit("Monthly"))
        // 28.32% used of the full 9770 capacity -> 71.68% remaining (was incorrectly 0)
        #expect(abs(monthly.percentRemaining - 71.68) < 0.1)
        #expect(monthly.resetText == "2767/9770 requests")
        #expect(monthly.resetsAt != nil)
        #expect(monthly.windowDuration == nil)

        let auto = snapshot.quotas[1]
        #expect(auto.quotaType == .timeLimit("Auto"))
        #expect(abs(auto.percentRemaining - 76.95) < 0.1)
        #expect(auto.resetText == nil)
        #expect(auto.resetsAt == monthly.resetsAt)
        #expect(auto.windowDuration == TimeInterval(30 * 24 * 3600))

        let api = snapshot.quotas[2]
        #expect(api.quotaType == .timeLimit("API"))
        #expect(abs(api.percentRemaining - 36.56) < 0.1)
        #expect(api.resetText == nil)
        #expect(api.windowDuration == TimeInterval(30 * 24 * 3600))
    }

    @Test
    func `should show no requests left, not below zero, when usage is over the limit`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 550,
                    "limit": 500,
                    "remaining": -50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 0)
    }

    // MARK: - Unlimited & Special Cases

    @Test
    func `should show the plan and no made-up 100% when the plan is unlimited`() async throws {
        let json = """
        {
            "membershipType": "business",
            "isUnlimited": true,
            "individualUsage": {
                "plan": { "enabled": false },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        // No ceiling, so no quota — the plan, and no made-up 100% (the Left law).
        #expect(snapshot.quotas.isEmpty)
        #expect(snapshot.accountTier == .custom("BUSINESS"))
    }

    @Test
    func `should show a free plan's monthly requests left`() async throws {
        let json = """
        {
            "membershipType": "free",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 30,
                    "limit": 50,
                    "remaining": 20
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.accountTier == .custom("FREE"))
        #expect(snapshot.quotas.count == 1)
        #expect(abs(snapshot.quotas[0].percentRemaining - 40.0) < 0.1)
    }

    // MARK: - Enterprise Plan

    @Test
    func `should show an Enterprise plan's monthly, Auto and API pools and the team's on-demand credits`() async throws {
        let json = """
        {
            "billingCycleStart": "2026-03-01T00:00:00.000Z",
            "billingCycleEnd": "2026-04-01T00:00:00.000Z",
            "membershipType": "enterprise",
            "limitType": "team",
            "isUnlimited": false,
            "autoModelSelectedDisplayMessage": "You've used 7% of your included total usage",
            "namedModelSelectedDisplayMessage": "You've used 7% of your included API usage",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 0,
                    "limit": 0,
                    "remaining": 0,
                    "breakdown": {
                        "included": 0,
                        "bonus": 300,
                        "total": 300
                    },
                    "autoPercentUsed": 0,
                    "apiPercentUsed": 6.9,
                    "totalPercentUsed": 6.9
                },
                "onDemand": {
                    "enabled": false,
                    "used": 0,
                    "limit": 0,
                    "remaining": 0
                }
            },
            "teamUsage": {
                "onDemand": {
                    "enabled": true,
                    "used": 0,
                    "limit": 10000,
                    "remaining": 10000
                }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.providerId.hasPrefix("cursor."))
        #expect(snapshot.accountTier == .custom("ENTERPRISE"))

        // Monthly + Auto (integer 0) + API + team on-demand
        #expect(snapshot.quotas.count == 4)
        #expect(snapshot.quotas.map(\.quotaType) == [
            .timeLimit("Monthly"), .timeLimit("Auto"), .timeLimit("API"), .timeLimit("Team"),
        ])

        let monthly = snapshot.quotas[0]
        // 6.9% used of 300 -> ~93.1% remaining
        #expect(abs(monthly.percentRemaining - 93.1) < 0.5)
        #expect(monthly.resetText != nil)
        #expect(monthly.windowDuration == nil)

        let auto = snapshot.quotas[1]
        #expect(auto.percentRemaining == 100)
        #expect(auto.resetText == nil)
        #expect(auto.resetsAt == monthly.resetsAt)
        #expect(auto.windowDuration == TimeInterval(31 * 24 * 3600))

        let api = snapshot.quotas[2]
        #expect(abs(api.percentRemaining - 93.1) < 0.5)
        #expect(api.resetText == nil)
        #expect(api.windowDuration == TimeInterval(31 * 24 * 3600))

        let teamQuota = snapshot.quotas[3]
        #expect(teamQuota.percentRemaining == 100.0)
        #expect(teamQuota.resetText == "0/10000 team credits")
    }

    @Test
    func `should measure an Enterprise member's requests against the plan's whole capacity when no limit is given`() async throws {
        let json = """
        {
            "membershipType": "enterprise",
            "limitType": "team",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 0,
                    "limit": 0,
                    "remaining": 0,
                    "breakdown": {
                        "included": 0,
                        "bonus": 184,
                        "total": 184
                    },
                    "totalPercentUsed": 50.0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": 0, "remaining": 0 }
            },
            "teamUsage": {
                "onDemand": { "enabled": false, "used": 0, "limit": 0, "remaining": 0 }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        let quota = snapshot.quotas[0]
        #expect(quota.quotaType == .timeLimit("Monthly"))
        // 50% used -> 50% remaining
        #expect(abs(quota.percentRemaining - 50.0) < 0.5)
    }

    // MARK: - Error Cases

    @Test
    func `should fail when Cursor answers with nothing`() async {
        let json = "{}".data(using: .utf8)!

        await #expect(throws: UsageError.self) {
            try await parse(json)
        }
    }

    @Test
    func `should fail when Cursor answers with something that isn't JSON`() async {
        let json = "not json".data(using: .utf8)!

        await #expect(throws: UsageError.self) {
            try await parse(json)
        }
    }

    @Test
    func `should fail when Cursor reports no personal usage for a plan that isn't unlimited`() async {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false
        }
        """.data(using: .utf8)!

        await #expect(throws: UsageError.self) {
            try await parse(json)
        }
    }

    // MARK: - Billing Cycle

    @Test
    func `should know the reset when the billing cycle end has fractional seconds`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "billingCycleEnd": "2025-03-01T00:00:00.000Z",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)
        #expect(snapshot.quotas[0].resetsAt != nil)
    }

    @Test
    func `should know the reset when the billing cycle end has whole seconds`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "billingCycleEnd": "2025-03-01T00:00:00Z",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)
        #expect(snapshot.quotas[0].resetsAt != nil)
    }

    // MARK: - Auto / API pool percents

    @Test
    func `should show one monthly window when Cursor reports only the total`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "2026-01-01T00:00:00.000Z",
            "billingCycleEnd": "2026-02-01T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400,
                    "totalPercentUsed": 20
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .timeLimit("Monthly"))
        #expect(snapshot.quotas[0].quotaType.quotaKey == "time:Monthly")
        #expect(abs(snapshot.quotas[0].percentRemaining - 80) < 0.01)
        #expect(snapshot.quotas[0].resetText == "100/500 requests")
    }

    @Test
    func `should show the Auto and API pools full when nothing of them is used`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "2026-01-01T00:00:00.000Z",
            "billingCycleEnd": "2026-01-31T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 0,
                    "limit": 500,
                    "remaining": 500,
                    "autoPercentUsed": 0,
                    "apiPercentUsed": 0,
                    "totalPercentUsed": 0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[1].quotaType == .timeLimit("Auto"))
        #expect(snapshot.quotas[1].percentRemaining == 100)
        #expect(snapshot.quotas[2].quotaType == .timeLimit("API"))
        #expect(snapshot.quotas[2].percentRemaining == 100)
        #expect(snapshot.quotas[1].windowDuration == TimeInterval(30 * 24 * 3600))
    }

    @Test
    func `should show no Auto or API pool when Cursor leaves their share empty`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 50,
                    "limit": 100,
                    "remaining": 50,
                    "autoPercentUsed": null,
                    "apiPercentUsed": null,
                    "totalPercentUsed": 50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .timeLimit("Monthly"))
        #expect(snapshot.quotas[0].percentRemaining == 50)
    }

    @Test
    func `should show no Auto or API pool when their share isn't a number`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 50,
                    "limit": 100,
                    "remaining": 50,
                    "autoPercentUsed": "high",
                    "apiPercentUsed": [],
                    "totalPercentUsed": 50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .timeLimit("Monthly"))
    }

    @Test
    func `should show no Auto or API pool when their share is true or false`() async throws {
        // JSON true/false are CFBoolean and must not become 1.0 / 0.0. Integer 0
        // still has to produce a card (see `should show the Auto and API pools full when nothing of them is used`).
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 50,
                    "limit": 100,
                    "remaining": 50,
                    "autoPercentUsed": false,
                    "apiPercentUsed": true,
                    "totalPercentUsed": 50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .timeLimit("Monthly"))
        #expect(snapshot.quotas[0].percentRemaining == 50)
    }

    @Test
    func `should show nothing left, not below zero, when the Auto and API pools are over their limit`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "2026-01-01T00:00:00.000Z",
            "billingCycleEnd": "2026-02-01T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 500,
                    "limit": 500,
                    "remaining": 0,
                    "autoPercentUsed": 142.5,
                    "apiPercentUsed": 100.1,
                    "totalPercentUsed": 110
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas[0].percentRemaining == 0)
        #expect(snapshot.quotas[1].quotaType == .timeLimit("Auto"))
        #expect(snapshot.quotas[1].percentRemaining == 0)
        #expect(snapshot.quotas[2].quotaType == .timeLimit("API"))
        #expect(snapshot.quotas[2].percentRemaining == 0)
    }

    @Test
    func `should show no Auto or API pool when their share is negative`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 10,
                    "limit": 100,
                    "remaining": 90,
                    "autoPercentUsed": -4,
                    "apiPercentUsed": -0.1,
                    "totalPercentUsed": 10
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .timeLimit("Monthly"))
        #expect(snapshot.quotas[0].percentRemaining == 90)
    }

    @Test
    func `should show the Auto and API pools without reset or pace when the billing cycle has no start`() async throws {
        // Existing fixtures sometimes only have billingCycleEnd (see `should show a Pro plan's monthly requests used out of its limit`).
        let json = """
        {
            "membershipType": "pro",
            "billingCycleEnd": "2025-02-01T00:00:00Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123,
                    "limit": 500,
                    "remaining": 377,
                    "autoPercentUsed": 10,
                    "apiPercentUsed": 20,
                    "totalPercentUsed": 15
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 3)

        let monthly = snapshot.quotas[0]
        #expect(monthly.quotaType == .timeLimit("Monthly"))
        #expect(abs(monthly.percentRemaining - 85) < 0.01)
        #expect(monthly.resetText == "75/500 requests")
        #expect(monthly.resetsAt != nil)
        #expect(monthly.windowDuration == nil)

        let auto = snapshot.quotas[1]
        #expect(auto.quotaType == .timeLimit("Auto"))
        #expect(auto.percentRemaining == 90)
        #expect(auto.resetText == nil)
        #expect(auto.resetsAt == nil)
        #expect(auto.windowDuration == nil)

        let api = snapshot.quotas[2]
        #expect(api.quotaType == .timeLimit("API"))
        #expect(api.percentRemaining == 80)
        #expect(api.resetsAt == nil)
        #expect(api.windowDuration == nil)
    }

    @Test
    func `should show the Auto and API pools without reset or window when the billing cycle start is unreadable`() async throws {
        let json = """
        {
            "membershipType": "pro",
            "billingCycleStart": "not-a-date",
            "billingCycleEnd": "2026-02-01T00:00:00.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 10,
                    "limit": 100,
                    "remaining": 90,
                    "autoPercentUsed": 5,
                    "apiPercentUsed": 8,
                    "totalPercentUsed": 6
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas[0].resetsAt != nil)
        #expect(snapshot.quotas[1].resetsAt == nil)
        #expect(snapshot.quotas[1].windowDuration == nil)
        #expect(snapshot.quotas[2].resetsAt == nil)
        #expect(snapshot.quotas[2].windowDuration == nil)
    }

    @Test
    func `should keep the monthly window first so the menu bar shows it by default`() async throws {
        let json = """
        {
            "membershipType": "ultra",
            "billingCycleStart": "2026-02-06T03:34:49.000Z",
            "billingCycleEnd": "2026-03-06T03:34:49.000Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 326,
                    "limit": 40000,
                    "remaining": 39674,
                    "autoPercentUsed": 39.9,
                    "apiPercentUsed": 97.2,
                    "totalPercentUsed": 44.7
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)
        let first = try #require(snapshot.quotas.first)

        #expect(first.quotaType == .timeLimit("Monthly"))
        #expect(first.quotaType.quotaKey == "time:Monthly")
        #expect(snapshot.quotas.contains { $0.quotaType.quotaKey == "time:API" })
    }

    // MARK: - JWT Parsing

    @Test
    func `should sign in as the user the login token names`() async throws {
        // JWT with payload: {"sub": "user_abc123", "iat": 1234567890}
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let payload = "eyJzdWIiOiJ1c2VyX2FiYzEyMyIsImlhdCI6MTIzNDU2Nzg5MH0"
        let signature = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwt = "\(header).\(payload).\(signature)"

        let userId = try await userID(jwt)
        #expect(userId == "user_abc123")
    }

    @Test
    func `should sign in as a user whose id holds a pipe, as Cursor's do`() async throws {
        // Cursor JWTs have sub like "github|user_01J6BBEPT2KSQKPPRGXDY8M1F4"
        // Payload: {"sub": "github|user_01ABC", "type": "session"}
        // base64url of {"sub":"github|user_01ABC","type":"session"} =
        let payloadJson = #"{"sub":"github|user_01ABC","type":"session"}"#
        let payloadBase64 = Data(payloadJson.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "eyJhbGciOiJIUzI1NiJ9.\(payloadBase64).sig"

        let userId = try await userID(jwt)
        #expect(userId == "github|user_01ABC")
    }

    @Test
    func `should sign in as the user a short login token names`() async throws {
        // Payload: {"sub": "u1"}
        let header = "eyJhbGciOiJIUzI1NiJ9"
        let payload = "eyJzdWIiOiJ1MSJ9"
        let jwt = "\(header).\(payload).sig"

        let userId = try await userID(jwt)
        #expect(userId == "u1")
    }

    @Test(arguments: ["not-a-jwt", "eyJhbGciOiJIUzI1NiJ9.eyJpYXQiOjEyM30.sig"])
    func `should sign in without a session cookie when the login token names no user`(_ token: String) async throws {
        // Not a JWT, or one with no `sub`: the cookie is left out, and Cursor answers for itself.
        let capture = CookieCapture()
        _ = try await refreshAdded(Data(#"{"isUnlimited":true}"#.utf8), token: token, capture: capture)
        #expect(capture.get() == nil)
    }

    // MARK: - Numeric Type Handling

    @Test
    func `should show the requests left when Cursor counts them with decimals`() async throws {
        // Some API responses return numbers as doubles
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123.0,
                    "limit": 500.0,
                    "remaining": 377.0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(abs(snapshot.quotas[0].percentRemaining - 75.4) < 0.1)
    }

    // MARK: - Account Tier Detection

    @Test
    func `should show the Ultra plan`() async throws {
        let json = """
        {
            "membershipType": "ultra",
            "isUnlimited": false,
            "individualUsage": {
                "plan": { "enabled": true, "used": 1, "limit": 40000, "remaining": 39999 },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try await parse(json)
        #expect(snapshot.accountTier == .custom("ULTRA"))
    }
}

@MainActor @Suite struct CursorAccountTests {
    private func token(_ subject: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["sub":subject])
        return "header." + data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") + ".signature"
    }
    private func database(in root: URL, token: String?) throws -> URL {
        let url=root.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        let insert=token.map {" INSERT INTO ItemTable VALUES ('cursorAuth/accessToken','\($0)');"} ?? ""
        try SQLiteFiles.make(at:url,"CREATE TABLE ItemTable(key TEXT,value TEXT);"+insert)
        return url
    }
    @Test func `should keep the Cursor app's login and added logins apart through rename, relaunch, a lost token and removal`() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let personal=try token("personal|desktop"), work=try token("work|account"), other=try token("work|similar")
        let db=try database(in:root,token:personal), bytes=try Data(contentsOf:db)
        let settings=InMemoryProviderSettings(), vault=MemoryVault(), network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            let cookie=request.value(forHTTPHeaderField:"Cookie") ?? ""
            let remaining=cookie.contains("personal|desktop::") ? 80 : cookie.contains("work|account::") ? 40 : cookie.contains("work|similar::") ? 20 : -1
            #expect(remaining >= 0)
            let data=Data("{\"individualUsage\":{\"plan\":{\"enabled\":true,\"limit\":100,\"used\":\(100-remaining)}}}".utf8)
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        let definition=try ProviderFactory.builtIn("cursor")
        var platform=Platform.current
        platform.applicationData={home,_ in home.appendingPathComponent("Library/Application Support")}
        let fixturePlatform=platform
        let make: @MainActor () -> Provider = {
            Provider(definition:definition,settings:settings,accounts:settings.accounts(forProvider:"cursor"),makeDataSource:{source,login in
                DataSources.make(source,providerId:"cursor",platform:fixturePlatform,network:network,scripts:ProviderFactory.builtInScripts,secrets:vault.scoped(to:login),environment:{_ in personal},homeDirectory:root,now:{Date()})
            },vault:vault)
        }
        let first=make()
        #expect(first.defaultAccount.displayName == "Cursor")
        let added=try first.accounts.add(filling:["accessToken":work]), second=try first.accounts.add(filling:["accessToken":other])
        first.accounts.rename(added,to:"Work");first.accounts.rename(second,to:"Other work")
        #expect(added.displayName == "Work" && second.displayName == "Other work")
        #expect((try await first.refreshPlain()).quotas[0].percentRemaining == 80)
        #expect((try await first.refresh(added)).quotas[0].percentRemaining == 40)
        #expect((try await first.refresh(second)).quotas[0].percentRemaining == 20)
        #expect(settings.accounts(forProvider:"cursor").allSatisfy {$0.probeConfig.isEmpty})
        let relaunched=make(), saved=try #require(relaunched.accounts.first {$0.id == added.id})
        #expect(saved.displayName == "Work")
        #expect((try await relaunched.refresh(saved)).quotas[0].percentRemaining == 40)
        _ = vault.delete("accessToken",provider:saved.id)
        await #expect(throws:UsageError.authenticationRequired) {try await relaunched.refresh(saved)}
        #expect((try await relaunched.refreshPlain()).quotas[0].percentRemaining == 80)
        relaunched.accounts.remove(saved)
        #expect(!settings.accounts(forProvider:"cursor").contains {$0.accountId == saved.accountId})
        #expect(relaunched.accounts.count == 2)
        #expect(try Data(contentsOf:db) == bytes)
    }
    @Test(arguments:[(401,UsageError.sessionExpired(hint:"Re-authenticate in Cursor settings.")),(403,.authenticationRequired),(201,.executionFailed("HTTP error: 201")),(500,.executionFailed("HTTP error: 500"))])
    func `should tell the person how to recover when Cursor refuses or errors`(_ fixture:(Int,UsageError)) async throws {
        let vault=MemoryVault(), network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            (Data("{}".utf8),HTTPURLResponse(url:request.url!,statusCode:fixture.0,httpVersion:nil,headerFields:nil)!)
        }
        let provider=Provider(definition:try ProviderFactory.builtIn("cursor"),settings:InMemoryProviderSettings(),makeDataSource:{source,login in
            DataSources.make(source,providerId:"cursor",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:ProviderFactory.builtInScripts,secrets:vault.scoped(to:login),environment:{_ in nil},homeDirectory:FileManager.default.temporaryDirectory,now:{Date()})
        },vault:vault)
        let account=try provider.accounts.add(filling:["accessToken":token("test")])
        await #expect(throws:fixture.1) {try await provider.refresh(account)}
    }

    @Test func `should say it is rate limited, not an HTTP error, when Cursor answers 429`() async throws {
        let vault = MemoryVault(), network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        let provider = Provider(definition: try ProviderFactory.builtIn("cursor"), settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: "cursor", cliExecutor: MockCLIExecutor(), network: network, makeTransport: { _, _, _, _ in MockRPCTransport() },
                             scripts: ProviderFactory.builtInScripts, secrets: vault.scoped(to: login), environment: { _ in nil },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
        let account = try provider.accounts.add(filling: ["accessToken": token("test")])
        await #expect { try await provider.refresh(account) } throws: { ($0 as? UsageError)?.tag == "rateLimited" }
    }

    @Test func `should ask to sign in again in Cursor's settings when the Cursor app has no login on this Mac`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let provider = Provider(definition: try ProviderFactory.builtIn("cursor"), settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: "cursor", cliExecutor: MockCLIExecutor(), network: MockNetworkClient(), makeTransport: { _, _, _, _ in MockRPCTransport() },
                             scripts: ProviderFactory.builtInScripts, environment: { _ in nil }, homeDirectory: root, now: { Date() })
        })
        #expect(await provider.isPlainAvailable() == false)
        await #expect(throws: UsageError.authenticationRequired) { try await provider.refreshPlain() }
        #expect(provider.configuration.keyHint == "Sign in again in Cursor settings, then refresh.")
    }
}
