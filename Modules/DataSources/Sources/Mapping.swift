import Quotas
import Foundation

/// WHAT THE BYTES SAY — *Map fields*. A closed sum: a JSON response is read by
/// paths, a terminal screen by patterns.
public enum Mapping: Sendable, Equatable {
    case json(JSONMapping)
    case text(TextMapping)
    /// A format no rule can say — a TUI screen, a money shape — read by a
    /// JavaScript file run in JavaScriptCore, with no file, network or
    /// process access.
    case script(ScriptMapping)
}

/// `{ "script": { "file": "claude-usage-screen.js", "credential": ["subscriptionType"] } }`
///
/// The script defines `read(response, context)` and returns
/// `{ quotas, plan, cost, account }` or `{ error }`. It sees only the
/// credential values named here — never a token.
public struct ScriptMapping: Sendable, Equatable, Codable {
    public let file: String
    public let credential: [String]
    /// Values handed to the script as `context.values` — typically
    /// `{{setting.x}}`, a setting the person set. One that still holds a
    /// template was left blank, and isn't there.
    public let values: [String: String]

    public init(file: String, credential: [String] = [], values: [String: String] = [:]) {
        self.file = file
        self.credential = credential
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(String.self, forKey: .file)
        credential = try container.decodeIfPresent([String].self, forKey: .credential) ?? []
        values = try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        if !credential.isEmpty { try container.encode(credential, forKey: .credential) }
        if !values.isEmpty { try container.encode(values, forKey: .values) }
    }

    private enum CodingKeys: String, CodingKey { case file, credential, values }
}

// MARK: - Shared vocabulary

/// Which kind of quota a rule produces — today's `QuotaType`.
public enum QuotaKind: String, Sendable, Equatable, Codable {
    /// The rolling 5-hour window ("Session").
    case session
    /// The rolling 7-day window ("Weekly").
    case weekly
    /// A model-specific limit, named by the rule.
    case model
    /// Any other named limit, named by the rule.
    case time
}

/// A value read from the response: a path, or a constant written in the
/// definition. A list of them means *the first that answers*.
///
/// Paths: `$.a.b` from the root · `a.b` from the current object · `$header.x`
/// for a response header · `$key` for the current key while repeating over a map.
public enum ValueRef: Sendable, Equatable, Codable {
    case path(String)
    case constant(Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .constant(number)
        } else {
            self = .path(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .path(let path): try container.encode(path)
        case .constant(let number): try container.encode(number)
        }
    }
}

/// When a quota resets, from one of the shapes providers use.
public enum ResetRef: Sendable, Equatable, Codable {
    case epochSeconds(String)
    case secondsFromNow(String)
    case iso8601(String)

    private static let tags = ["epochSeconds", "secondsFromNow", "iso8601"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        let tag = try container.singleTag(of: Self.tags, in: "resetsAt")
        let path = try container.decode(String.self, forKey: TagKey(tag))
        switch tag {
        case "epochSeconds": self = .epochSeconds(path)
        case "secondsFromNow": self = .secondsFromNow(path)
        default: self = .iso8601(path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .epochSeconds(let path): try container.encode(path, forKey: TagKey("epochSeconds"))
        case .secondsFromNow(let path): try container.encode(path, forKey: TagKey("secondsFromNow"))
        case .iso8601(let path): try container.encode(path, forKey: TagKey("iso8601"))
        }
    }
}

/// A window's length — read from the response in the unit the provider
/// reports it in, or a fixed length the provider is known for:
/// `{ "seconds": "limit_window_seconds" }` · `{ "minutes": "windowDurationMins" }` ·
/// `{ "hours": 5 }` · `{ "days": 7 }`. The kernel never guesses one.
public enum DurationRef: Sendable, Equatable, Codable {
    case seconds(String)
    case minutes(String)
    /// A fixed length, in seconds.
    case fixed(TimeInterval)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        let tag = try container.singleTag(of: ["seconds", "minutes", "hours", "days"], in: "window")
        let scale: TimeInterval = ["seconds": 1, "minutes": 60, "hours": 3600, "days": 86400][tag] ?? 1
        if let length = try? container.decode(Double.self, forKey: TagKey(tag)) {
            self = .fixed(length * scale)
        } else {
            let path = try container.decode(String.self, forKey: TagKey(tag))
            self = tag == "minutes" ? .minutes(path) : .seconds(path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .seconds(let path): try container.encode(path, forKey: TagKey("seconds"))
        case .minutes(let path): try container.encode(path, forKey: TagKey("minutes"))
        case .fixed(let seconds): try container.encode(seconds, forKey: TagKey("seconds"))
        }
    }
}

/// A quota's name: fixed text, or read from the response and tidied.
public struct NameRule: Sendable, Equatable, Codable {
    /// Strips a prefix (case-insensitively); `capitalize` upper-cases the
    /// first letter of what is left.
    public struct Prefix: Sendable, Equatable, Codable {
        public let prefix: String
        public let capitalize: Bool

