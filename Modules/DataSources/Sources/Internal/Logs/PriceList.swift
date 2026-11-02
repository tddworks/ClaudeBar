import Diagnostics
import Foundation

/// What a token costs, from a price file shipped beside a definition — data,
/// so a price change edits the file, never Swift. Amounts are decimal texts,
/// kept exact.
///
/// A model is priced by the first rule that knows it: its exact id, the
/// longest id it starts with (or that starts with it), a family its name
/// contains, a free family (a local, open-weight model), an unpriced model
/// on a local route, and otherwise the fallback — a hedge for models newer
/// than the file, never zero by omission. A price may change with the
/// prompt's length (`above`); each record is priced by its own prompt.
struct PriceList: Sendable, Equatable, Decodable {
    struct Price: Sendable, Equatable, Decodable {
        let input: Decimal
        let output: Decimal
        let cacheWrite: Decimal
        /// A write kept an hour; unset is the five-minute price.
        let cacheWrite1h: Decimal?
        let cacheRead: Decimal
        /// The prices of a longer prompt, when the model has them.
        let above: Above?

        static let free = Price(input: 0, output: 0, cacheWrite: 0, cacheWrite1h: 0, cacheRead: 0)

        init(input: Decimal, output: Decimal, cacheWrite: Decimal, cacheWrite1h: Decimal? = nil, cacheRead: Decimal,
             above: Above? = nil) {
            self.input = input
            self.output = output
            self.cacheWrite = cacheWrite
            self.cacheWrite1h = cacheWrite1h
            self.cacheRead = cacheRead
            self.above = above
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = try PriceAmount.decode(container, .input)
            output = try PriceAmount.decode(container, .output)
            cacheWrite = try PriceAmount.decode(container, .cacheWrite)
            cacheWrite1h = container.contains(.cacheWrite1h) ? try PriceAmount.decode(container, .cacheWrite1h) : nil
            cacheRead = try PriceAmount.decode(container, .cacheRead)
            above = try container.decodeIfPresent(Above.self, forKey: .above)
        }

        /// The prices a request pays whose prompt — input, cache writes and
        /// cache reads together — is `tokens` long.
        func forPrompt(of tokens: Int) -> Price {
            guard let above, tokens > above.prompt else { return self }
            return above.price
        }

        enum CodingKeys: String, CodingKey { case input, output, cacheWrite, cacheWrite1h, cacheRead, above }
    }

    /// What a request pays whose prompt is over `prompt` tokens. A class, so
    /// a price can hold another.
    final class Above: Sendable, Equatable, Decodable {
        let prompt: Int
        let price: Price

        required init(from decoder: Decoder) throws {
            prompt = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .prompt)
            price = try Price(from: decoder)
        }

        static func == (lhs: Above, rhs: Above) -> Bool { lhs.prompt == rhs.prompt && lhs.price == rhs.price }

        private enum CodingKeys: String, CodingKey { case prompt }
    }

    struct Model: Sendable, Equatable, Decodable {
        let id: String
        let price: Price

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            price = try Price(from: decoder)
        }

        private enum CodingKeys: String, CodingKey { case id }
    }

    /// A name that contains `contains` is priced as the model `as`.
    struct Family: Sendable, Equatable, Decodable {
        let contains: String
        let `as`: String
    }

    /// Tokens per price — prices are per million when 1000000.
    let per: Decimal
    let models: [Model]
    let families: [Family]
    /// Names, matched as lowercased substrings, of model families nobody
    /// bills per token.
    let free: [String]
    let otherwise: Price

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        per = try container.decodeIfPresent(Decimal.self, forKey: .per) ?? 1
        models = try container.decodeIfPresent([Model].self, forKey: .models) ?? []
        families = try container.decodeIfPresent([Family].self, forKey: .families) ?? []
        free = try container.decodeIfPresent([String].self, forKey: .free) ?? []
        otherwise = try container.decode(Price.self, forKey: .otherwise)
    }

    private enum CodingKeys: String, CodingKey { case per, models, families, free, otherwise }

    /// The price file `file`, or `nil` — logged — when it is missing or malformed.
    static func load(_ file: String, from scripts: DataSources.ScriptSource) -> PriceList? {
        guard let text = scripts(file) else {
            AppLog.probes.error("Usage history: price file '\(file)' is missing")
            return nil
        }
        do {
            return try JSONDecoder().decode(PriceList.self, from: Data(text.utf8))
        } catch {
            AppLog.probes.error("Usage history: price file '\(file)' is malformed: \(error.localizedDescription)")
            return nil
        }
    }

    /// - Parameter servedLocally: the route is on this Mac. Only consulted
    ///   for names the list doesn't price: a local route says nothing about
    ///   which listed model was billed.
    func price(for model: String, servedLocally: Bool = false) -> Price {
        if let exact = models.first(where: { $0.id == model }) { return exact.price }
        if let prefix = models.filter({ model.hasPrefix($0.id) }).max(by: { $0.id.count < $1.id.count }) { return prefix.price }
        if let longer = models.filter({ $0.id.hasPrefix(model) }).min(by: { $0.id.count < $1.id.count }) { return longer.price }
        if let family = families.first(where: { model.contains($0.contains) }),
           let priced = models.first(where: { $0.id == family.as }) {
            return priced.price
        }
        let name = model.lowercased()
        if free.contains(where: { name.contains($0) }) || servedLocally { return .free }
        return otherwise
    }

    func cost(of record: LogRecord, servedLocally: Bool = false) -> Decimal {
        let price = price(of: record, servedLocally: servedLocally)
        return Decimal(record.input) / per * price.input
            + Decimal(record.output) / per * price.output
            + Decimal(record.cacheWrite - record.cacheWrite1h) / per * price.cacheWrite
            + Decimal(record.cacheWrite1h) / per * (price.cacheWrite1h ?? price.cacheWrite)
            + Decimal(record.cacheRead) / per * price.cacheRead
    }

    /// What cache reads saved: their tokens at the input price, less what they cost.
    func savings(of record: LogRecord, servedLocally: Bool = false) -> Decimal {
        let price = price(of: record, servedLocally: servedLocally)
        return Decimal(record.cacheRead) / per * (price.input - price.cacheRead)
    }

    /// The record's model's prices for the record's own prompt: a record is
    /// one request, billed on its own.
    private func price(of record: LogRecord, servedLocally: Bool) -> Price {
        price(for: record.model ?? "", servedLocally: servedLocally)
            .forPrompt(of: record.input + record.cacheWrite + record.cacheRead)
    }
}

/// `"0.30"` or `0.3`, read as an exact `Decimal` from its text.
private enum PriceAmount {
    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> Decimal {
        if let text = try? container.decode(String.self, forKey: key),
           let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
            return value
        }
        return try container.decode(Decimal.self, forKey: key)
    }
}
