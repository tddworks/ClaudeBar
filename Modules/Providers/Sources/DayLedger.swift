import Foundation
import Mockable
import Quotas

/// PAST DAYS, KEPT — a closed day is summed once and kept on this Mac, so a
/// thirty-day range reads only its open days from the logs. A ledger is a
/// cache, not a record: deleting it reads the logs again, and a change to how
/// the logs read (the log's fingerprint) starts it over.
public struct DayLedger: Sendable {
    /// A day closes this long after its midnight: lines a tool writes late
    /// still land, and the day is final after that.
    public static let closesAfter: TimeInterval = 3600

    let store: any LedgerStore
    /// Whose days these are — the login's lineup id.
    let key: String

    public init(store: any LedgerStore, key: String) {
        self.store = store
        self.key = key
    }

    /// Whether `day` (its start) is closed at `now`.
    static func isClosed(_ day: Date, at now: Date, calendar: Calendar) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return now >= end.addingTimeInterval(closesAfter)
    }

    /// The kept days, by date, when they were summed the way `fingerprint`
    /// reads — the fingerprint carries how days are summed, so a change to
    /// the summing starts it over.
    func days(readAs fingerprint: String) -> [String: DailyUsageStat] {
        guard let page = store.load(key), page.fingerprint == fingerprint else { return [:] }
        return page.days
    }

    /// Keeps `days`, beside those already kept the same way.
    func keep(_ days: [String: DailyUsageStat], readAs fingerprint: String) {
        guard !days.isEmpty else { return }
        store.save(LedgerPage(fingerprint: fingerprint, days: self.days(readAs: fingerprint).merging(days) { _, new in new }),
                   for: key)
    }

    static func name(of day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// One login's kept days, and how they were read.
public struct LedgerPage: Sendable, Equatable, Codable {
    public let fingerprint: String
    /// By local date, `yyyy-MM-dd`.
    public let days: [String: DailyUsageStat]

    public init(fingerprint: String, days: [String: DailyUsageStat]) {
        self.fingerprint = fingerprint
        self.days = days
    }
}

/// Where kept days live.
@Mockable
public protocol LedgerStore: Sendable {
    func load(_ key: String) -> LedgerPage?
    func save(_ page: LedgerPage, for key: String)
}

/// `~/.claudebar/usage-history/<login>.json` — a few hundred bytes a day.
struct FileLedgerStore: LedgerStore {
    let directory: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claudebar/usage-history")) {
        self.directory = directory
    }

    func load(_ key: String) -> LedgerPage? {
        guard let data = FileManager.default.contents(atPath: file(key).path) else { return nil }
        return try? JSONDecoder().decode(LedgerPage.self, from: data)
    }

    func save(_ page: LedgerPage, for key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }
}
