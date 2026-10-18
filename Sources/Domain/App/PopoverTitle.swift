import Foundation

/// The name at the top of the popover: *ClaudeBar* until the person names it
/// their own way (Settings → Appearance → Popover Title).
///
/// What they typed is kept as typed; the rule applies when it is shown, so a
/// later rule never rewrites their settings file.
public struct PopoverTitle: Sendable, Equatable {
    public static let productName = "ClaudeBar"
    public static let maxLength = 24

    /// The text as the person typed it, `""` when never set.
    public let typed: String

    public init(_ typed: String) {
        self.typed = typed
    }

    /// One line, at most `maxLength` characters, no whitespace around it;
    /// *ClaudeBar* when nothing is left.
    public var shown: String {
        let oneLine = typed
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let name = String(oneLine.trimmingCharacters(in: .whitespaces).prefix(Self.maxLength))
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? Self.productName : name
    }

    /// True while the person hasn't named it: nothing typed but whitespace.
    public var isDefault: Bool { typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
