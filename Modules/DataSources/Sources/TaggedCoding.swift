import Foundation

/// The JSON shape of a closed sum: one object with exactly one key, the case's
/// tag — `{ "http": { … } }`, `{ "jsonFile": { … } }`. The tag names the case;
/// the value is its payload.
struct TagKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where Key == TagKey {
    /// The one tag present among `known`, or a decoding error naming them.
    func singleTag(of known: [String], in type: String) throws -> String {
        let present = allKeys.map(\.stringValue).filter(known.contains)
        guard present.count == 1, let tag = present.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "\(type) needs exactly one of \(known.joined(separator: ", ")); found \(allKeys.map(\.stringValue))"
            ))
        }
        return tag
    }
}
