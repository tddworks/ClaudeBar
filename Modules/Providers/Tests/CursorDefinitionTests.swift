import Foundation
import Testing
import Providers
import DataSources
import Quotas
import Mockable


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
    private func make(_ data:Data, token:String, capture:CookieCapture = CookieCapture()) throws -> Account {
        let definition=try Providers.builtIn("cursor"), vault=MemoryVault(), network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            #expect(request.url?.absoluteString == "https://cursor.com/api/usage-summary")
            #expect(request.httpMethod == "GET" && request.timeoutInterval == 15)
            capture.set(request.value(forHTTPHeaderField:"Cookie"))
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        let provider=Provider(definition:definition,settings:InMemoryProviderSettings(),makeDataSource:{ source,login in
            DataSources.make(source,providerId:"cursor",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,secrets:vault.scoped(to:login),environment:{_ in nil},homeDirectory:FileManager.default.temporaryDirectory,now:{Date()})
        },vault:vault)
        return try provider.addAccount(filling:["accessToken":token])
    }
    private func parse(_ data:Data) async throws -> UsageSnapshot {
        try await make(data,token:"header.eyJzdWIiOiJmaXh0dXJlLXVzZXIifQ.signature").refresh()
    }
    private func userID(_ token:String) async throws -> String {
        let capture=CookieCapture()
        _ = try await make(Data(#"{"isUnlimited":true}"#.utf8),token:token,capture:capture).refresh()
        let cookie=try #require(capture.get())
        #expect(cookie.hasPrefix("WorkosCursorSessionToken="))
        #expect(cookie.hasSuffix("::"+token))
        return String(cookie.dropFirst("WorkosCursorSessionToken=".count).dropLast(token.count+2))
    }


    // MARK: - Real API Response

    @Test
    func `parse real ultra plan response`() async throws {
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
    func `parse pro plan with plan usage`() async throws {
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
    func `parse plan with on-demand usage enabled`() async throws {
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
    func `parse depleted plan usage`() async throws {
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
    func `parse pro plan with bonus credits reports remaining from total capacity`() async throws {
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
    func `parse over-limit usage clamps to zero`() async throws {
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
    func `parse unlimited plan`() async throws {
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
    func `parse free plan`() async throws {
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
    func `parse enterprise plan with team limitType`() async throws {
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
    func `parse enterprise plan individual usage falls back to breakdown total`() async throws {
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
    func `parse empty response throws error`() async {
        let json = "{}".data(using: .utf8)!

        await #expect(throws: UsageError.self) {
            try await parse(json)
        }
    }

    @Test
    func `parse invalid json throws error`() async {
        let json = "not json".data(using: .utf8)!

        await #expect(throws: UsageError.self) {
            try await parse(json)
        }
    }

    @Test
    func `parse response with no individualUsage and not unlimited throws error`() async {
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
    func `parse billing cycle end with fractional seconds`() async throws {
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
    func `parse billing cycle end without fractional seconds`() async throws {
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
    func `parse total-only response keeps a single monthly card`() async throws {
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
    func `parse integer zero auto percent as fully remaining`() async throws {
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
    func `parse null auto and api percent omits those cards`() async throws {
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
    func `parse non-numeric auto and api percent omits those cards`() async throws {
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
    func `parse boolean auto and api percent omits those cards`() async throws {
        // JSON true/false are CFBoolean and must not become 1.0 / 0.0. Integer 0
        // still has to produce a card (see parse integer zero auto percent).
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
    func `parse auto and api percent over 100 clamps remaining to zero`() async throws {
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
    func `parse negative auto and api percent omits those cards`() async throws {
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
    func `parse billing cycle without start omits auto api reset pace`() async throws {
        // Existing fixtures sometimes only have billingCycleEnd (see parse pro plan with plan usage).
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
    func `parse unusable billing cycle start omits auto api window duration`() async throws {
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
    func `first quota stays monthly so the default menu bar selection is unchanged`() async throws {
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
    func `extract user ID from valid JWT`() async throws {
        // JWT with payload: {"sub": "user_abc123", "iat": 1234567890}
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let payload = "eyJzdWIiOiJ1c2VyX2FiYzEyMyIsImlhdCI6MTIzNDU2Nzg5MH0"
        let signature = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwt = "\(header).\(payload).\(signature)"

        let userId = try await userID(jwt)
        #expect(userId == "user_abc123")
    }

    @Test
    func `extract user ID with pipe character like real Cursor JWTs`() async throws {
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
    func `extract user ID from JWT with padding needed`() async throws {
        // Payload: {"sub": "u1"}
        let header = "eyJhbGciOiJIUzI1NiJ9"
        let payload = "eyJzdWIiOiJ1MSJ9"
        let jwt = "\(header).\(payload).sig"

        let userId = try await userID(jwt)
        #expect(userId == "u1")
    }

    @Test(arguments: ["not-a-jwt", "eyJhbGciOiJIUzI1NiJ9.eyJpYXQiOjEyM30.sig"])
    func `a token with no user id sends no session cookie`(_ token: String) async throws {
        // Not a JWT, or one with no `sub`: the cookie is left out, and Cursor answers for itself.
        let capture = CookieCapture()
        _ = try await make(Data(#"{"isUnlimited":true}"#.utf8), token: token, capture: capture).refresh()
        #expect(capture.get() == nil)
    }

    // MARK: - Numeric Type Handling

    @Test
    func `parse usage values as doubles`() async throws {
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
    func `detect ultra tier`() async throws {
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
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/sqlite3")
        let insert=token.map {" INSERT INTO ItemTable VALUES ('cursorAuth/accessToken','\($0)');"} ?? ""
        process.arguments=[url.path,"CREATE TABLE ItemTable(key TEXT,value TEXT);"+insert]
        try process.run();process.waitUntilExit();#expect(process.terminationStatus == 0)
        return url
    }
    @Test func `desktop and saved accounts stay separate through rename relaunch removal and missing credentials`() async throws {
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
        let definition=try Providers.builtIn("cursor")
        let make: @MainActor () -> Provider = {
            Provider(definition:definition,settings:settings,accounts:settings.accounts(forProvider:"cursor"),makeDataSource:{source,login in
                DataSources.make(source,providerId:"cursor",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,secrets:vault.scoped(to:login),environment:{_ in personal},homeDirectory:root,now:{Date()})
            },vault:vault)
        }
        let first=make()
        #expect(first.defaultAccount.displayName == "Cursor")
        let added=try first.addAccount(filling:["accessToken":work]), second=try first.addAccount(filling:["accessToken":other])
        first.rename(added,to:"Work");first.rename(second,to:"Other work")
        #expect(added.displayName == "Work" && second.displayName == "Other work")
        #expect((try await first.defaultAccount.refresh()).quotas[0].percentRemaining == 80)
        #expect((try await added.refresh()).quotas[0].percentRemaining == 40)
        #expect((try await second.refresh()).quotas[0].percentRemaining == 20)
        #expect(settings.accounts(forProvider:"cursor").allSatisfy {$0.probeConfig.isEmpty})
        let relaunched=make(), saved=try #require(relaunched.accounts.first {$0.id == added.id})
        #expect(saved.displayName == "Work")
        #expect((try await saved.refresh()).quotas[0].percentRemaining == 40)
        _ = vault.delete("accessToken",provider:saved.id)
        await #expect(throws:UsageError.authenticationRequired) {try await saved.refresh()}
        #expect((try await relaunched.defaultAccount.refresh()).quotas[0].percentRemaining == 80)
        relaunched.remove(saved)
        #expect(!settings.accounts(forProvider:"cursor").contains {$0.accountId == saved.accountId})
        #expect(relaunched.accounts.count == 2)
        #expect(try Data(contentsOf:db) == bytes)
    }
    @Test(arguments:[(401,UsageError.sessionExpired(hint:"Re-authenticate in Cursor settings.")),(403,.authenticationRequired),(201,.executionFailed("HTTP error: 201")),(500,.executionFailed("HTTP error: 500"))])
    func `HTTP failures preserve Cursor recovery behavior`(_ fixture:(Int,UsageError)) async throws {
        let vault=MemoryVault(), network=MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            (Data("{}".utf8),HTTPURLResponse(url:request.url!,statusCode:fixture.0,httpVersion:nil,headerFields:nil)!)
        }
        let provider=Provider(definition:try Providers.builtIn("cursor"),settings:InMemoryProviderSettings(),makeDataSource:{source,login in
            DataSources.make(source,providerId:"cursor",cliExecutor:MockCLIExecutor(),network:network,makeTransport:{_,_,_,_ in MockRPCTransport()},scripts:Providers.builtInScripts,secrets:vault.scoped(to:login),environment:{_ in nil},homeDirectory:FileManager.default.temporaryDirectory,now:{Date()})
        },vault:vault)
        let account=try provider.addAccount(filling:["accessToken":token("test")])
        await #expect(throws:fixture.1) {try await account.refresh()}
    }

    @Test func `a 429 is a rate limit, not an HTTP error`() async throws {
        let vault = MemoryVault(), network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        let provider = Provider(definition: try Providers.builtIn("cursor"), settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: "cursor", cliExecutor: MockCLIExecutor(), network: network, makeTransport: { _, _, _, _ in MockRPCTransport() },
                             scripts: Providers.builtInScripts, secrets: vault.scoped(to: login), environment: { _ in nil },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
        let account = try provider.addAccount(filling: ["accessToken": token("test")])
        await #expect { try await account.refresh() } throws: { ($0 as? UsageError)?.tag == "rateLimited" }
    }

    @Test func `without the Cursor app's database the default login needs signing in, with Cursor's own hint`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let provider = Provider(definition: try Providers.builtIn("cursor"), settings: InMemoryProviderSettings(), makeDataSource: { source, login in
            DataSources.make(source, providerId: "cursor", cliExecutor: MockCLIExecutor(), network: MockNetworkClient(), makeTransport: { _, _, _, _ in MockRPCTransport() },
                             scripts: Providers.builtInScripts, environment: { _ in nil }, homeDirectory: root, now: { Date() })
        })
        #expect(await provider.defaultAccount.isAvailable() == false)
        await #expect(throws: UsageError.authenticationRequired) { try await provider.defaultAccount.refresh() }
        #expect(provider.keyHint == "Sign in again in Cursor settings, then refresh.")
    }
}
