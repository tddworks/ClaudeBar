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
        let options = TerminalOptions(cols: cols, rows: rows, convertEol: true)
        let terminal = Terminal(delegate: delegate, options: options)

        // Feed the raw output to the terminal emulator
        terminal.feed(text: raw)

        // Extract the rendered screen content
        return extractScreenText(from: terminal)
    }

    /// Extracts text content from the terminal buffer.
    private func extractScreenText(from terminal: Terminal) -> String {
        var lines: [String] = []

        // Iterate through all lines in the terminal buffer
        for row in 0..<rows {
            guard let line = terminal.getLine(row: row) else {
                lines.append("")
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
