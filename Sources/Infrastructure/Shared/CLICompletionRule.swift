import Foundation

/// Tells a PTY run when a TUI screen is actually finished.
///
/// Going idle is not proof that a screen is done, because a `/usage` capture is a
/// wait for a *target* screen that can be preceded by a long stretch of quiet.
/// The CLI only submits `/usage` once it has finished booting — its SessionStart
/// hooks first, on a busy machine for seconds — and then fills the quota bars in
/// from a second request a few seconds after the Usage tab opens. Every one of
/// those screens is "not finished", and a capture that stops on one holds nothing
/// to parse (#271, #317).
///
/// Readiness is therefore decided positively: a screen is finished when it
/// carries a marker that only a settled screen has, whether that is the data we
/// asked for or the error that replaced it. A screen that carries no such marker
/// is still filling in, whether or not it happens to be painting a placeholder.
/// The PTY buffer is cumulative — a redraw appends, it does not erase — so a
/// placeholder appearing or disappearing proves nothing either way.
public struct CLICompletionRule: Sendable, Equatable {
    /// One piece of evidence that the screen has settled.
    public struct Marker: Sendable, Equatable {
        /// The text to look for, matched the way `screenText` normalises.
        public let text: String

        /// True when the marker has to be the whole row, not just a run of
        /// words inside one.
        ///
        /// Only for a *section label* — something the CLI paints as a row of
        /// its own. `Current session` is one: the same words in the middle of a
        /// SessionStart hook's sentence are prose, and treating them as the
        /// label ends the wait on a screen that never opened the Usage tab
        /// (#317). A marker that is not a label must not carry this: the CLI
        /// shares rows, and a real Usage screen puts `27% used` and
        /// `Resets 4:59pm (America/New_York)` on the same line, and redraw
        /// artifacts repeat the reset text on that line. Requiring the whole
        /// row for those would stop real screens being recognised.
        public let endsRow: Bool

        public init(_ text: String, endsRow: Bool = false) {
            self.text = text
            self.endsRow = endsRow
        }

        /// A marker the CLI paints as a whole row: a section label.
        public static func row(_ text: String) -> Marker { Marker(text, endsRow: true) }
    }

    /// Markers whose presence means the screen has settled, data or error.
    public let readyMarkers: [Marker]

    public init(readyMarkers: [Marker]) {
        self.readyMarkers = readyMarkers
    }

    /// True while the captured screen has not shown a ready marker yet.
    public func isPending(_ text: String) -> Bool {
        !isReady(text)
    }

    /// True once the screen carries a ready marker.
    public func isReady(_ text: String) -> Bool {
        let screen = Self.screenText(text)
        return readyMarkers.contains { Self.contains(marker: $0, in: screen) }
    }

    /// The ready markers this text carries, in the order they are declared.
    ///
    /// Read by `scripts/replay-claude-usage-captures.swift` to report which
    /// piece of evidence ended a real capture, so the corpus replay says why a
    /// screen was accepted rather than only that it was.
    public func matchedMarkers(in text: String) -> [String] {
        let screen = Self.screenText(text)
        return readyMarkers.filter { Self.contains(marker: $0, in: screen) }.map(\.text)
    }

    /// The text a marker is actually findable in, as a character array.
    ///
    /// Two things happen in one pass. Escape sequences become a separator,
    /// because the gap a cursor jump leaves is padding the terminal inserts
    /// rather than bytes the CLI sent — `Current session` reaches the PTY as
    /// `Curre␛[10Gt␛[12Gsession` and `38% used` as `38%␛[59Gused`. Every run
    /// of non-alphanumerics then collapses to that same separator, so a phrase
    /// matches whether the CLI wrote it in one run or split it across half a
    /// dozen. A line break stays its own character: two screen rows never spell
    /// one label, and a match that would need to cross one is not a match.
    ///
    /// This normalisation is not what makes every ready marker findable — most
    /// already are. Across the 430 `/usage` captures in the log attached to
    /// #317, 137 contain a ready marker as a raw literal substring. It is the
    /// multi-word phrases that need it: "Loading usage data…", the placeholder
    /// #271 added, is a raw substring of 0 of those 430 and a normalised match
    /// in 12, so a raw search could never have fired on a real screen.
    private static func screenText(_ text: String) -> [Character] {
        let withoutEscapes = escapeSequence?
            .stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\u{1}"
            ) ?? text

