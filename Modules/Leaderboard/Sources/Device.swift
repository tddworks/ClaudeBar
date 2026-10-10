import Foundation

/// *DEVICE* (design §2a): one of a member's machines, which is one key. `/me`
/// lists them, removed ones included; a removed device's days stay and count.
public struct Device: Sendable, Equatable, Codable {
    /// The device's public key, base64url, as `X-Key` names it.
    public let publicKey: String
    public let label: String
    public let addedAt: Date
    public let removedAt: Date?
    /// The device that removed it, `nil` while it's in use.
    public let removedBy: DeviceRef?

    public init(publicKey: String, label: String, addedAt: Date, removedAt: Date? = nil, removedBy: DeviceRef? = nil) {
        self.publicKey = publicKey
        self.label = label
        self.addedAt = addedAt
        self.removedAt = removedAt
        self.removedBy = removedBy
    }

    public var isRemoved: Bool { removedAt != nil }

    private enum CodingKeys: String, CodingKey { case publicKey, label, addedAt, removedAt, removedBy }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        label = try container.decode(String.self, forKey: .label)
        addedAt = try ServerTime.decode(from: container, forKey: .addedAt)
        removedAt = try ServerTime.decodeIfPresent(from: container, forKey: .removedAt)
        removedBy = try container.decodeIfPresent(DeviceRef.self, forKey: .removedBy)
    }

    /// Written as `ServerTime` reads it, so an exported `/me` answer reads back
    /// as the same instants; `JSONEncoder`'s own form counts from 2001.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(label, forKey: .label)
        try container.encode(ServerTime.string(addedAt), forKey: .addedAt)
        try container.encodeIfPresent(removedAt.map(ServerTime.string), forKey: .removedAt)
        try container.encodeIfPresent(removedBy, forKey: .removedBy)
    }
}

/// A device named in passing: the one that removed another.
public struct DeviceRef: Sendable, Equatable, Codable {
    public let publicKey: String
    public let label: String

    public init(publicKey: String, label: String) {
        self.publicKey = publicKey
        self.label = label
    }
}

/// What a device is called on the member's list: the label the person typed
/// when it joined or was added, filled in with the machine's model and never
/// its computer name, which is often a person's (design §6). The server takes
/// 1–40 characters without control characters.
public struct DeviceLabel: Sendable, Hashable, CustomStringConvertible {
    public let value: String

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.count),
              !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        value = trimmed
    }

    public var description: String { value }
}

/// The code a new device shows until one the member has approves it: 8 of
/// RFC 8628's consonants, shown as `WDJB-MJHT` and read however it's typed.
public struct DeviceCode: Sendable, Hashable, CustomStringConvertible {
    /// The 8 letters, upper case, as the server's paths take them.
    public let value: String

    private static let alphabet = Set("BCDFGHJKLMNPQRSTVWXZ")

    public init?(_ typed: String) {
        let letters = typed.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard letters.count == 8, letters.allSatisfy(Self.alphabet.contains) else { return nil }
        value = letters
    }

    public var description: String { "\(value.prefix(4))-\(value.suffix(4))" }
}

/// What approving a code would add: the label the new device asked with, and
/// when, shown above *Approve* so a code read out to a stranger isn't
/// approved blind (RFC 8628 §5.4).
public struct PendingDevice: Sendable, Equatable, Decodable {
    public let label: String
    public let requestedAt: Date

    public init(label: String, requestedAt: Date) {
        self.label = label
        self.requestedAt = requestedAt
    }

    private enum CodingKeys: String, CodingKey { case label, requestedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        requestedAt = try ServerTime.decode(from: container, forKey: .requestedAt)
    }
}

/// The server's answer to a new device asking to be added: its code, how long
/// the code lasts and how often to ask whether it was approved.
public struct DeviceAuthorization: Sendable, Equatable {
    public let code: DeviceCode
    public let expiresIn: TimeInterval
    public let interval: TimeInterval

    public init(code: DeviceCode, expiresIn: TimeInterval, interval: TimeInterval) {
        self.code = code
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// Where a new device's code stands, by `GET /me` signed with its own key.
public enum DeviceApproval: Sendable, Equatable {
    /// Not approved yet: `202`, with no member data.
    case waiting
    /// Approved: the member it joined, as `/me` answers.
    case approved(MemberSummary)
}

/// A time as the server writes it. §5 doesn't fix the form, so the ones a
/// Worker on D1 is likely to send are read: ISO 8601 with or without
/// fractional seconds, SQLite's `YYYY-MM-DD HH:MM:SS` in UTC, and Unix time in
/// seconds or milliseconds. Anything else fails the answer rather than guess.
/// Written back as ISO 8601 in UTC with milliseconds.
enum ServerTime {
    static func decode<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Date {
        if let seconds = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
        }
        let text = try container.decode(String.self, forKey: key)
        guard let date = date(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not a time: \(text)")
        }
        return date
    }

    static func decodeIfPresent<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Date? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        return try decode(from: container, forKey: key)
    }

    static func string(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions.insert(.withFractionalSeconds)
        return iso.string(from: date)
    }

    private static func date(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return date }
        let sqlite = DateFormatter()
        sqlite.locale = Locale(identifier: "en_US_POSIX")
        sqlite.timeZone = TimeZone(identifier: "UTC")
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqlite.date(from: text)
    }
}