        public init(prefix: String, capitalize: Bool = false) {
            self.prefix = prefix
            self.capitalize = capitalize
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            prefix = try container.decode(String.self, forKey: .prefix)
            capitalize = try container.decodeIfPresent(Bool.self, forKey: .capitalize) ?? false
        }
    }

    public let text: String?
    public let firstOf: [String]
    /// The first prefix that matches is the one dropped.
    public let dropPrefixes: [Prefix]
    /// Only the first word — "Fable 5" → "Fable".
    public let firstWord: Bool
    public let lowercase: Bool

    public init(text: String? = nil, firstOf: [String] = [], dropPrefixes: [Prefix] = [], firstWord: Bool = false, lowercase: Bool = false) {
        self.text = text
        self.firstOf = firstOf
        self.dropPrefixes = dropPrefixes
        self.firstWord = firstWord
        self.lowercase = lowercase
    }

    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text: text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try container.decodeIfPresent(String.self, forKey: .text),
            firstOf: try container.decodeIfPresent([String].self, forKey: .firstOf) ?? [],
            dropPrefixes: try container.decodeIfPresent([Prefix].self, forKey: .dropPrefixes) ?? [],
            firstWord: try container.decodeIfPresent(Bool.self, forKey: .firstWord) ?? false,
            lowercase: try container.decodeIfPresent(Bool.self, forKey: .lowercase) ?? false
        )
    }
}

/// The failure a rule reports, as one of today's `UsageError`s.
public enum ErrorRef: Sendable, Equatable, Codable {
    case authenticationRequired
    case updateRequired
    case folderTrustRequired
    case subscriptionRequired
    case noData
    case parseFailed(String)
    case sessionExpired(String?)
    case executionFailed(String)
    /// *CLI not found*, naming the CLI the person should install.
    case cliNotFound(String)

    public var usageError: UsageError {
        switch self {
        case .authenticationRequired: .authenticationRequired
        case .updateRequired: .updateRequired
        case .folderTrustRequired: .folderTrustRequired
        case .subscriptionRequired: .subscriptionRequired
        case .noData: .noData
        case .parseFailed(let reason): .parseFailed(reason)
        case .sessionExpired(let hint): .sessionExpired(hint: hint)
        case .executionFailed(let reason): .executionFailed(reason)
        case .cliNotFound(let name): .cliNotFound(name)
        }
    }

