import Foundation

/// Renders raw terminal output with ANSI escape sequences into clean text.
///
/// On macOS 13+, uses SwiftTerm's terminal emulator for proper cursor movement
/// and screen clearing handling. On macOS 12, falls back to basic ANSI stripping.
public final class TerminalRenderer {
    private let cols: Int
    private let rows: Int

    public init(cols: Int = 160, rows: Int = 50) {
        self.cols = cols
        self.rows = rows
    }

    public func render(_ raw: String) -> String {
        #if canImport(SwiftTerm)
        if #available(macOS 13, *) {
            return _SwiftTermRenderer(cols: cols, rows: rows).render(raw)
        }
        #endif
        return stripAnsiEscapes(raw)
    }

    private func stripAnsiEscapes(_ text: String) -> String {
        var result = text
        // Remove CSI sequences: ESC [ (params) (final byte)
        result = result.replacingOccurrences(
            of: #"\x1b\[[0-9;?]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
        // Remove OSC sequences: ESC ] (text) BEL
        result = result.replacingOccurrences(
            of: #"\x1b\][^\x07]*\x07"#,
            with: "",
            options: .regularExpression
        )
        // Remove carriage returns
        result = result.replacingOccurrences(of: "\r", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
