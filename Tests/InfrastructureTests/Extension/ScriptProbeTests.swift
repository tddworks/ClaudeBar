import Foundation
import Testing
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct ScriptProbeTests {
    // MARK: - Successful Probing

    @Test
    func `probe executes script and returns snapshot with quotas`() async throws {
        let scriptOutput = """
        {
            "quotas": [
                {
                    "type": "session",
                    "percentRemaining": 97.0,
                    "resetsAt": "2026-03-17T18:00:00Z"
                },
                {
                    "type": "weekly",
                    "percentRemaining": 69.0
                }
            ]
        }
        """

        let executor = MockCLIExecutor()
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: scriptOutput, exitCode: 0))
        given(executor).locate(.any).willReturn("/path/to/probe.sh")

        let probe = ScriptProbe(
            scriptPath: "/ext/probe.sh",
            extensionDir: URL(fileURLWithPath: "/ext"),
            providerId: "test",
            sectionType: .quotaGrid,
            timeout: 10,
            cliExecutor: executor
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "test")
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas[0].quotaType == .session)
        #expect(snapshot.quotas[0].percentRemaining == 97.0)
        #expect(snapshot.quotas[1].quotaType == .weekly)
    }

    @Test
    func `probe parses metrics into extensionMetrics`() async throws {
        let scriptOutput = """
        {
            "metrics": [
                {
                    "label": "Cost",
                    "value": "$10.26",
                    "unit": "Spent",
                    "progress": 0.5
                }
            ]
        }
        """

        let executor = MockCLIExecutor()
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: scriptOutput, exitCode: 0))
        given(executor).locate(.any).willReturn("/bin/sh")

        let probe = ScriptProbe(
            scriptPath: "./probe.sh",
            extensionDir: URL(fileURLWithPath: "/ext"),
            providerId: "test",
            sectionType: .metricsRow,
            timeout: 10,
            cliExecutor: executor
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.extensionMetrics?.count == 1)
        #expect(snapshot.extensionMetrics?[0].label == "Cost")
        #expect(snapshot.extensionMetrics?[0].value == "$10.26")
    }

    @Test
    func `probe parses cost usage`() async throws {
        let scriptOutput = """
        {
            "costUsage": {
                "totalCost": 10.26,
                "apiDuration": 454.0
            }
        }
        """

        let executor = MockCLIExecutor()
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: scriptOutput, exitCode: 0))
        given(executor).locate(.any).willReturn("/bin/sh")

        let probe = ScriptProbe(
            scriptPath: "./probe.sh",
            extensionDir: URL(fileURLWithPath: "/ext"),
            providerId: "test",
            sectionType: .costUsage,
            timeout: 10,
            cliExecutor: executor
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "10.26"))
    }

    // MARK: - Error Handling

    @Test
    func `probe throws on non-zero exit code`() async {
        let executor = MockCLIExecutor()
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "error occurred", exitCode: 1))
        given(executor).locate(.any).willReturn("/bin/sh")

        let probe = ScriptProbe(
            scriptPath: "./probe.sh",
            extensionDir: URL(fileURLWithPath: "/ext"),
            providerId: "test",
            sectionType: .quotaGrid,
            timeout: 10,
            cliExecutor: executor
        )

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws on invalid JSON output`() async {
        let executor = MockCLIExecutor()
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: "not json", exitCode: 0))
        given(executor).locate(.any).willReturn("/bin/sh")

        let probe = ScriptProbe(
            scriptPath: "./probe.sh",
            extensionDir: URL(fileURLWithPath: "/ext"),
            providerId: "test",
            sectionType: .quotaGrid,
            timeout: 10,
            cliExecutor: executor
        )

        await #expect(throws: (any Error).self) {
            try await probe.probe()
        }
    }

    // MARK: - Availability

    @Test
    func `isAvailable returns true when script exists`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scriptFile = tempDir.appendingPathComponent("probe.sh")
        try "#!/bin/sh\necho '{}'".write(to: scriptFile, atomically: true, encoding: .utf8)

        let executor = MockCLIExecutor()

        let probe = ScriptProbe(
            scriptPath: "./probe.sh",
            extensionDir: tempDir,
            providerId: "test",
            sectionType: .quotaGrid,
            timeout: 10,
            cliExecutor: executor
        )

        let available = await probe.isAvailable()
        #expect(available == true)
    }

    // MARK: - Config Injection

    @Test
    func `probe injects config values as env vars in command`() async throws {
        let scriptOutput = """
        { "quotas": [{ "type": "session", "percentRemaining": 80.0 }] }
        """

        let executor = MockCLIExecutor()
        var capturedArgs: [String] = []
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, args, _, _, _, _ in
                capturedArgs = args
                return CLIResult(output: scriptOutput, exitCode: 0)
            }

        let configRepo = MockExtensionConfigRepository()
        let fields = [
            ConfigField(id: "apiKey", label: "Key", type: .secret),
            ConfigField(id: "baseUrl", label: "URL", type: .string, defaultValue: "https://default.com"),
        ]
        given(configRepo)
            .allValues(forExtensionId: .value("openrouter"), fields: .any)
            .willReturn(["apiKey": "sk-123", "baseUrl": "https://custom.com"])

        let manifest = ExtensionManifest(
            id: "openrouter", name: "OpenRouter", version: "1.0.0",
            configFields: fields,
            sections: [ExtensionSection(id: "q", type: .quotaGrid, probeCommand: "./probe.sh")]
        )

        let probe = ScriptProbe(
            scriptPath: "./probe.sh",
            extensionDir: URL(fileURLWithPath: "/ext"),
            providerId: "ext-openrouter",
            sectionType: .quotaGrid,
            timeout: 10,
            cliExecutor: executor,
            configRepository: configRepo,
            manifest: manifest
        )

        _ = try await probe.probe()

        // The command should contain env var exports before the script
        let command = capturedArgs.last ?? ""
        #expect(command.contains("CLAUDEBAR_API_KEY="))
        #expect(command.contains("CLAUDEBAR_BASE_URL="))
        #expect(command.contains("./probe.sh"))
    }

    @Test
    func `probe runs without env vars when no config fields`() async throws {
        let scriptOutput = """
        { "quotas": [{ "type": "session", "percentRemaining": 80.0 }] }
        """

        let executor = MockCLIExecutor()
        var capturedArgs: [String] = []
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, args, _, _, _, _ in
                capturedArgs = args
                return CLIResult(output: scriptOutput, exitCode: 0)
            }

        let probe = ScriptProbe(
            scriptPath: "./probe.sh",
            extensionDir: URL(fileURLWithPath: "/ext"),
            providerId: "test",
            sectionType: .quotaGrid,
            timeout: 10,
            cliExecutor: executor
        )

        _ = try await probe.probe()

        // No env prefix — just the raw script path
        let command = capturedArgs.last ?? ""
        #expect(!command.contains("CLAUDEBAR_"))
    }

    @Test
    func `isAvailable returns false when script does not exist`() async {
        let executor = MockCLIExecutor()

        let probe = ScriptProbe(
            scriptPath: "./nonexistent.sh",
            extensionDir: URL(fileURLWithPath: "/nonexistent"),
            providerId: "test",
            sectionType: .quotaGrid,
            timeout: 10,
            cliExecutor: executor
        )

        let available = await probe.isAvailable()
        #expect(available == false)
    }
}
