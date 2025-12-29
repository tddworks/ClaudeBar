import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct AntigravityUsageProbeTests {

    // MARK: - Sample Data

    static let samplePsOutputWithAntigravity = """
    12345 /path/to/language_server_macos --csrf_token abc123token --extension_server_port 8080 --app_data_dir antigravity
    67890 /other/process --some-flag value
    """

    static let samplePsOutputWithAntigravityARM = """
    26416 /Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm --csrf_token 9f808dbe-cb96-4829 --extension_server_port 58445 --app_data_dir antigravity
    """

    static let samplePsOutputNoAntigravity = """
    12345 /path/to/some_other_binary --flag value
    67890 /another/process
    """

    static let samplePsOutputMissingToken = """
    12345 /path/to/language_server_macos --extension_server_port 8080 --app_data_dir antigravity
    """

    static let sampleLsofOutput = """
    COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    language  12345  user   10u  IPv4 0x1234567890abcdef      0t0  TCP 127.0.0.1:42135 (LISTEN)
    language  12345  user   11u  IPv4 0x1234567890abcdef      0t0  TCP 127.0.0.1:42136 (LISTEN)
    """

    static let sampleApiResponse = """
    {
      "userStatus": {
        "email": "user@example.com",
        "cascadeModelConfigData": {
          "clientModelConfigs": [
            {
              "label": "Claude Sonnet",
              "modelOrAlias": { "model": "claude-sonnet-4" },
              "quotaInfo": { "remainingFraction": 0.75, "resetTime": "2025-01-01T00:00:00Z" }
            }
          ]
        }
      }
    }
    """

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns false when process not running`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.samplePsOutputNoAntigravity, exitCode: 0))

        let probe = AntigravityUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable returns true when process detected with CSRF token`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.samplePsOutputWithAntigravity, exitCode: 0))

        let probe = AntigravityUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns true when ARM binary detected with CSRF token`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.samplePsOutputWithAntigravityARM, exitCode: 0))

        let probe = AntigravityUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when process running but CSRF token missing`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.samplePsOutputMissingToken, exitCode: 0))

        let probe = AntigravityUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Process Detection Parsing Tests

    @Test
    func `extracts CSRF token from process command line`() {
        // Given
        let commandLine = "/path/to/language_server_macos --csrf_token abc123token --extension_server_port 8080 --app_data_dir antigravity"

        // When
        let token = AntigravityUsageProbe.extractCSRFToken(from: commandLine)

        // Then
        #expect(token == "abc123token")
    }

    @Test
    func `extracts extension port from process command line`() {
        // Given
        let commandLine = "/path/to/language_server_macos --csrf_token abc123 --extension_server_port 8080 --app_data_dir antigravity"

        // When
        let port = AntigravityUsageProbe.extractExtensionPort(from: commandLine)

        // Then
        #expect(port == 8080)
    }

    @Test
    func `extracts PID from ps output line`() {
        // Given
        let line = "12345 /path/to/language_server_macos --csrf_token abc123 --app_data_dir antigravity"

        // When
        let pid = AntigravityUsageProbe.extractPID(from: line)

        // Then
        #expect(pid == 12345)
    }

    @Test
    func `identifies antigravity process by markers`() {
        // Given - Intel binary
        let antigravityLine = "/path/to/language_server_macos --app_data_dir antigravity"
        // ARM binary
        let antigravityARMLine = "/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm --csrf_token abc --app_data_dir antigravity"
        let otherLine = "/path/to/some_other_binary"
        let antigravityPathLine = "/Users/test/.antigravity/language_server_macos"

        // When & Then
        #expect(AntigravityUsageProbe.isAntigravityProcess(antigravityLine) == true)
        #expect(AntigravityUsageProbe.isAntigravityProcess(antigravityARMLine) == true)
        #expect(AntigravityUsageProbe.isAntigravityProcess(otherLine) == false)
        #expect(AntigravityUsageProbe.isAntigravityProcess(antigravityPathLine) == true)
    }

    // MARK: - Port Discovery Parsing Tests

    @Test
    func `parses listening ports from lsof output`() {
        // When
        let ports = AntigravityUsageProbe.parseListeningPorts(from: Self.sampleLsofOutput)

        // Then
        #expect(ports.count == 2)
        #expect(ports.contains(42135))
        #expect(ports.contains(42136))
    }

    @Test
    func `returns empty array when no ports found`() {
        // Given
        let emptyOutput = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"

        // When
        let ports = AntigravityUsageProbe.parseListeningPorts(from: emptyOutput)

        // Then
        #expect(ports.isEmpty)
    }

    // MARK: - Probe Error Tests

    @Test
    func `probe throws cliNotFound when no Antigravity process`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.samplePsOutputNoAntigravity, exitCode: 0))

        let probe = AntigravityUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        await #expect(throws: ProbeError.cliNotFound("Antigravity")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired when CSRF token missing`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.samplePsOutputMissingToken, exitCode: 0))

        let probe = AntigravityUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }
}
