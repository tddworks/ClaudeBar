import Foundation

/// Locates the separator colon inside an hours-and-minutes countdown so a
/// renderer can animate it.
///
/// The menu bar label carries no clock of its own: the countdown text advances
/// only when the label is redrawn, which makes a correct-but-static "4:40"
/// indistinguishable from a stale one. Pulsing the colon is the signal that the
/// value is live, the same way a digital clock blinks its separator.
///
/// Only a `digit:digit-digit` run counts. A probe can set a `menuBarTitle`
/// containing a colon (e.g. an account discriminator), and that punctuation
/// must not pulse — it isn't counting down.
///
/// Lives in Domain because "which characters are the countdown separator" is a
/// rule worth testing; how the pulse is drawn stays in the App layer.
public enum CountdownColon {
    /// A colon preceded by a digit and followed by exactly two digits — the
    /// shape `UsageQuota.compactResetTime` emits for the 1h–24h range ("4:40").
    /// The capture group isolates the colon itself, so each returned range
    /// addresses one character.
    private static let pattern = #"\d(:)\d\d"#

    private static let regex = try? NSRegularExpression(pattern: pattern)

    /// Ranges of the countdown colons in `text`, in order.
    ///
    /// Empty when there is nothing to animate — a `"45m"` or `"2d"` label, a
    /// label with no duration shown, or a colon that belongs to something other
    /// than a countdown. A dual-window label yields one range per window that
    /// is currently in hours range.
    public static func ranges(in text: String) -> [Range<String.Index>] {
        guard let regex, !text.isEmpty else { return [] }

        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: full).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return Range(match.range(at: 1), in: text)
        }
    }
}
