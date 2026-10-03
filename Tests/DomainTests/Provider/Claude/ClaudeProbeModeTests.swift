import Testing
@testable import Domain

@Suite("ClaudeProbeMode Tests")
struct ClaudeProbeModeTests {

    // MARK: - Cases

    @Test
    func `probe mode has cli api and localFile cases`() {
        #expect(ClaudeProbeMode.allCases == [.cli, .api, .localFile])
    }

    @Test
    func `localFile raw value is localFile`() {
        #expect(ClaudeProbeMode(rawValue: "localFile") == .localFile)
    }

    // MARK: - Display

    @Test
    func `localFile display name is Local File`() {
        #expect(ClaudeProbeMode.localFile.displayName == "Local File")
    }

    @Test
    func `localFile description marks the mode as best-effort`() {
        // The mode reads an implementation detail of Claude Desktop, so the
        // Settings UI must label it best-effort (issue #198).
        let description = ClaudeProbeMode.localFile.description
        #expect(description.contains("Claude Desktop"))
        #expect(description.lowercased().contains("best-effort"))
    }
}
