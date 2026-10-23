import Foundation
import Quotas

/// What a webhook POSTs: an alert, the week's recap, or a test, shaped for
/// its channel. Slack gets one line, the words of the Mac's notification; a
/// recap gets its own message, built from the same `Recap` the card reads;
/// JSON gets every key of its kind on every send, `null` where there is no
/// value. A test says it is a test and is never shaped like an alert or a
/// recap.
public struct WebhookBody: Sendable, Equatable {
    /// What is being sent.
    public enum Message: Sendable, Equatable {
        case alert(Alert)
        /// The week that closed, added up ([recap alerts](docs/features/alerting/recap-alerts/design.md)).
        case recap(RecapAlert)
        /// *Send a test*: no login, no quota judged, no week.
        case test
    }

    public let message: Message
    public let channel: WebhookChannel
    public let sentAt: Date

    public init(_ message: Message, channel: WebhookChannel, sentAt: Date) {
        self.message = message
        self.channel = channel
        self.sentAt = sentAt
    }

    /// The bytes to POST.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Every payload is plain strings, numbers and nulls: encoding can't fail.
        return switch channel {
        case .slack: (try? encoder.encode(["text": line])) ?? Data()
        case .json: (try? encoder.encode(jsonPayload)) ?? Data()
        }
    }

    /// The JSON body, as the message decides: one switch, and each payload a
    /// plain shape of its own kind.
    private var jsonPayload: any Encodable {
        switch message {
        case .alert(.quota(let alert)):
            AlertPayload(type: "quota", provider: alert.providerId, login: alert.login,
                         below: alert.below, left: alert.left, status: nil, was: nil, sentAt: sentAt)
        case .alert(.status(let alert)):
            AlertPayload(type: "status", provider: alert.providerId, login: alert.login,
                         below: nil, left: nil, status: alert.now.payloadName, was: alert.was.payloadName,
                         sentAt: sentAt)
        case .recap(let alert):
            RecapPayload(alert, sentAt: sentAt)
        case .test:
            AlertPayload(type: "test", provider: nil, login: nil, below: nil, left: nil,
                         status: nil, was: nil, sentAt: sentAt)
        }
    }

    /// The one line a person reads in Slack.
    var line: String {
        switch message {
        case .alert(.quota(let alert)): "\(alert.login) is below \(alert.below)% — \(alert.left)% left"
        case .alert(.status(let alert)): "\(alert.login) is \(alert.now.payloadName) — was \(alert.was.payloadName)"
        case .recap(let alert): RecapLine(alert).text
        case .test: "ClaudeBar test — this webhook works. No quota was judged."
        }
    }
}

/// The alerts' and the test's JSON body. Every key is written on every send
/// of its kind, so a consumer never has to tell an absent field from an empty
/// one.
private struct AlertPayload: Encodable {
    let type: String
    let provider: String?
    let login: String?
    let below: Int?
    let left: Int?
    let status: String?
    let was: String?
    let sentAt: Date

    enum CodingKeys: String, CodingKey { case type, provider, login, below, left, status, was, sentAt }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(provider, forKey: .provider)
        try container.encode(login, forKey: .login)
        try container.encode(below, forKey: .below)
        try container.encode(left, forKey: .left)
        try container.encode(status, forKey: .status)
        try container.encode(was, forKey: .was)
        try container.encode(sentAt, forKey: .sentAt)
    }
}

/// The recap's JSON body: the week's numbers, the split with each provider's
/// name, and the highlights — `null` where the week has no value.
private struct RecapPayload: Encodable {
    struct ProviderPart: Encodable {
        let provider: String
        let name: String
        let value: Double
        let share: Double
    }

    let type: String
    let unit: String
    let total: Double
    let change: Double?
    let weekStart: Date
    let weekEnd: Date
    let providers: [ProviderPart]
    let topModel: String?
    let biggestDay: String?
    let cacheSavings: Decimal
    let workingTime: TimeInterval
    let sessions: Int
    let tokens: Double?
    let sentAt: Date

    init(_ alert: RecapAlert, sentAt: Date) {
        type = "recap"
        self.sentAt = sentAt
        unit = switch alert.recap.unit {
        case .cost: "cost"
        case .tokens: "tokens"
        case .cache: "cache"
        }
        total = alert.recap.total
        change = alert.recap.change
        weekStart = alert.week.first
        weekEnd = alert.week.last
        providers = alert.recap.providers.map {
            ProviderPart(provider: $0.provider, name: alert.name(of: $0), value: $0.value, share: $0.share)
        }
        topModel = alert.recap.topModel.map(\.line.model)
        biggestDay = alert.recap.biggestDay.map { Self.day($0.date, in: alert.calendar) }
        cacheSavings = alert.recap.cacheSavings
        workingTime = alert.recap.workingTime
        sessions = alert.recap.sessions
        tokens = alert.recap.tokens
    }

