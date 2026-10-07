import Kit
import Foundation

/// Status information for a status banner section.
public struct StatusInfo: Sendable, Equatable, Codable {
    public let text: String
    public let level: StatusLevel

    public init(text: String, level: StatusLevel) {
        self.text = text
        self.level = level
    }
}

/// Severity level for status banners.
public enum StatusLevel: String, Sendable, Equatable, Codable {
    case healthy
    case warning
    case critical
    case inactive
}
