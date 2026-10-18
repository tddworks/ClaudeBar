import Foundation

/// opencode's own database as a test writes it: the places it keeps
/// messages in, each with its own columns and JSON, as opencode's migrations
/// make them — `message` (opencode 1) and `session_message` (opencode 2). An
/// install upgraded from 1 keeps both (#566).
enum OpenCodeStore {
    /// A table opencode keeps messages in.
    enum Place: String, Sendable, CaseIterable {
        case message
        case sessionMessage = "session_message"
    }

    /// A message as opencode writes it in `place`. A `nil` time or cost
    /// leaves the field out, as a message without it is.
    struct Message: Sendable {
        var id: String
        var at: Int64?
        var provider: String
        var role = "assistant"
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var cost: Double? = 0
        var place: Place = .sessionMessage
    }

    /// The SQL that makes a store holding `places` and `messages`.
    static func sql(places: Set<Place>, _ messages: [Message]) -> String {
        var sql = ""
        if places.contains(.message) {
            sql += "CREATE TABLE message(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);"
        }
        if places.contains(.sessionMessage) {
            sql += "CREATE TABLE session_v2(id TEXT PRIMARY KEY);"
            sql += "CREATE TABLE session_message(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);"
        }
        for (seq, message) in messages.enumerated() {
            let created = message.at ?? 0
            switch message.place {
            case .message:
                sql += "INSERT INTO message VALUES ('\(message.id)', 'ses_1', \(created), \(created), '\(data(message))');"
            case .sessionMessage:
                sql += "INSERT INTO session_message VALUES ('\(message.id)', 'ses_1', '\(message.role)', \(seq), \(created), \(created), '\(data(message))');"
            }
        }
        return sql
    }

    /// Makes the store at `url`.
    static func make(at url: URL, places: Set<Place>, _ messages: [Message]) throws {
        try SQLiteFiles.make(at: url, sql(places: places, messages))
    }

    /// `data` as the place writes it: 1 with the provider and role at the
    /// top, 2 with the provider inside `model` and the role as the row's type.
    private static func data(_ message: Message) -> String {
        var fields = [#""id":"\#(message.id)""#]
        switch message.place {
        case .message: fields.append(#""providerID":"\#(message.provider)","role":"\#(message.role)""#)
        case .sessionMessage: fields.append(#""model":{"providerID":"\#(message.provider)","id":"claude-x"}"#)
        }
        if let at = message.at { fields.append(#""time":{"created":\#(at)}"#) }
        fields.append(#""tokens":{"input":\#(message.input),"output":\#(message.output),"cache":{"read":\#(message.cacheRead),"write":\#(message.cacheWrite)}}"#)
        if let cost = message.cost { fields.append(#""cost":\#(cost)"#) }
        return "{" + fields.joined(separator: ",") + "}"
    }
}
