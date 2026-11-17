import Testing
import Foundation
@testable import Quotas

@Suite
struct QuotaTypeTests {

    // MARK: - Display Name Tests

    @Test
    func `should name the session quota Session`() {
        #expect(QuotaType.session.displayName == "Session")
    }

    @Test
    func `should name the weekly quota Weekly`() {
        #expect(QuotaType.weekly.displayName == "Weekly")
    }

    @Test
    func `should name a model's quota after the model, capitalized`() {
        #expect(QuotaType.modelSpecific("opus").displayName == "Opus")
        #expect(QuotaType.modelSpecific("sonnet").displayName == "Sonnet")
        #expect(QuotaType.modelSpecific("haiku").displayName == "Haiku")
    }

    @Test
    func `should show the Fable quota as Fable and read it back after saving it`() {
        let fable = QuotaType.modelSpecific("fable")
        #expect(fable.displayName == "Fable")
        #expect(fable.quotaKey == "model:fable")
        #expect(QuotaType(quotaKey: "model:fable") == fable)
    }

    @Test
    func `should capitalize each word of a hyphenated model name`() {
        // .capitalized capitalizes each word
        #expect(QuotaType.modelSpecific("claude-3-opus").displayName == "Claude-3-Opus")
    }

    @Test
    func `should show a time-limit quota's name exactly as the provider wrote it`() {
        // Labels arrive display-ready; capitalizing would mangle acronyms
        // ("MCP" → "Mcp") and window tokens ("Claude 5h" → "Claude 5H").
        #expect(QuotaType.timeLimit("MCP").displayName == "MCP")
        #expect(QuotaType.timeLimit("Daily Limit").displayName == "Daily Limit")
        #expect(QuotaType.timeLimit("Claude 5h").displayName == "Claude 5h")
    }

    // MARK: - Duration Tests

    @Test
    func `should expect the session quota to last 5 hours`() {
        #expect(QuotaType.session.conventionalWindow == .hours(5))
    }

    @Test
    func `should expect the weekly quota to last 7 days`() {
        #expect(QuotaType.weekly.conventionalWindow == .days(7))
    }

    @Test
    func `should expect a model's quota to last 7 days`() {
        #expect(QuotaType.modelSpecific("opus").conventionalWindow == .days(7))
    }

    @Test
    func `should expect a time-limit quota to last 7 days`() {
        #expect(QuotaType.timeLimit("any").conventionalWindow == .days(7))
    }

    // MARK: - Model Name Tests

    @Test
    func `should name no model for the session quota`() {
        #expect(QuotaType.session.modelName == nil)
    }

    @Test
    func `should name no model for the weekly quota`() {
        #expect(QuotaType.weekly.modelName == nil)
    }

    @Test
    func `should name no model for a time-limit quota`() {
        #expect(QuotaType.timeLimit("mcp").modelName == nil)
    }

    @Test
    func `should name the model a model's quota belongs to`() {
        #expect(QuotaType.modelSpecific("opus").modelName == "opus")
        #expect(QuotaType.modelSpecific("sonnet").modelName == "sonnet")
    }

    // MARK: - Equality Tests

    @Test
    func `should treat the same kind of quota as the same`() {
        #expect(QuotaType.session == .session)
        #expect(QuotaType.weekly == .weekly)
        #expect(QuotaType.modelSpecific("opus") == .modelSpecific("opus"))
    }

    @Test
    func `should tell different kinds of quota apart`() {
        #expect(QuotaType.session != .weekly)
        #expect(QuotaType.modelSpecific("opus") != .modelSpecific("sonnet"))
    }

    // MARK: - Hashable Tests

    @Test
    func `should count a repeated kind of quota once in a set`() {
        let types: Set<QuotaType> = [.session, .weekly, .modelSpecific("opus"), .session]
        #expect(types.count == 3)
    }

    @Test
    func `should let each kind of quota carry its own value in a lookup`() {
        var dict: [QuotaType: String] = [:]
        dict[.session] = "5 hours"
        dict[.weekly] = "7 days"

        #expect(dict[.session] == "5 hours")
        #expect(dict[.weekly] == "7 days")
    }
}

@Suite
struct QuotaDurationTests {

    // MARK: - Seconds Calculation Tests

    @Test
    func `should count an hour-long window as 3600 seconds per hour`() {
        #expect(QuotaDuration.hours(1).seconds == 3600)
        #expect(QuotaDuration.hours(5).seconds == 18000)
        #expect(QuotaDuration.hours(24).seconds == 86400)
    }

    @Test
    func `should count a day-long window as 86400 seconds per day`() {
        #expect(QuotaDuration.days(1).seconds == 86400)
        #expect(QuotaDuration.days(7).seconds == 604800)
    }

    // MARK: - Description Tests

    @Test
    func `should print one hour as 1 hour`() {
        #expect(QuotaDuration.hours(1).description == "1 hour")
    }

    @Test
    func `should print several hours in the plural`() {
        #expect(QuotaDuration.hours(5).description == "5 hours")
        #expect(QuotaDuration.hours(24).description == "24 hours")
    }

    @Test
    func `should print one day as 1 day`() {
        #expect(QuotaDuration.days(1).description == "1 day")
    }

    @Test
    func `should print several days in the plural`() {
        #expect(QuotaDuration.days(7).description == "7 days")
        #expect(QuotaDuration.days(30).description == "30 days")
    }

    // MARK: - Equality Tests

    @Test
    func `should treat the same window length as the same`() {
        #expect(QuotaDuration.hours(5) == .hours(5))
        #expect(QuotaDuration.days(7) == .days(7))
    }

    @Test
    func `should tell 24 hours apart from 1 day and other lengths apart`() {
        #expect(QuotaDuration.hours(5) != .hours(6))
        #expect(QuotaDuration.days(7) != .days(1))
        #expect(QuotaDuration.hours(24) != .days(1)) // Same seconds, different types
    }
}
