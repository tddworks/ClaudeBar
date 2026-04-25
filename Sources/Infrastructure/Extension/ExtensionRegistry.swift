import Foundation
import Domain

/// Discovers extensions from disk, creates ExtensionProviders, and registers them with QuotaMonitor.
public final class ExtensionRegistry: Sendable {
    private let extensionsDirectory: URL
    private let scanner: ExtensionDirectoryScanner
    private let settingsRepository: ProviderSettingsRepository
    private let configRepository: (any ExtensionConfigRepository)?
    private let cliExecutor: CLIExecutor?

    /// Default extensions directory: ~/.claudebar/extensions/
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudebar")
            .appendingPathComponent("extensions")
    }

    public init(
        extensionsDirectory: URL? = nil,
        scanner: ExtensionDirectoryScanner = ExtensionDirectoryScanner(),
        settingsRepository: ProviderSettingsRepository,
        configRepository: (any ExtensionConfigRepository)? = nil,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.extensionsDirectory = extensionsDirectory ?? Self.defaultDirectory
        self.scanner = scanner
        self.settingsRepository = settingsRepository
        self.configRepository = configRepository
        self.cliExecutor = cliExecutor
    }

    /// Scans for extensions and registers them with the monitor.
    /// Returns the list of registered extension providers.
    @discardableResult
    public func loadExtensions(into monitor: QuotaMonitor) -> [ExtensionProvider] {
        ensureDirectoryExists()

        let scanResults = scanner.scan(directory: extensionsDirectory)
        var providers: [ExtensionProvider] = []

        for result in scanResults {
            let probes = createProbes(for: result)
            let provider = ExtensionProvider(
                manifest: result.manifest,
                probes: probes,
                settingsRepository: settingsRepository
            )
            monitor.addProvider(provider)
            providers.append(provider)
        }

        return providers
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: extensionsDirectory.path) {
            try? fm.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
        }
    }

    private func createProbes(for result: ExtensionScanResult) -> [String: any UsageProbe] {
        var probes: [String: any UsageProbe] = [:]
        let providerId = "ext-\(result.manifest.id)"

        for section in result.manifest.sections {
            let probe: any UsageProbe
            switch section.probeConfig {
            case .script(let command):
                probe = ScriptProbe(
                    scriptPath: command,
                    extensionDir: result.directory,
                    providerId: providerId,
                    sectionType: section.type,
                    timeout: section.timeout,
                    cliExecutor: cliExecutor,
                    configRepository: configRepository,
                    manifest: result.manifest
                )
            case .healthCheck(let url):
                probe = HealthCheckProbe(
                    url: url,
                    providerId: providerId,
                    timeout: section.timeout
                )
            }
            probes[section.id] = probe
        }

        return probes
    }
}
