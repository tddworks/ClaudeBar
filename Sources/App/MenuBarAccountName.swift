import Foundation

/// The few characters beside a provider's icon that say which login a menu-bar
/// number belongs to — the page's, not the model's. An email shows the part
/// before the `@` (8 characters at most); a name the person gave keeps up to
/// 12. Names that shorten alike are numbered; they never grow back into a full
/// email, which the 16 px bar has no room for. The tooltip keeps the full name.
enum MenuBarAccountName {
    /// Short names by lineup id, from each account's display name.
    static func names(_ displayNames: [String: String]) -> [String: String] {
        let ids = displayNames.keys.sorted()
        var shortened: [String: (text: String, limit: Int)] = [:]
        for id in ids {
            shortened[id] = short(displayNames[id] ?? "")
        }
        var names: [String: String] = [:]
        for id in ids {
            guard let (text, limit) = shortened[id] else { continue }
            let alike = ids.filter { shortened[$0]?.text == text }
            guard alike.count > 1, let position = alike.firstIndex(of: id) else {
                names[id] = text
                continue
            }
            let suffix = "·\(position + 1)"
            let stem = text.hasSuffix("…") ? String(text.dropLast()) : text
            names[id] = String(stem.prefix(max(1, limit - suffix.count))) + suffix
        }
        return names
    }

    private static func short(_ displayName: String) -> (text: String, limit: Int) {
        if let at = displayName.firstIndex(of: "@") {
            return (cut(String(displayName[..<at]), to: 8), 8)
        }
        return (cut(displayName, to: 12), 12)
    }

    private static func cut(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