    /// The day a date falls on, Gregorian in the week's own zone — "2026-11-05".
    /// The week's boundaries stay in the person's calendar; what a machine
    /// reads is written Gregorian, whatever calendar the person keeps.
    private static func day(_ date: Date, in calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let day = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case type, unit, total, change, weekStart, weekEnd, providers, topModel
        case biggestDay, cacheSavings, workingTime, sessions, tokens, sentAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(unit, forKey: .unit)
        try container.encode(total, forKey: .total)
        try container.encode(change, forKey: .change)
        try container.encode(weekStart, forKey: .weekStart)
        try container.encode(weekEnd, forKey: .weekEnd)
        try container.encode(providers, forKey: .providers)
        try container.encode(topModel, forKey: .topModel)
        try container.encode(biggestDay, forKey: .biggestDay)
        try container.encode(cacheSavings, forKey: .cacheSavings)
        try container.encode(workingTime, forKey: .workingTime)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(sentAt, forKey: .sentAt)
    }
}

/// The recap's Slack words: the week, the total, the change, the split, and
/// the highlights the week has. Clauses the week doesn't have are left out.
/// Money reads through the kernel's `MoneyFormat`; counts spell like the
/// chart's; the days are written Gregorian in the week's zone — the person's
/// calendar holds the week's boundaries, never the numbers on the page.
private struct RecapLine {
    private let alert: RecapAlert
    /// The calendar the words are written in: Gregorian, in the week's zone.
    private let calendar: Calendar
    private let days: DateFormatter
    /// An en dash between a run of days.
    private static let dash = "\u{2013}"

    init(_ alert: RecapAlert) {
        self.alert = alert
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = alert.calendar.timeZone
        calendar = gregorian
        days = DateFormatter()
        days.locale = Locale(identifier: "en_US_POSIX")
        days.calendar = gregorian
        days.timeZone = alert.calendar.timeZone
        days.dateFormat = "MMM d"
    }

    var text: String {
        [story, split, highlights].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// *Weekly recap Nov 3–9: $12.34, +20% vs the week before.*
    private var story: String {
        var text = "Weekly recap \(weekText): \(totalText)"
        if let change = alert.recap.change {
            text += ", \(UsageNumberFormat.change(change)) vs the week before"
        }
        return text + "."
    }

    /// *Claude 62% · Codex 38%.*
    private var split: String {
        let parts = alert.recap.providers.map { "\(alert.name(of: $0)) \(UsageNumberFormat.share($0.share))" }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: " · ") + "."
    }

    /// *Top model claude-sonnet-4-5 · biggest day Nov 5 · cache saved $1.02.*
    private var highlights: String {
        var highlights: [String] = []
        if let top = alert.recap.topModel { highlights.append("top model \(top.line.model)") }
        if let day = alert.recap.biggestDay { highlights.append("biggest day \(days.string(from: day.date))") }
        if alert.recap.cacheSavings > 0 { highlights.append("cache saved \(MoneyFormat.string(alert.recap.cacheSavings))") }
        guard !highlights.isEmpty else { return "" }
        return Self.sentence(highlights.joined(separator: " · ")) + "."
    }

    /// The clause run as its own sentence — its first word capitalized,
    /// "top model" opening as "Top model".
    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    /// *Nov 3–9*, or *Nov 28–Dec 4* across a month's edge — the shared month
    /// written once.
    private var weekText: String {
        let first = days.string(from: alert.week.first)
        let last = days.string(from: alert.week.last)
        if first == last { return first }
        let sameMonth = calendar.isDate(alert.week.first, equalTo: alert.week.last, toGranularity: .month)
        return sameMonth ? "\(first)\(Self.dash)\(Self.dayNumber(of: alert.week.last, in: calendar))"
                         : "\(first)\(Self.dash)\(last)"
    }

    /// The day of the month as the words' calendar holds it — "9".
    private static func dayNumber(of date: Date, in calendar: Calendar) -> String {
        String(calendar.dateComponents([.day], from: date).day ?? 0)
    }

    /// "$12.34", or "19.5M tokens" — in the unit every provider offers.
    private var totalText: String {
        switch alert.recap.unit {
        case .cost: MoneyFormat.string(Decimal(alert.recap.total))
        case .tokens: "\(UsageNumberFormat.count(Int(alert.recap.total))) tokens"
        case .cache: "\(UsageNumberFormat.count(Int(alert.recap.total))) cache tokens"
        }
    }
}

extension QuotaStatus {
    /// The status as a payload names it.
    var payloadName: String {
        switch self {
        case .healthy: "healthy"
        case .warning: "warning"
        case .critical: "critical"
        case .depleted: "depleted"
        }
    }
}
