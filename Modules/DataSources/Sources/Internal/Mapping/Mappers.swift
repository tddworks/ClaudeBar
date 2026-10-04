import Diagnostics
import Quotas
import Foundation

/// `json` — reads a JSON response by paths into today's `UsageSnapshot`.
struct JSONMapper: Reading {
    let mapping: JSONMapping
    let now: @Sendable () -> Date

    func read(_ response: Response, facts: MappingFacts, providerId: String) throws -> UsageSnapshot {
        guard let document = try? JSONSerialization.jsonObject(with: response.body) else {
            throw UsageError.parseFailed("Response is not JSON")
        }
        if let reason = mapping.notAnObject, !(document is [String: Any]) {
            throw UsageError.parseFailed(reason)
        }
        let scope = JSONScope(root: document, headers: response.headers, credential: facts.credential)

        var quotas: [UsageQuota] = []
        for rule in mapping.quotas {
            var made = self.quotas(for: rule, in: scope, providerId: providerId)
            if rule.unique {
                var seen = Set(quotas.map(\.quotaType))
                made = made.filter { seen.insert($0.quotaType).inserted }
            }
            quotas += made
        }
        if quotas.isEmpty, let empty = mapping.whenEmpty {
            if let condition = empty.condition, scope.string(condition.path) == condition.equals {
                quotas = empty.quotas.flatMap { self.quotas(for: $0, in: scope, providerId: providerId) }
            } else if let reason = empty.otherwise {
                throw UsageError.parseFailed(reason)
            }
        }

        // Nothing answering is not a failure unless `whenEmpty` says so: a
        // provider that has no usage yet reports none (*No usage data*).
        let cost = mapping.cost.lazy.compactMap { self.cost(for: $0, in: scope, providerId: providerId) }.first

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: now(),
            accountEmail: mapping.email.lazy.compactMap { scope.string($0) }.first { !$0.isEmpty },
            accountTier: mapping.plan.flatMap { plan(for: $0, in: scope) },
            costUsage: cost
        )
    }

    // MARK: - Quotas

    private func quotas(for rule: QuotaRule, in scope: JSONScope, providerId: String) -> [UsageQuota] {
        let base = rule.at.map { scope.moved(to: scope.value($0)) } ?? scope
        guard let each = rule.each else {
            return quota(for: rule, named: rule.name?.text, in: base, providerId: providerId).map { [$0] } ?? []
        }

        var elements: [JSONScope] = []
        switch base.value(each) {
        case let array as [Any]:
            elements = array.map { base.moved(to: $0) }
        case let map as [String: Any]:
            elements = map.keys.sorted()
                .filter { !rule.skipKeys.contains($0) }
                .map { base.moved(to: map[$0], key: $0) }
        default:
            return []
        }
        if let condition = rule.where {
            elements = elements.filter { Self.holds(condition, in: $0) }
        }

        return elements.flatMap { element -> [UsageQuota] in
            guard let name = self.name(rule.name, in: element), !name.isEmpty else { return [] }
            let windows = rule.windows.isEmpty ? [QuotaRule.WindowPick(at: "")] : rule.windows
            return windows.compactMap { pick in
                let windowScope = pick.at.isEmpty ? element : element.moved(to: element.value(pick.at))
                return quota(for: rule, named: name + pick.suffix, in: windowScope, providerId: providerId)
            }
        }
    }

    private func quota(for rule: QuotaRule, named name: String?, in scope: JSONScope, providerId: String) -> UsageQuota? {
        if let money = rule.left {
            return moneyQuota(money, for: rule, named: name, in: scope, providerId: providerId)
        }
        let left: Double
        if let used = first(rule.usedPercent, in: scope) {
            left = rule.overLimit ? 100 - used : max(0, 100 - used)
        } else if let remaining = first(rule.leftPercent, in: scope) {
            left = remaining
        } else {
            return nil
        }

        let resetsAt = rule.resetsAt.lazy.compactMap { self.date($0, in: scope) }.first
        let windowDuration = windowLength(rule, in: scope)

        guard let type = Self.quotaType(rule.kind, name: name) else { return nil }
        return UsageQuota(
            percentRemaining: left,
            quotaType: type,
            providerId: providerId,
            resetsAt: resetsAt,
            resetText: rule.resetText ?? resetsAt.flatMap { countdown(rule.countdown, until: $0) },
            windowDuration: windowDuration
        )
    }

    private func countdown(_ style: QuotaRule.Countdown, until date: Date) -> String? {
        switch style {
        case .days: Countdown.text(until: date, now: now())
        case .hours: Countdown.hoursText(until: date, now: now())
        }
    }

    /// Money left — of a ceiling, or a balance with no percentage at all.
    private func moneyQuota(_ rule: QuotaRule.MoneyLeft, for quotaRule: QuotaRule, named name: String?, in scope: JSONScope, providerId: String) -> UsageQuota? {
        guard let type = Self.quotaType(quotaRule.kind, name: name),
              let remaining = money(rule.money, in: scope) else { return nil }
        let currency = rule.currency ?? "USD"
        var ceiling: Money?
        if let of = rule.of, isPresent(of, in: scope) {
            guard let amount = money(of, in: scope) else { return nil }
            ceiling = Money(amount, currency: currency)
        }
        let resetsAt = quotaRule.resetsAt.lazy.compactMap { self.date($0, in: scope) }.first
        return UsageQuota(
            left: .money(Money(remaining, currency: currency), of: ceiling),
            quotaType: type,
            providerId: providerId,
            resetsAt: resetsAt,
            resetText: quotaRule.resetText ?? resetsAt.flatMap { countdown(quotaRule.countdown, until: $0) },
            windowDuration: windowLength(quotaRule, in: scope)
        )
    }

    private func windowLength(_ rule: QuotaRule, in scope: JSONScope) -> TimeInterval? {
        rule.window.lazy.compactMap { ref -> TimeInterval? in
            switch ref {
            case .seconds(let path): scope.number(path)
            case .minutes(let path): scope.number(path).map { $0 * 60 }
            case .fixed(let seconds): seconds
            }
        }.first
    }

    static func quotaType(_ kind: QuotaKind, name: String?) -> QuotaType? {
        switch kind {
        case .session: return .session
        case .weekly: return .weekly
        case .model: return name.map { .modelSpecific($0) }
        case .time: return name.map { .timeLimit($0) }
        }
    }

    private func name(_ rule: NameRule?, in scope: JSONScope) -> String? {
        guard let rule else { return nil }
        if let text = rule.text { return text }
        guard let raw = rule.firstOf.lazy.compactMap({ scope.string($0) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        var name = raw.trimmingCharacters(in: .whitespaces)
        if rule.firstWord {
            name = name.split(separator: " ").first.map(String.init) ?? ""
        }
        if rule.lowercase {
            name = name.lowercased()
        }
        for drop in rule.dropPrefixes where name.lowercased().hasPrefix(drop.prefix.lowercased()) {
            let rest = String(name.dropFirst(drop.prefix.count))
            guard !rest.isEmpty else { return name }
            return drop.capitalize ? rest.prefix(1).uppercased() + rest.dropFirst() : rest
        }
        return name
    }

    /// Whether the value at the condition's path equals its JSON value.
    static func holds(_ condition: Match, in scope: JSONScope) -> Bool {
        let value = scope.value(condition.path)
        switch condition.equals {
        case .string(let text): return value as? String == text
        case .number(let number): return JSONPath.number(value) == number && !(value is String)
        case .bool(let flag):
            guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
            return value.boolValue == flag
        case .null: return value == nil || value is NSNull
        case .object, .array:
            guard let value = value as? NSObject, let expected = condition.equals.foundationObject as? NSObject else { return false }
            return value.isEqual(expected)
        }
    }

    // MARK: - Values

    private func first(_ refs: [ValueRef], in scope: JSONScope) -> Double? {
        for ref in refs {
            switch ref {
            case .constant(let value): return value
            case .path(let path): if let value = scope.number(path) { return value }
            }
        }
        return nil
    }

    private func date(_ ref: ResetRef, in scope: JSONScope) -> Date? {
        switch ref {
        case .epochSeconds(let path):
            return scope.number(path).map { Date(timeIntervalSince1970: $0) }
        case .secondsFromNow(let path):
            return scope.number(path).map { now().addingTimeInterval($0) }
        case .iso8601(let path):
            return scope.string(path).flatMap(OAuth2Refresher.parseDate)
        }
    }

    private func plan(for rule: PlanRule, in scope: JSONScope) -> AccountTier? {
        guard let value = scope.string(rule.path), !value.isEmpty else { return nil }
        if !rule.plans.isEmpty {
            return ScriptOutput.tier(rule.plans[value.lowercased()] ?? value)
        }
        return .custom(rule.badges[value.lowercased()] ?? value.uppercased())
    }

    private func cost(for rule: CostRule, in scope: JSONScope, providerId: String) -> CostUsage? {
        if let condition = rule.when, !Self.holds(condition, in: scope) { return nil }
        // A limit that is there but is not money drops the rule: an invalid
        // cap must not read as "no cap".
        var limit: Decimal?
        if let amount = rule.limit, isPresent(amount, in: scope) {
            guard let money = money(amount, in: scope) else { return nil }
            limit = money
        }
        let used: Decimal
        if let amount = rule.used {
            guard let money = money(amount, in: scope) else { return nil }
            used = money
        } else if let remaining = first(rule.remaining, in: scope), let limit {
            used = max(0, min(limit, limit - Decimal(remaining)))
        } else {
            return nil
        }
        return CostUsage(
            totalCost: used,
            budget: limit,
            apiDuration: 0,
            providerId: providerId,
            kind: rule.kind == .extraUsage ? .extraUsage : .apiCost,
            capturedAt: now()
        )
    }

    private func isPresent(_ amount: Amount, in scope: JSONScope) -> Bool {
        switch amount {
        case .value(let refs):
            refs.contains { if case .path(let path) = $0 { scope.value(path) != nil } else { true } }
        case .minorUnits(let path, _):
            scope.value(path) != nil
        }
    }

    private func money(_ amount: Amount, in scope: JSONScope) -> Decimal? {
        switch amount {
        case .value(let refs):
            // Read a path's number from its own text, so 12.4 stays 12.4.
            for ref in refs {
                switch ref {
                case .constant(let value):
                    return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
                case .path(let path):
                    if let number = scope.value(path) as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                        return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
                    }
                    // An amount sent as text stays exact — decimal text only, never hex.
                    if let text = (scope.value(path) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       text.range(of: #"^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil {
                        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
                    }
                }
            }
            return nil
        case .minorUnits(let path, let decimals):
            guard let number = scope.value(path) as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let minor = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
                  minor >= 0,
                  let places = first(decimals, in: scope),
                  places >= 0, places.rounded() == places, places <= 38 else { return nil }
            return minor / pow(Decimal(10), Int(places))
        }
    }
}

/// `text` — reads a terminal screen: a known error phrase fails the read;
/// otherwise each quota's label and the percentage within a few lines of it.
struct TextMapper: Reading {
    let mapping: TextMapping
    let now: @Sendable () -> Date

    func read(_ response: Response, facts: MappingFacts, providerId: String) throws -> UsageSnapshot {
        let screen = Self.stripANSI(response.text)
        let lower = screen.lowercased()

        for rule in mapping.errors {
            let any = rule.contains.contains { lower.contains($0.lowercased()) }
            let all = rule.alsoContains.allSatisfy { lower.contains($0.lowercased()) }
            if any && all {
                AppLog.probes.error("\(providerId) screen reports: \(rule.contains.first ?? "an error")")
                throw rule.error.usageError
            }
        }

        let lines = screen.components(separatedBy: .newlines)
        let quotas = mapping.quotas.compactMap { pattern -> UsageQuota? in
            guard let type = JSONMapper.quotaType(pattern.kind, name: pattern.name) else { return nil }
            if let regex = pattern.leftPercent, let left = Self.percent(after: pattern.label, matching: regex, within: pattern.lookahead, in: lines) {
                return UsageQuota(percentRemaining: left, quotaType: type, providerId: providerId)
            }
            if let regex = pattern.usedPercent, let used = Self.percent(after: pattern.label, matching: regex, within: pattern.lookahead, in: lines) {
                return UsageQuota(percentRemaining: max(0, 100 - used), quotaType: type, providerId: providerId)
            }
            return nil
        }

        guard !quotas.isEmpty else {
            throw UsageError.parseFailed(mapping.whenEmpty ?? "Could not find usage limits")
        }
        return UsageSnapshot(providerId: providerId, quotas: quotas, capturedAt: now())
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#, with: "", options: .regularExpression)
    }

    static func percent(after label: String, matching pattern: String, within lookahead: Int, in lines: [String]) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let label = label.lowercased()
        for (index, line) in lines.enumerated() where line.lowercased().contains(label) {
            for candidate in lines[index..<min(lines.count, index + lookahead)] {
                let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                if let match = regex.firstMatch(in: candidate, range: range),
                   match.numberOfRanges >= 2,
                   let value = Range(match.range(at: 1), in: candidate),
                   let number = Double(candidate[value]) {
                    return number
                }
            }
        }
        return nil
    }
}

/// "Resets in 2d 5h 30m" — the countdown a CLI's screen shows as `resetText`.
enum Countdown {
    static func text(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Resets soon" }
        let days = Int(interval / 86400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if days > 0 { return "Resets in \(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        if minutes > 0 { return "Resets in \(minutes)m" }
        return "Resets soon"
    }

    /// The same in hours, never days — "Resets in 53h 30m". `nil` once past.
    static func hoursText(until date: Date, now: Date) -> String? {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        if minutes > 0 { return "Resets in \(minutes)m" }
        return "Resets soon"
    }
}
