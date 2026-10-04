import Foundation
import SwiftTerm

/// Minimal delegate for headless terminal rendering.
/// Only implements required methods - we don't need to send data back.
private final class RenderDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
        // No-op: we're only reading, not sending
    }
}

/// Renders raw terminal output with ANSI escape sequences into clean text.
///
/// Uses SwiftTerm's terminal emulator to properly handle cursor movements,
/// screen clearing, and other terminal control sequences that would otherwise
/// corrupt the output when captured from a PTY.
///
/// Example:
/// ```swift
/// let renderer = TerminalRenderer()
/// let raw = "Hello\u{1B}[5CWorld"  // "Hello" + move 5 right + "World"
/// let clean = renderer.render(raw)  // "Hello     World"
/// ```
public final class TerminalRenderer {
    private let cols: Int
    private let rows: Int

    /// Scrollback capacity in lines. Output longer than `rows + scrollback`
    /// loses its OLDEST lines — for `claude /usage` that's the quota sections
    /// at the top, so keep this comfortably above the tallest known screen.
    private let scrollback = 2000

    /// Creates a terminal renderer with the specified dimensions.
    /// - Parameters:
    ///   - cols: Number of columns (default: 160)
    ///   - rows: Number of rows (default: 50)
    public init(cols: Int = 160, rows: Int = 50) {
        self.cols = cols
        self.rows = rows
    }

    /// Renders raw terminal output into clean text.
    ///
    /// - Parameter raw: Raw terminal output containing ANSI escape sequences
    /// - Returns: Clean rendered text as it would appear in a terminal
    public func render(_ raw: String) -> String {
        let delegate = RenderDelegate()
        // Enable convertEol to handle \n as \r\n (newline + carriage return)
        let options = TerminalOptions(cols: cols, rows: rows, convertEol: true, scrollback: scrollback)
        let terminal = Terminal(delegate: delegate, options: options)

        // Feed the raw output to the terminal emulator
        terminal.feed(text: raw)

        // Extract the rendered screen content
        return extractScreenText(from: terminal)
    }

    /// Extracts text content from the terminal buffer, including scrollback.
    ///
    /// Output taller than the terminal (e.g. `claude /usage`'s usage-contribution
    /// report) scrolls its earlier lines off the visible screen into scrollback;
    /// reading only the visible rows would silently drop them.
    private func extractScreenText(from terminal: Terminal) -> String {
        var lines: [String] = []

        // Iterate the whole buffer (scrollback + visible screen).
        // getScrollInvariantLine returns nil past the end of the buffer, and
        // for rows trimmed off the front when scrollback overflows.
        for row in 0..<(rows + scrollback) {
            guard let line = terminal.getScrollInvariantLine(row: row) else {
                continue
            }

            var lineText = ""
            for col in 0..<cols {
                let charData = line[col]
                let char = charData.getCharacter()
                // Replace null character (empty cell) with space
                lineText.append(char == "\0" ? " " : char)
            }

            // Trim trailing spaces from each line
            lines.append(lineText.trimmingCharacters(in: CharacterSet(charactersIn: " \t\0")))
        }

        // Join lines and trim trailing empty lines
        return lines
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .joined(separator: "\n")
    }
}
