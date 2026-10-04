import CryptoKit
import Diagnostics
import Foundation
import Quotas

/// HOW TO EXTRACT A LOGIN'S USAGE HISTORY — the one part that differs per
/// provider. Built from a definition's `usageHistory` block, filled with the
/// login's values: where its tool's logs are, how a record reads, what a
/// token costs. `days(in:)` reads and prices them into one stat per day
/// (TARGET_ARCHITECTURE §10).
///
/// Every reader yields the same record, so deduplication, days, sessions and
/// prices never learn which tool wrote the log.
public struct UsageLog: Sendable {
    let definition: Definition
    let reader: LogReader
    let prices: PriceList?
    let localEndpoint: LocalEndpoint?
    let files: String
    /// The local calendar its days are counted in.
    public let calendar: Calendar
    let now: @Sendable () -> Date
    /// Changes whenever how the logs read does — the definition, the price
    /// file, where the files are — so days kept under an older one are
    /// summed again.
    public let fingerprint: String

    /// The start of the day that holds now.
    public var today: Date { calendar.startOfDay(for: now()) }

    /// Now, as this log's clock tells it.
    public var currentTime: Date { now() }

    /// One stat per day of `range`, every date present; a day with nothing
    /// is an empty day. Unreadable files are skipped.
    public func days(in range: DateRange) async -> [DailyUsageStat] {
        let found = LogFileFinder.files(matching: files, changedSince: range.first)
        let raw = await reader.records(in: found)
        let scan = await reader.lastScan
        AppLog.probes.info("Usage history: scanned \(found.count) recent log files (\(scan.reused) unchanged, \(scan.extended) appended, \(scan.reparsed) read in full)")
        let records = LogRecord.deduplicated(raw)
        AppLog.probes.info("Usage history: \(raw.count) raw records, \(records.count) after dedup")

        // `freeWhen` describes the route now, so it prices only the day that
        // holds now: an earlier day keeps its estimate.
        let today = calendar.startOfDay(for: now())
        let freeDay = range.contains(today, calendar: calendar) && localEndpoint?.isLocal() == true ? today : nil
        if freeDay != nil {
            AppLog.probes.debug("Usage history: routed at a local endpoint — unpriced models cost nothing today")
        }
        return DayAggregator.days(records, in: range, calendar: calendar, sessionGap: definition.sessionGap,
                                  prices: prices, freeOn: freeDay)
    }

    /// The `count` days ending today.
    public func days(last count: Int) async -> [DailyUsageStat] {
        await days(in: .last(count, endingOn: now(), calendar: calendar))
    }
}

extension UsageLog {
    /// A definition's `usageHistory` block: the JSON, no behaviour.
    public struct Definition: Sendable, Equatable, Codable {
        public let records: Records
        /// What a token costs, when the log doesn't say.
        public let prices: Prices?
        public let freeWhen: FreeWhen?
        /// A pause longer than this many seconds starts a working session;
        /// without one, each record is a session and no working time is known.
        public let sessionGap: Double?

        public init(records: Records, prices: Prices? = nil, freeWhen: FreeWhen? = nil, sessionGap: Double? = nil) {
            self.records = records
            self.prices = prices
            self.freeWhen = freeWhen
            self.sessionGap = sessionGap
        }
    }

    /// Where the records are and how one reads, in the mapping's path language.
    public struct Records: Sendable, Equatable, Codable {
        /// A glob: `**` any depth, `*` within one name; `~` and `${VAR:-default}` expand.
        public let files: String
        public let format: Format
        /// Only the records where this holds; its text is also a byte prefilter.
        public let `where`: Match?
        /// When — a field (ISO 8601 text or epoch seconds), or the file's path.
        public let at: At
        /// Together, a record's identity: written twice, it counts once — the last wins.
        public let id: [String]
        public let model: String?
        public let tokens: Tokens
        /// The log's own cost, which wins over any price.
        public let cost: String?

        public init(files: String, format: Format = .jsonLines, where condition: Match? = nil, at: At,
                    id: [String] = [], model: String? = nil, tokens: Tokens = Tokens(), cost: String? = nil) {
            self.files = files
            self.format = format
            self.where = condition
            self.at = at
            self.id = id
            self.model = model
            self.tokens = tokens
            self.cost = cost
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                files: try container.decode(String.self, forKey: .files),
                format: try container.decodeIfPresent(Format.self, forKey: .format) ?? .jsonLines,
                where: try container.decodeIfPresent(Match.self, forKey: .where),
                at: try container.decode(At.self, forKey: .at),
                id: try container.decodeIfPresent([String].self, forKey: .id) ?? [],
                model: try container.decodeIfPresent(String.self, forKey: .model),
                tokens: try container.decodeIfPresent(Tokens.self, forKey: .tokens) ?? Tokens(),
                cost: try container.decodeIfPresent(String.self, forKey: .cost)
            )
        }

