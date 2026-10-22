import Foundation

/// Where a webhook is sent: an https URL, or http only to a host on this Mac
/// or the person's network. It is a secret — a Slack URL carries a token — so
/// it is kept in `DestinationSecrets` and never saved, logged or shown again.
public struct WebhookAddress: Sendable, Equatable {
    /// Why a URL was refused, for the card to word.
    public enum Refusal: Error, Equatable, Sendable {
        /// Not a full web URL: no `https://`, no host.
        case notAURL
        /// http to a host on the internet, where the token would travel in the clear.
        case notHTTPS
    }

    public let url: URL

    /// Parses what the person pasted.
    public init(_ text: String) throws(Refusal) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { throw .notAURL }
        switch scheme {
        case "https": break
        case "http": guard Self.isLocal(host) else { throw .notHTTPS }
        default: throw .notAURL
        }
        self.url = url
    }

    /// The host, as the list names a webhook until the person types a name.
    public var host: String { url.host ?? "" }

    /// `localhost`, `*.local`, the loopback and the private IPv4 ranges.
    private static func isLocal(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, host.split(separator: ".").count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168): return true
        case (172, let second): return (16...31).contains(second)
        default: return false
        }
    }
}
