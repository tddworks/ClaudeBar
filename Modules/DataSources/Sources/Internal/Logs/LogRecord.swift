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

/// How one shape of a log's records reads: its filter, its paths, and the
/// bytes a line must hold for its `where` to have a chance.
struct RecordShape: Sendable {
    let shape: UsageLog.Shape

    init(_ shape: UsageLog.Shape) {
        self.shape = shape
    }

    /// The `where` text, quoted as JSON writes it, or `nil` when the shape has
    /// no text to look for. Inside a JSON string the quotes would be escaped,
    /// so a quoted mention never matches.
    var fragment: [UInt8]? {
        guard case .string(let text)? = shape.where?.equals else { return nil }
        return Array("\"\(text)\"".utf8)
    }

    /// Whether this shape's `where` holds for the record in `scope`.
    func picks(_ scope: JSONScope) -> Bool {
        shape.where.map { JSONMapper.holds($0, in: scope) } ?? true
    }

    /// The record in `scope` read whole from this shape's paths, from the file
    /// at `path`, or `nil` when it has no time or declared model, or says
    /// nothing about usage.
    func record(in scope: JSONScope, path: String) -> LogRecord? {
        guard let at = time(in: scope, path: path) else { return nil }
        var model: String?
        if let path = shape.model {
            guard let name = scope.string(path) else { return nil }
            model = name
        }
        let tokens = shape.tokens
        let read = [tokens.input, tokens.output, tokens.cacheWrite, tokens.cacheRead, tokens.total, tokens.cacheWrite1h]
            .map { path in path.flatMap { scope.number($0) } }
        // A count is a whole number of tokens: a negative or a fraction is a
        // log that changed shape, not usage.
        guard read.allSatisfy({ $0.map { $0 >= 0 && $0.rounded() == $0 } ?? true }) else { return nil }
        let counts = read.map { $0.map { Int($0) } }
        let cost = shape.cost.flatMap { Self.decimal(scope.value($0)) }
        // A record that says nothing about usage isn't usage.
        guard counts.prefix(5).contains(where: { $0 != nil }) || cost != nil else { return nil }
        let parts = shape.id.map { scope.string($0) }
        let id = parts.isEmpty || parts.contains(nil) ? nil : parts.compactMap { $0 }.joined(separator: "\u{1F}")
        var input = counts[0] ?? 0
        if tokens.inputIncludesCacheRead == true { input = max(0, input - (counts[3] ?? 0)) }
        return LogRecord(at: at, id: id, model: model,
                         input: input, output: counts[1] ?? 0, cacheWrite: counts[2] ?? 0,
                         cacheWrite1h: counts[5] ?? 0, cacheRead: counts[3] ?? 0, total: counts[4], cost: cost)
    }

    private func time(in scope: JSONScope, path: String) -> Date? {
        switch shape.at {
        case .field(let field): Self.date(scope.value(field))
        case .fromPath(let rule): Self.date(inPath: path, rule)
        case .formatted(let rule): scope.string(rule.field).flatMap { Self.date($0, format: rule.format, timeZone: rule.timeZone) }
        }
    }

    /// The first capture of the rule's pattern in `path`, read with its format.
    static func date(inPath path: String, _ rule: UsageLog.At.FromPath) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: path) else { return nil }
        return date(String(path[range]), format: rule.format, timeZone: rule.timeZone)
    }

    /// `text` read with `format` in `timeZone`, the user's own when `nil`.
    /// Text the format doesn't give back unchanged — `2026-02-30`, or a time
    /// after a bare day — has no time.
    static func date(_ text: String, format: String, timeZone: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
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

/// A log's shapes, in order: a record is read by the first whose `where`
/// holds, and by it alone.
extension [RecordShape] {
    /// A line must hold one of these — the shapes' `where` texts — before it is
    /// decoded; `nil` when a shape has none to look for, which reads every line.
    var fragments: [[UInt8]]? {
        var all: [[UInt8]] = []
        for shape in self {
            guard let fragment = shape.fragment else { return nil }
            all.append(fragment)
        }
        return all
    }

    /// The record in `json`, read from the file at `path`, or `nil` when no
    /// shape picks it out or the one that does can't read it.
    func record(from json: Any, path: String = "") -> LogRecord? {
        let scope = JSONScope(root: json)
        return first { $0.picks(scope) }?.record(in: scope, path: path)
    }
}
