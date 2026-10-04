import DataSources
import Foundation

/// *Map fields*: what came back, as values to click — every number, string
/// and flag in a JSON response with the path that reaches it (`$.data.limit`),
/// so a person maps *Used · Remaining · Limit · Resets* by pointing.
public struct ResponseFields: RandomAccessCollection, Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public let path: String
        public let value: String
        public let isNumber: Bool
    }

    private let fields: [Field]

    /// The response's values, sorted by path; empty when it isn't JSON.
    public init(_ response: Response) {
        guard let document = try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed]) else {
            fields = []
            return
        }
        var found: [Field] = []
        Self.walk(document, path: "$", into: &found)
        fields = found.sorted { $0.path < $1.path }
    }

    /// A text response's non-empty lines — what a CLI printed.
    public static func lines(of response: Response) -> [String] {
        response.text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var startIndex: Int { fields.startIndex }
    public var endIndex: Int { fields.endIndex }
    public subscript(position: Int) -> Field { fields[position] }

    /// Enough to map a response, not to drown in one.
    private static let limit = 500

    private static func walk(_ value: Any, path: String, into fields: inout [Field]) {
        guard fields.count < limit else { return }
        switch value {
        case let object as [String: Any]:
            for key in object.keys.sorted() {
                walk(object[key]!, path: "\(path).\(key)", into: &fields)
            }
        case let array as [Any]:
            for (index, element) in array.enumerated() {
                walk(element, path: "\(path).\(index)", into: &fields)
            }
        case let number as NSNumber:
            let isBool = CFGetTypeID(number) == CFBooleanGetTypeID()
            fields.append(Field(path: path, value: isBool ? (number.boolValue ? "true" : "false") : number.stringValue, isNumber: !isBool))
        case let text as String:
            fields.append(Field(path: path, value: text, isNumber: false))
        default:
            break
        }
    }
}