    public init(from decoder: Decoder) throws {
        if let tag = try? decoder.singleValueContainer().decode(String.self) {
            switch tag {
            case "authenticationRequired": self = .authenticationRequired
            case "updateRequired": self = .updateRequired
            case "folderTrustRequired": self = .folderTrustRequired
            case "subscriptionRequired": self = .subscriptionRequired
            case "noData": self = .noData
            case "sessionExpired": self = .sessionExpired(nil)
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown error '\(tag)'"))
            }
            return
        }
        let container = try decoder.container(keyedBy: TagKey.self)
        let tag = try container.singleTag(of: ["parseFailed", "sessionExpired", "executionFailed", "cliNotFound"], in: "error")
        let text = try container.decode(String.self, forKey: TagKey(tag))
        switch tag {
        case "parseFailed": self = .parseFailed(text)
        case "cliNotFound": self = .cliNotFound(text)
        case "executionFailed": self = .executionFailed(text)
        default: self = .sessionExpired(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .parseFailed(let reason):
            var container = encoder.container(keyedBy: TagKey.self)
            try container.encode(reason, forKey: TagKey("parseFailed"))
        case .sessionExpired(let hint?):
            var container = encoder.container(keyedBy: TagKey.self)
            try container.encode(hint, forKey: TagKey("sessionExpired"))
        case .executionFailed(let reason):
            var container = encoder.container(keyedBy: TagKey.self)
            try container.encode(reason, forKey: TagKey("executionFailed"))
        case .cliNotFound(let name):
            var container = encoder.container(keyedBy: TagKey.self)
            try container.encode(name, forKey: TagKey("cliNotFound"))
        default:
            var container = encoder.singleValueContainer()
            let tag: String = switch self {
            case .authenticationRequired: "authenticationRequired"
            case .updateRequired: "updateRequired"
            case .folderTrustRequired: "folderTrustRequired"
            case .subscriptionRequired: "subscriptionRequired"
            case .noData: "noData"
            default: "sessionExpired"
            }
            try container.encode(tag)
        }
    }
}

// MARK: - JSON mapping

/// Reads a JSON response by paths — *Used · Remaining · Limit · Resets*.
public struct JSONMapping: Sendable, Equatable, Codable {
    public let plan: PlanRule?
    public let quotas: [QuotaRule]
    /// The first that answers — one rule, or a list of shapes a provider
    /// has used over time.
    public let cost: [CostRule]
    /// What to do when no quota answered.
    public let whenEmpty: EmptyRule?
    /// The account's email — the first path that answers, `$credential.` included.
    public let email: [String]
    /// The `parseFailed` reason when the body is JSON but not an object.
    public let notAnObject: String?

    public init(
        plan: PlanRule? = nil,
        quotas: [QuotaRule],
        cost: [CostRule] = [],
        whenEmpty: EmptyRule? = nil,
        email: [String] = [],
        notAnObject: String? = nil
    ) {
        self.plan = plan
        self.quotas = quotas
        self.cost = cost
        self.whenEmpty = whenEmpty
        self.email = email
        self.notAnObject = notAnObject
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decodeIfPresent(PlanRule.self, forKey: .plan)
        quotas = try container.decodeIfPresent([QuotaRule].self, forKey: .quotas) ?? []
        if let list = try? container.decodeIfPresent([CostRule].self, forKey: .cost) {
            cost = list
        } else {
            cost = try container.decodeIfPresent(CostRule.self, forKey: .cost).map { [$0] } ?? []
        }
        whenEmpty = try container.decodeIfPresent(EmptyRule.self, forKey: .whenEmpty)
        notAnObject = try container.decodeIfPresent(String.self, forKey: .notAnObject)
        if let one = try? container.decodeIfPresent(String.self, forKey: .email) {
            email = [one]
        } else {
            email = try container.decodeIfPresent([String].self, forKey: .email) ?? []
        }
    }
}

/// One quota — or, with `each`, one per element of an array or map.
public struct QuotaRule: Sendable, Equatable, Codable {
    /// A sub-object to read per element, and the suffix its quota's name gets
    /// ("Spark" · "Spark 7d").
    public struct WindowPick: Sendable, Equatable, Codable {
        public let at: String
        public let suffix: String

        public init(at: String, suffix: String = "") {
            self.at = at
            self.suffix = suffix
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            at = try container.decode(String.self, forKey: .at)
            suffix = try container.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        }
    }

