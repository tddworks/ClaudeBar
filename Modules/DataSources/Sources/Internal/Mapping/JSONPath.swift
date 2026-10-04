import Foundation

/// The small path dialect definitions use — implemented here rather than
/// taken as a dependency (docs/architecture/TARGET_ARCHITECTURE.md §9):
///
/// - `$.a.b` — from the root of the document
/// - `a.b` — from the current object (inside `at` or `each`)
/// - `$header.name` — a response header
/// - `$key` — the current key while repeating over a map
/// - a numeric component indexes an array; a trailing `[*]` is ignored
struct JSONScope {
    let root: Any?
    let current: Any?
    let headers: [String: String]
    let key: String?
    /// Non-secret credential values — `$credential.email`.
    let credential: [String: String]

    /// A scope at the root of a document.
    init(root: Any?, headers: [String: String] = [:], credential: [String: String] = [:]) {
        self.init(root: root, current: root, headers: headers, key: nil, credential: credential)
    }

    private init(root: Any?, current: Any?, headers: [String: String], key: String?, credential: [String: String]) {
        self.root = root
        self.current = current
        self.headers = headers
        self.key = key
        self.credential = credential
    }

    /// The same document, reading relative paths from `current` — which may
    /// be missing, and then every relative path reads nothing.
    func moved(to current: Any?, key: String? = nil) -> JSONScope {
        JSONScope(root: root, current: current, headers: headers, key: key ?? self.key, credential: credential)
    }

    func value(_ path: String) -> Any? {
        if path == "$key" { return key }
        if path.hasPrefix("$credential.") {
            return credential[String(path.dropFirst("$credential.".count))]
        }
        if path.hasPrefix("$header.") {
            return headers[String(path.dropFirst("$header.".count)).lowercased()]
        }
        if path == "$" { return root }
        if path.hasPrefix("$.") {
            return JSONPath.walk(root, JSONPath.components(String(path.dropFirst(2))))
        }
        return JSONPath.walk(current, JSONPath.components(path))
    }

    func number(_ path: String) -> Double? {
        JSONPath.number(value(path))
    }

    func string(_ path: String) -> String? {
        JSONPath.string(value(path))
    }
}

enum JSONPath {
    static func components(_ path: String) -> [String] {
        var trimmed = path
        if trimmed.hasPrefix("$.") { trimmed = String(trimmed.dropFirst(2)) }
        if trimmed.hasSuffix("[*]") { trimmed = String(trimmed.dropLast(3)) }
        return trimmed.split(separator: ".").map(String.init).filter { !$0.isEmpty }
    }

    static func walk(_ value: Any?, _ components: [String]) -> Any? {
        var current = value
        for component in components {
            if let object = current as? [String: Any] {
                current = object[component]
            } else if let array = current as? [Any], let index = Int(component), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
            if current is NSNull { return nil }
        }
        return current
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            let double = number.doubleValue
            return double.isFinite ? double : nil
        case let string as String:
            guard let double = Double(string.trimmingCharacters(in: .whitespaces)), double.isFinite else { return nil }
            return double
        default:
            return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    /// Writes `value` at a `$.a.b` path, creating objects on the way and
    /// keeping every other field.
    static func set(_ value: Any, at path: String, in object: [String: Any]) -> [String: Any] {
        set(value, components(path)[...], in: object)
    }

    private static func set(_ value: Any, _ components: ArraySlice<String>, in object: [String: Any]) -> [String: Any] {
        guard let first = components.first else { return object }
        var copy = object
        if components.count == 1 {
            copy[first] = value
        } else {
            let child = object[first] as? [String: Any] ?? [:]
            copy[first] = set(value, components.dropFirst(), in: child)
        }
        return copy
    }
}
