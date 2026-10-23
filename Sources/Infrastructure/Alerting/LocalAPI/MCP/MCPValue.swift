import Foundation

/// JSON as values — the MCP kernel speaks in these, never in `[String: Any]`,
/// so a message can cross an actor boundary. Parsed with
/// `JSONSerialization`, written back with it too; `parse`/`encoded` are the
/// only places bytes and values meet.
public enum MCPValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([MCPValue])
    case object([String: MCPValue])

    /// The value's object pairs, or `nil` for anything else.
    public var objectValue: [String: MCPValue]? {
        if case let .object(pairs) = self { return pairs }
        return nil
    }

    /// The value's string, or `nil` for anything else.
    public var stringValue: String? {
        if case let .string(text) = self { return text }
        return nil
    }

    /// The value's whole number, or `nil` for anything else.
    public var intValue: Int? {
        if case let .number(double) = self { return Int(exactly: double) }
        return nil
    }

    /// A pair in an object; anything else reads as `nil`.
    public subscript(key: String) -> MCPValue? {
        objectValue?[key]
    }

    /// An empty object — the schema of a tool that takes no arguments.
    public static let emptyObject: MCPValue = .object([:])

    /// Parses bytes into a value, JSON fragments included. `nil` for anything
    /// that does not parse — a batch (`[...]`) parses as `.array`, and the
    /// MCP kernel is the one that refuses it.
    public static func parse(_ data: Data) -> MCPValue? {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return Self(any)
    }

    /// Writes the value back to bytes. The object's keys are sorted, so a
    /// reply is stable byte for byte.
    public func encoded(pretty: Bool = false) -> Data {
        let any: Any = switch self {
        case .null: NSNull()
        case let .bool(bool): bool
        case let .number(number): number
        case let .string(string): string
        case let .array(values): values.map { Self.anyValue($0) }
        case let .object(pairs): Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, Self.anyValue($0.value)) })
        }
        var serialization: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]
        serialization.insert(.withoutEscapingSlashes)
        return (try? JSONSerialization.data(withJSONObject: any, options: serialization)) ?? Data("null".utf8)
    }

    private static func anyValue(_ value: MCPValue) -> Any {
        switch value {
        case .null: NSNull()
        case let .bool(bool): bool
        case let .number(number): number
        case let .string(string): string
        case let .array(values): values.map { anyValue($0) }
        case let .object(pairs): Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, anyValue($0.value)) })
        }
    }

    /// The value of one parsed JSON node.
    private init?(_ any: Any) {
        switch any {
        case is NSNull: self = .null
        case let number as NSNumber:
            // A JSON true/false arrives as an NSNumber of a boolean type.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String: self = .string(string)
        case let values as [Any]: self = .array(values.compactMap { Self.init($0) })
        case let pairs as [String: Any]:
            var converted: [String: MCPValue] = [:]
            for (key, value) in pairs {
                guard let convertedValue = Self.init(value) else { return nil }
                converted[key] = convertedValue
            }
            self = .object(converted)
        default: return nil
        }
    }
}