    public let kind: QuotaKind
    public let name: NameRule?
    /// The object the values are read from.
    public let at: String?
    /// Repeat over this array, or this map in key order.
    public let each: String?
    /// Map keys not to repeat over.
    public let skipKeys: [String]
    /// Per element, read these sub-objects instead of the element itself.
    public let windows: [WindowPick]
    public let usedPercent: [ValueRef]
    public let leftPercent: [ValueRef]
    public let resetsAt: [ResetRef]
    /// The first that answers — what the response states, then a length the
    /// provider is known for.
    public let window: [DurationRef]
    /// Fixed text in place of the reset countdown ("Free plan").
    public let resetText: String?
    /// With `each`: only the elements where this holds.
    public let `where`: Match?
    /// Over the limit reads as negative left, as the provider reports it,
    /// instead of 0.
    public let overLimit: Bool
    /// How the reset countdown is written.
    public let countdown: Countdown
    /// Skip a quota whose kind and name an earlier rule already produced —
    /// the first one wins.
    public let unique: Bool
    /// Money in place of a percentage — "$12.40 remaining", "of $50.00".
    /// Without `of` it is a balance: no percentage at all.
    public let left: MoneyLeft?

    /// `{ "money": "$.remaining", "of": "$.limit", "currency": "USD" }`.
    public struct MoneyLeft: Sendable, Equatable, Codable {
        public let money: Amount
        public let of: Amount?
        /// ISO 4217; USD when absent.
        public let currency: String?

        public init(money: Amount, of ceiling: Amount? = nil, currency: String? = nil) {
            self.money = money
            self.of = ceiling
            self.currency = currency
        }
    }

    /// `days` — "Resets in 2d 5h 30m"; `hours` — "Resets in 53h 30m".
    public enum Countdown: String, Sendable, Equatable, Codable {
        case days
        case hours
    }

    enum CodingKeys: String, CodingKey {
        case kind, name, at, each, skipKeys, windows, usedPercent, leftPercent, resetsAt, window, resetText
        case `where`, overLimit, countdown, unique, left
    }

    public init(
        kind: QuotaKind,
        name: NameRule? = nil,
        at: String? = nil,
        each: String? = nil,
        skipKeys: [String] = [],
        windows: [WindowPick] = [],
        usedPercent: [ValueRef] = [],
        leftPercent: [ValueRef] = [],
        resetsAt: [ResetRef] = [],
        window: [DurationRef] = [],
        resetText: String? = nil,
        where condition: Match? = nil,
        overLimit: Bool = false,
        countdown: Countdown = .days,
        unique: Bool = false,
        left: MoneyLeft? = nil
    ) {
        self.kind = kind
        self.name = name
        self.at = at
        self.each = each
        self.skipKeys = skipKeys
        self.windows = windows
        self.usedPercent = usedPercent
        self.leftPercent = leftPercent
        self.resetsAt = resetsAt
        self.window = window
        self.resetText = resetText
        self.where = condition
        self.overLimit = overLimit
        self.countdown = countdown
        self.unique = unique
        self.left = left
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(QuotaKind.self, forKey: .kind)
        name = try container.decodeIfPresent(NameRule.self, forKey: .name)
        at = try container.decodeIfPresent(String.self, forKey: .at)
        each = try container.decodeIfPresent(String.self, forKey: .each)
        skipKeys = try container.decodeIfPresent([String].self, forKey: .skipKeys) ?? []
        windows = try container.decodeIfPresent([WindowPick].self, forKey: .windows) ?? []
        usedPercent = try Self.decodeList(ValueRef.self, container, .usedPercent)
        leftPercent = try Self.decodeList(ValueRef.self, container, .leftPercent)
        resetsAt = try Self.decodeList(ResetRef.self, container, .resetsAt)
        window = try Self.decodeList(DurationRef.self, container, .window)
        resetText = try container.decodeIfPresent(String.self, forKey: .resetText)
        self.where = try container.decodeIfPresent(Match.self, forKey: .where)
        overLimit = try container.decodeIfPresent(Bool.self, forKey: .overLimit) ?? false
        countdown = try container.decodeIfPresent(Countdown.self, forKey: .countdown) ?? .days
        unique = try container.decodeIfPresent(Bool.self, forKey: .unique) ?? false
        left = try container.decodeIfPresent(MoneyLeft.self, forKey: .left)
    }

