import Foundation
import Domain

/// A UsageProbe that executes an external script and parses its JSON output.
/// Used by extension providers to probe custom data sources.
public final class ScriptProbe: UsageProbe, @unchecked Sendable {
    private let scriptPath: String
    private let extensionDir: URL
    private let providerId: String
    private let sectionType: SectionType
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor
    private let configRepository: (any ExtensionConfigRepository)?
    private let manifest: ExtensionManifest?

    public init(
        scriptPath: String,
        extensionDir: URL,
        providerId: String,
        sectionType: SectionType,
        timeout: TimeInterval = 10,
        cliExecutor: CLIExecutor? = nil,
        configRepository: (any ExtensionConfigRepository)? = nil,
        manifest: ExtensionManifest? = nil
    ) {
        self.scriptPath = scriptPath
        self.extensionDir = extensionDir
        self.providerId = providerId
        self.sectionType = sectionType
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.configRepository = configRepository
        self.manifest = manifest
    }

    public func probe() async throws -> UsageSnapshot {
        let command = buildCommand()

        let result = try cliExecutor.execute(
            binary: "/bin/sh",
            args: ["-c", command],
            input: nil,
            timeout: timeout,
            workingDirectory: extensionDir,
            autoResponses: [:]
        )

        guard result.exitCode == 0 else {
            throw ProbeError.executionFailed("Extension probe '\(scriptPath)' exited with code \(result.exitCode): \(result.output)")
        }

        guard let data = result.output.data(using: .utf8) else {
            throw ProbeError.parseFailed("Extension probe output is not valid UTF-8")
        }

        let sectionData = try SectionData.decode(from: data, type: sectionType, providerId: providerId)
        return sectionDataToSnapshot(sectionData)
    }

    public func isAvailable() async -> Bool {
        let resolvedPath = resolveScriptPath()
        return FileManager.default.fileExists(atPath: resolvedPath)
    }

    // MARK: - Private

    private func buildCommand() -> String {
        let resolvedPath = resolveScriptPath()

        guard let configRepository, let manifest, !manifest.configFields.isEmpty else {
            return resolvedPath
        }

        let values = configRepository.allValues(forExtensionId: manifest.id, fields: manifest.configFields)
        guard !values.isEmpty else {
            return resolvedPath
        }

        // Build "env VAR1=val1 VAR2=val2 ./probe.sh" command
        let envPairs = manifest.configFields.compactMap { field -> String? in
            guard let value = values[field.id] else { return nil }
            let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
            return "\(field.environmentVariableName)='\(escaped)'"
        }

        return "env \(envPairs.joined(separator: " ")) \(resolvedPath)"
    }

    private func resolveScriptPath() -> String {
        if scriptPath.hasPrefix("/") {
            return scriptPath
        }
        return extensionDir.appendingPathComponent(scriptPath).path
    }

    private func sectionDataToSnapshot(_ data: SectionData) -> UsageSnapshot {
        switch data {
        case .quotas(let quotas):
            return UsageSnapshot(providerId: providerId, quotas: quotas, capturedAt: Date())
        case .cost(let costUsage):
            return UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date(), costUsage: costUsage)
        case .daily(let report):
            return UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date(), dailyUsageReport: report)
        case .metrics(let metrics):
            return UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date(), extensionMetrics: metrics)
        case .status:
            return UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date())
        }
    }
}
