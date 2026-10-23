#if os(macOS)
import DataSources
import Quotas

extension ClaudeHarness {
    /// Raw terminal bytes, drawn by the terminal emulator first — what the
    /// `cli` fetch does with `"screen": "rendered"`. The emulator is the Mac's.
    func readRawUsageScreen(_ raw: String) throws -> UsageSnapshot {
        try readUsageScreen(TerminalRenderer().render(raw))
    }
}
#endif