    /// One value or a list of them — `"used_percent"` or `["$header.x", "used_percent"]`.
    private static func decodeList<T: Decodable>(_ type: T.Type, _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [T] {
        if let list = try? container.decodeIfPresent([T].self, forKey: key) { return list }
        return try container.decodeIfPresent(T.self, forKey: key).map { [$0] } ?? []
    }
}

/// The plan badge — "PLUS", "PRO" — from a field (`$credential.` included),
/// upper-cased unless `badges` names it. With `plans`, a value is one of the
/// well-known plans by name (`claudeMax`, `claudePro`, `claudeApi`), and any
/// other is kept as written.
public struct PlanRule: Sendable, Equatable, Codable {
    public let path: String
    public let badges: [String: String]
    public let plans: [String: String]

    public init(path: String, badges: [String: String] = [:], plans: [String: String] = [:]) {
        self.path = path
        self.badges = badges
        self.plans = plans
    }

    public init(from decoder: Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self.init(path: path)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            badges: try container.decodeIfPresent([String: String].self, forKey: .badges) ?? [:],
            plans: try container.decodeIfPresent([String: String].self, forKey: .plans) ?? [:]
        )
    }
}

/// Money gone — "EXTRA USAGE" or "API COST" — from what is left of a limit,
/// or what was used. The rule answers nothing when `when` does not hold, when
/// nothing was used, or when a limit is present but not money.
public struct CostRule: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case apiCost
        case extraUsage
    }

    public let kind: Kind
    public let when: Match?
    public let remaining: [ValueRef]
    public let used: Amount?
    public let limit: Amount?

    enum CodingKeys: String, CodingKey {
        case kind, when, remaining, used, limit
    }

    public init(kind: Kind = .apiCost, when: Match? = nil, remaining: [ValueRef] = [], used: Amount? = nil, limit: Amount? = nil) {
        self.kind = kind
        self.when = when
        self.remaining = remaining
        self.used = used
        self.limit = limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .apiCost
        when = try container.decodeIfPresent(Match.self, forKey: .when)
        if let list = try? container.decodeIfPresent([ValueRef].self, forKey: .remaining) {
            remaining = list
        } else {
            remaining = try container.decodeIfPresent(ValueRef.self, forKey: .remaining).map { [$0] } ?? []
        }
        used = try container.decodeIfPresent(Amount.self, forKey: .used)
        limit = try container.decodeIfPresent(Amount.self, forKey: .limit)
    }
}

/// An amount of money: a number in the currency — `"used"` or a list, the
/// first that answers — or minor units shifted by a number of decimal places,
/// `{ "amount": "used.amount_minor", "decimals": "used.exponent" }`. Minor
/// units are read exactly; a negative amount or a fractional or negative
/// `decimals` is not money.
public enum Amount: Sendable, Equatable, Codable {
    case value([ValueRef])
    case minorUnits(amount: String, decimals: [ValueRef])

    private enum Keys: String, CodingKey { case amount, decimals }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: Keys.self),
           let amount = try? container.decode(String.self, forKey: .amount) {
            let decimals: [ValueRef]
            if let list = try? container.decodeIfPresent([ValueRef].self, forKey: .decimals) {
                decimals = list
            } else {
                decimals = try container.decodeIfPresent(ValueRef.self, forKey: .decimals).map { [$0] } ?? []
            }
            self = .minorUnits(amount: amount, decimals: decimals)
        } else if let list = try? decoder.singleValueContainer().decode([ValueRef].self) {
            self = .value(list)
        } else {
            self = .value([try decoder.singleValueContainer().decode(ValueRef.self)])
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .value(let refs):
            var container = encoder.singleValueContainer()
            try container.encode(refs)
        case .minorUnits(let amount, let decimals):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(amount, forKey: .amount)
            try container.encode(decimals, forKey: .decimals)
        }
    }
}

/// `{ "path": "kind", "equals": "weekly_scoped" }` — a value in the response
/// equals this JSON value.
public struct Match: Sendable, Equatable, Codable {
    public let path: String
    public let equals: JSONValue

    public init(path: String, equals: JSONValue) {
        self.path = path
        self.equals = equals
    }
}

/// When nothing answered: fixed quotas if a field says so, otherwise a failure.
public struct EmptyRule: Sendable, Equatable, Codable {
    public struct Condition: Sendable, Equatable, Codable {
        public let path: String
        public let equals: String