        var screen: [Character] = []
        screen.reserveCapacity(withoutEscapes.count)
        var previous: Character?
        for character in withoutEscapes.lowercased() {
            // A word character is kept as itself; anything else is reduced to a
            // separator, and a line break to one that is never interchangeable
            // with the padding inside a line.
            let current: Character
            if character.isLetter || character.isNumber {
                current = character
            } else if character == "\n" || character == "\r" {
                current = lineBreak
            } else {
                current = separator
            }
            if current != previous { screen.append(current) }
            previous = current
        }
        return screen
    }

    /// True when `screen` contains `marker`.
    ///
    /// Collapsing the padding costs the text its word boundaries, so both are
    /// restored here. A marker has to *begin* one — otherwise a phrase could
    /// match the tail of one word plus the head of the next — and a marker
    /// declared with `endsRow` has to end at the end of its row too. That
    /// second test is per-marker because only a section label earns it: the CLI
    /// paints `Current session` as a row of its own, while a SessionStart hook
    /// printing "The current session will seed it…" carries the same words
    /// mid-sentence, and treating that as the label ends the wait on a screen
    /// that never reached the Usage tab (#317). The other markers are values the
    /// CLI shares a row with other content — `27% used` sits beside
    /// `Resets 4:59pm (America/New_York)`, and a redraw artifact repeats the
    /// reset text on that same line — so requiring a whole row from them would
    /// stop real Usage screens being recognised.
    ///
    /// A marker that starts with punctuation (`% used`) supplies its own left
    /// boundary, and a marker that is not a label (`Error:`) only has to end on
    /// a non-word character — the colon is boundary enough, and a settled error
    /// continues into "Error: Usage endpoint is rate limited…".
    private static func contains(marker: Marker, in screen: [Character]) -> Bool {
        let needle = screenText(marker.text)
        guard !needle.isEmpty, screen.count >= needle.count else { return false }
        // Decided from the marker as written, not from its normalised form: a
        // marker that opens with punctuation (`% used`) supplies its own left
        // boundary, and normalising would turn that `%` into a separator and
        // then demand a boundary that a `38% used` row never has.
        let startsAWord = marker.text.first.map { $0.isLetter || $0.isNumber } ?? false

        var start = screen.startIndex
        while start <= screen.index(screen.endIndex, offsetBy: -needle.count) {
            if startsAWord, start > screen.startIndex {
                let previous = screen[screen.index(before: start)]
                // A word character here means the marker is a fragment of the
                // word before it. Collapsing the padding would otherwise let
                // `…cache write` + `Current session` read as one token.
                if previous.isLetter || previous.isNumber {
                    start = screen.index(after: start)
                    continue
                }
            }
            if let end = match(needle, in: screen, from: start) {
                // A row marker has to end at the end of its row. The CLI writes
                // `Current session` and then a cursor move, not a line break, so
                // the padding between the phrase and that break is stepped over
                // before looking.
                var next = end
                if marker.endsRow {
                    while next < screen.endIndex, screen[next] == separator {
                        next += 1
                    }
                }
                let atRowEnd = next == screen.endIndex || screen[next] == lineBreak
                if marker.endsRow {
                    if atRowEnd { return true }
                } else {
                    // Everything else only has to end on a non-word character,
                    // so trailing content on the same row is allowed.
                    if atRowEnd || !(screen[next].isLetter || screen[next].isNumber) {
                        return true
                    }
                }
            }
            start = screen.index(after: start)
        }
        return false
    }

    /// Walks `needle` through `screen` from `start` and returns the index of the
    /// last character it matched, or nil when it does not fit.
    ///
    /// Padding is stepped over *between* characters of the marker: the CLI
    /// splits a phrase across cursor moves, so `Current session` reaches the
    /// screen as `current␁session`. A separator the marker spells is matched as
    /// one screen separator — except a *trailing* one, which is left for the
    /// caller's boundary check: `Error:` ends in punctuation, and consuming the
    /// padding after it there would hide the very word that has to follow.
    private static func match(
        _ needle: [Character],
        in screen: [Character],
        from start: Int
    ) -> Int? {
        var index = start
        for (offset, expected) in needle.enumerated() {
            let isLast = offset == needle.count - 1
            if expected == separator {
                guard index < screen.endIndex, screen[index] == separator else { return nil }
                if isLast { break }
                while index < screen.endIndex, screen[index] == separator {
                    index += 1
                }
                continue
            }
            // Padding is skipped between characters, never before the first:
            // that is what a leading punctuation marker such as `% used` is
            // already standing in for.
            if offset > 0 {
                while index < screen.endIndex, screen[index] == separator {
                    index += 1
                }
            }
            guard index < screen.endIndex, screen[index] == expected else { return nil }
            index += 1
        }
        return index
    }

    /// Stands for padding the terminal painted between two words.
    private static let separator: Character = "\u{1}"

    /// A real line break, which a single label never spans.
    private static let lineBreak: Character = "\u{2}"

    /// OSC (…BEL / …ST), CSI (`␛[` + parameters + a final byte), charset
    /// designators, and the two-character escapes Claude Code uses for save and
    /// restore (`␛7`, `␛8`).
    private static let escapeSequence: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|\x1B\[[0-9;?]*[A-Za-z]|\x1B[()][AB012]|\x1B[78]"#
        )
    }()

    /// The rule for `claude /usage`.
    ///
    /// Ready markers cover both outcomes so a stalled or rate-limited endpoint
    /// ends the wait as soon as the CLI says so, instead of holding the run open
    /// until the probe timeout.
    ///
    /// Only `Current session` is a row marker. It is the Usage screen's section
    /// label, and the words also turn up mid-sentence in a SessionStart hook's
    /// output. The rest are values the CLI shares a row with other content —
    /// `27% used` beside `Resets 4:59pm (America/New_York)`, an error message
    /// that continues after its colon — so a whole-row requirement would reject
    /// real screens (#317).
    public static let claudeUsage = CLICompletionRule(
        readyMarkers: [
            .row("Current session"),
            Marker("% used"),
            Marker("% left"),
            Marker("rate limited"),
            Marker("Error:"),
            Marker("/usage is only available"),
        ]
    )
}
