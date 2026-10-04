import Foundation

/// `freeWhen.localEndpoint` — whether a tool is routed at a server on this
/// Mac (ollama, LM Studio, llama.cpp), where nobody bills per token.
///
/// Reads `file` on every call, so a route switched to a local server counts
/// from the next read without a restart. The first `url` entry that answers
/// decides — a tool's own route outranks a menu of routes it may switch to —
/// and a missing, unreadable or remote URL means "not local".
struct LocalEndpoint: Sendable {
    let file: String
    let url: [[String]]

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]

    func isLocal() -> Bool {
        guard let data = FileManager.default.contents(atPath: file),
              let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        for entry in url {
            let urls = entry.flatMap { Self.strings(at: $0, in: root) }
            if !urls.isEmpty { return urls.contains(where: Self.isLoopback) }
        }
        return false
    }

    /// Whether a base URL points at this machine. A host that can't be
    /// parsed is remote: charging nothing because a URL failed to parse
    /// would silently under-report real spend.
    static func isLoopback(_ baseURL: String) -> Bool {
        guard let host = URLComponents(string: baseURL)?.host?.lowercased() else { return false }
        // URLComponents keeps the brackets of an IPv6 literal ("[::1]").
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return loopbackHosts.contains(bare) || bare.hasSuffix(".localhost")
    }

    /// The texts at a path, where `name[*]` walks every element of a list.
    static func strings(at path: String, in root: Any) -> [String] {
        var trimmed = path
        if trimmed.hasPrefix("$.") { trimmed = String(trimmed.dropFirst(2)) }
        let components = trimmed.split(separator: ".").map(String.init)
        return values(components[...], in: root).compactMap { $0 as? String }
    }

    private static func values(_ components: ArraySlice<String>, in value: Any) -> [Any] {
        guard let first = components.first else { return [value] }
        let rest = components.dropFirst()
        if first.hasSuffix("[*]") {
            let name = String(first.dropLast(3))
            guard let list = (value as? [String: Any])?[name] as? [Any] else { return [] }
            return list.flatMap { values(rest, in: $0) }
        }
        guard let next = JSONPath.walk(value, [first]) else { return [] }
        return values(rest, in: next)
    }
}
