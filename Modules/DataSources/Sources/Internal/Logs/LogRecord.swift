import Foundation

/// One usage record, whatever log it came from — the shape every reader
/// yields, so nothing after the reader knows which tool wrote it.
struct LogRecord: Sendable, Equatable {
    let at: Date
    /// The record's identity, when every `id` path answered; `nil` is never
    /// merged with another record.
    let id: String?
    let model: String?
    let input: Int
    let output: Int
    let cacheWrite: Int
    /// The part of `cacheWrite` kept an hour.
    let cacheWrite1h: Int
    let cacheRead: Int
    /// The log's own sum, when it keeps only that.
    let total: Int?
    /// The log's own cost, which wins over any price.
    let cost: Decimal?

    init(at: Date, id: String? = nil, model: String? = nil, input: Int = 0, output: Int = 0,
         cacheWrite: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0, total: Int? = nil, cost: Decimal? = nil) {
        self.at = at
        self.id = id
        self.model = model
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheWrite1h = min(cacheWrite1h, cacheWrite)
        self.cacheRead = cacheRead
        self.total = total
        self.cost = cost
    }

    /// Input and output — what *TODAY'S USAGE* counts as tokens.
    var tokens: Int { total ?? input + output }

    /// Records written twice count once: the **last** copy of an identity
    /// wins (a streamed message is logged as it grows), kept where it was
    /// first seen. A record with no identity is always kept.
    static func deduplicated(_ records: [LogRecord]) -> [LogRecord] {
        var last: [String: LogRecord] = [:]
        var order: [Either] = []
        for record in records {
            if let id = record.id {
                if last[id] == nil { order.append(.keyed(id)) }
                last[id] = record
            } else {
                order.append(.bare(record))
            }
        }
        return order.compactMap { entry in
            switch entry {
            case .keyed(let id): last[id]
            case .bare(let record): record
            }
        }
    }

    private enum Either {
        case keyed(String)
        case bare(LogRecord)
    }
}

/// How one record reads, from a definition's `records`: the paths, the
/// filter, and the bytes a line must hold before it is decoded.
struct RecordShape: Sendable {
    let records: UsageLog.Records

    init(_ records: UsageLog.Records) {
        self.records = records
    }

    /// The `where` texts, quoted as JSON writes them: a line without one
    /// can't match, so it is skipped undecoded. Inside a JSON string the
    /// quotes would be escaped, so a quoted mention never matches.
    var requiredFragments: [[UInt8]] {
        guard case .string(let text)? = records.where?.equals else { return [] }
        return [Array("\"\(text)\"".utf8)]
    }

    /// The record in `json`, read from the file at `path`, or `nil` when it
    /// doesn't match, has no time or declared model, or says nothing about usage.
    func record(from json: Any, path: String = "") -> LogRecord? {
        let scope = JSONScope(root: json)
        if let condition = records.where, !JSONMapper.holds(condition, in: scope) { return nil }
        guard let at = time(in: scope, path: path) else { return nil }
        var model: String?
        if let path = records.model {
            guard let name = scope.string(path) else { return nil }
            model = name
        }
        let tokens = records.tokens
        let counts = [tokens.input, tokens.output, tokens.cacheWrite, tokens.cacheRead, tokens.total, tokens.cacheWrite1h]
            .map { path in path.flatMap { scope.number($0) }.map { Int($0) } }
        let cost = records.cost.flatMap { Self.decimal(scope.value($0)) }
        // A record that says nothing about usage isn't usage.
        guard counts.prefix(5).contains(where: { $0 != nil }) || cost != nil else { return nil }
        let parts = records.id.map { scope.string($0) }
        let id = parts.isEmpty || parts.contains(nil) ? nil : parts.compactMap { $0 }.joined(separator: "\u{1F}")
        return LogRecord(at: at, id: id, model: model,
                         input: counts[0] ?? 0, output: counts[1] ?? 0, cacheWrite: counts[2] ?? 0,
                         cacheWrite1h: counts[5] ?? 0, cacheRead: counts[3] ?? 0, total: counts[4], cost: cost)
    }

    private func time(in scope: JSONScope, path: String) -> Date? {
        switch records.at {
        case .field(let field): Self.date(scope.value(field))
        case .fromPath(let rule): Self.date(inPath: path, rule)
        }
    }

    /// The first capture of the rule's pattern in `path`, read with its format.
    static func date(inPath path: String, _ rule: UsageLog.At.FromPath) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = rule.format
        formatter.timeZone = rule.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        return formatter.date(from: String(path[range]))
    }

    /// ISO 8601 text, or epoch seconds.
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String { return ISO8601Instant.parse(text) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    /// An amount as written — text or number — read as an exact `Decimal`.
    static func decimal(_ value: Any?) -> Decimal? {
        let text: String
        switch value {
        case let string as String: text = string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): text = number.stringValue
        default: return nil
        }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}