        public init(path: String, equals: String) {
            self.path = path
            self.equals = equals
        }
    }

    public let condition: Condition?
    public let quotas: [QuotaRule]
    /// The `parseFailed` reason when the condition does not hold.
    public let otherwise: String?

    public init(condition: Condition? = nil, quotas: [QuotaRule] = [], otherwise: String? = nil) {
        self.condition = condition
        self.quotas = quotas
        self.otherwise = otherwise
    }

    enum CodingKeys: String, CodingKey {
        case condition = "if"
        case quotas
        case otherwise
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        condition = try container.decodeIfPresent(Condition.self, forKey: .condition)
        quotas = try container.decodeIfPresent([QuotaRule].self, forKey: .quotas) ?? []
        otherwise = try container.decodeIfPresent(String.self, forKey: .otherwise)
    }
}

// MARK: - Text mapping

/// Reads a terminal screen by patterns: errors first, then each quota's label
/// and the percentage within a few lines of it.
public struct TextMapping: Sendable, Equatable, Codable {
    public struct ErrorRule: Sendable, Equatable, Codable {
        /// Any of these phrases (case-insensitive)…
        public let contains: [String]
        /// …and all of these, when given.
        public let alsoContains: [String]
        public let error: ErrorRef

        public init(contains: [String], alsoContains: [String] = [], error: ErrorRef) {
            self.contains = contains
            self.alsoContains = alsoContains
            self.error = error
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contains = try container.decode([String].self, forKey: .contains)
            alsoContains = try container.decodeIfPresent([String].self, forKey: .alsoContains) ?? []
            error = try container.decode(ErrorRef.self, forKey: .error)
        }
    }

    public struct QuotaPattern: Sendable, Equatable, Codable {
        public let kind: QuotaKind
        public let name: String?
        /// The line that names the quota (case-insensitive substring).
        public let label: String
        /// A regex whose first group is the percentage **left**.
        public let leftPercent: String?
        /// A regex whose first group is the percentage **used**.
        public let usedPercent: String?
        /// How many lines from the label to look.
        public let lookahead: Int

        public init(kind: QuotaKind, name: String? = nil, label: String, leftPercent: String? = nil, usedPercent: String? = nil, lookahead: Int = 12) {
            self.kind = kind
            self.name = name
            self.label = label
            self.leftPercent = leftPercent
            self.usedPercent = usedPercent
            self.lookahead = lookahead
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(QuotaKind.self, forKey: .kind)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            label = try container.decode(String.self, forKey: .label)
            leftPercent = try container.decodeIfPresent(String.self, forKey: .leftPercent)
            usedPercent = try container.decodeIfPresent(String.self, forKey: .usedPercent)
            lookahead = try container.decodeIfPresent(Int.self, forKey: .lookahead) ?? 12
        }
    }

    public let errors: [ErrorRule]
    public let quotas: [QuotaPattern]
    /// The `parseFailed` reason when no quota is found.
    public let whenEmpty: String?

    public init(errors: [ErrorRule] = [], quotas: [QuotaPattern], whenEmpty: String? = nil) {
        self.errors = errors
        self.quotas = quotas
        self.whenEmpty = whenEmpty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = try container.decodeIfPresent([ErrorRule].self, forKey: .errors) ?? []
        quotas = try container.decode([QuotaPattern].self, forKey: .quotas)
        whenEmpty = try container.decodeIfPresent(String.self, forKey: .whenEmpty)
    }
}

// MARK: - JSON

extension Mapping: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        switch try container.singleTag(of: ["json", "text", "script"], in: "mapping") {
        case "json": self = .json(try container.decode(JSONMapping.self, forKey: TagKey("json")))
        case "script": self = .script(try container.decode(ScriptMapping.self, forKey: TagKey("script")))
        default: self = .text(try container.decode(TextMapping.self, forKey: TagKey("text")))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .json(let mapping): try container.encode(mapping, forKey: TagKey("json"))
        case .text(let mapping): try container.encode(mapping, forKey: TagKey("text"))
        case .script(let mapping): try container.encode(mapping, forKey: TagKey("script"))
        }
    }
}