        private enum CodingKeys: String, CodingKey { case files, format, `where`, at, id, model, tokens, cost }
    }

    /// How a log is laid out — a closed list, one reader per case.
    public enum Format: String, Sendable, Equatable, Codable {
        /// One JSON object per line, appended to; read incrementally.
        case jsonLines
        /// One JSON document per file, one record.
        case json
    }

    /// When a record happened: a field of it, or — for a tool that names
    /// its files by time — the file's path.
    public enum At: Sendable, Equatable, Codable, ExpressibleByStringLiteral {
        /// A path to ISO 8601 text or epoch seconds.
        case field(String)
        case fromPath(FromPath)

        /// The time in a file's path: the first capture of `pattern`, read
        /// with `format` in `timeZone` — never as local time unless it says so.
        public struct FromPath: Sendable, Equatable, Codable {
            public let pattern: String
            public let format: String
            public let timeZone: String?

            public init(pattern: String, format: String, timeZone: String? = nil) {
                self.pattern = pattern
                self.format = format
                self.timeZone = timeZone
            }

            private enum CodingKeys: String, CodingKey {
                case pattern = "fromPath", format, timeZone
            }
        }

        public init(stringLiteral path: String) {
            self = .field(path)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let path = try? container.decode(String.self) {
                self = .field(path)
            } else {
                self = .fromPath(try container.decode(FromPath.self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .field(let path): try container.encode(path)
            case .fromPath(let rule): try container.encode(rule)
            }
        }
    }

    /// Token counts by kind; a missing one counts 0. `total` stands in when
    /// a log keeps only the sum.
    public struct Tokens: Sendable, Equatable, Codable {
        public let input: String?
        public let output: String?
        public let cacheWrite: String?
        /// The part of `cacheWrite` kept an hour, which costs more than a
        /// five-minute write.
        public let cacheWrite1h: String?
        public let cacheRead: String?
        public let total: String?

        public init(input: String? = nil, output: String? = nil, cacheWrite: String? = nil, cacheWrite1h: String? = nil,
                    cacheRead: String? = nil, total: String? = nil) {
            self.input = input
            self.output = output
            self.cacheWrite = cacheWrite
            self.cacheWrite1h = cacheWrite1h
            self.cacheRead = cacheRead
            self.total = total
        }
    }

    /// A price file shipped beside the definition.
    public struct Prices: Sendable, Equatable, Codable {
        public let file: String

        public init(file: String) {
            self.file = file
        }
    }

    public struct FreeWhen: Sendable, Equatable, Codable {
        public let localEndpoint: LocalEndpointRule?

        public init(localEndpoint: LocalEndpointRule?) {
            self.localEndpoint = localEndpoint
        }
    }

    /// An unpriced model costs nothing when a base URL in `file` is on this Mac.
    public struct LocalEndpointRule: Sendable, Equatable, Codable {
        public let file: String
        /// The first entry that answers decides; a list of paths is one entry,
        /// and `[*]` walks every element of a list.
        public let url: [[String]]

        public init(file: String, url: [[String]]) {
            self.file = file
            self.url = url
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            var entries = try container.nestedUnkeyedContainer(forKey: .url)
            var url: [[String]] = []
            while !entries.isAtEnd {
                if let path = try? entries.decode(String.self) {
                    url.append([path])
                } else {
                    url.append(try entries.decode([String].self))
                }
            }
            self.url = url
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(file, forKey: .file)
            var entries = container.nestedUnkeyedContainer(forKey: .url)
            for entry in url {
                if entry.count == 1 { try entries.encode(entry[0]) } else { try entries.encode(entry) }
            }
        }

        private enum CodingKeys: String, CodingKey { case file, url }
    }
}

extension DataSources {
    /// A login's usage log, reading this Mac's files. `scripts` finds the
    /// price file shipped beside the definition.
    public static func makeUsageLog(
        _ definition: UsageLog.Definition,
        scripts: @escaping ScriptSource = { _ in nil },
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> UsageLog {
        let expand = { (path: String) in Paths.expand(path, homeDirectory: homeDirectory, environment: environment) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var hash = SHA256()
        hash.update(data: (try? encoder.encode(definition)) ?? Data())
        hash.update(data: Data(expand(definition.records.files).utf8))
        hash.update(data: Data((definition.prices.flatMap { scripts($0.file) } ?? "").utf8))
        let fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return UsageLog(
            definition: definition,
            reader: LogReader(definition.records),
            prices: definition.prices.flatMap { PriceList.load($0.file, from: scripts) },
            localEndpoint: definition.freeWhen?.localEndpoint.map { LocalEndpoint(file: expand($0.file), url: $0.url) },
            files: expand(definition.records.files),
            calendar: calendar,
            now: now,
            fingerprint: fingerprint
        )
    }
}
