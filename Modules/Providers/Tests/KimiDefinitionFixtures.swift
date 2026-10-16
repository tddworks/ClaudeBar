@testable import DataSources
import Foundation
import Providers
import Quotas

/// Kimi's mappings read through its definition, as the old probes' fixtures were.
enum KimiDefinitionFixtures {
    static func read(_ response: Response, kind: String, providerId: String = "kimi") throws -> UsageSnapshot {
        let definition = try ProviderFactory.builtIn("kimi")
        let source = DataSources.make(definition.dataSource(kind)!, providerId: providerId, scripts: ProviderFactory.builtInScripts,
                                      environment: { _ in nil })
        do { return try source.read(response) }
        catch let error as DataSourceError { throw error.reason }
    }
    static func api(_ data: Data, providerId: String) throws -> UsageSnapshot { try read(Response(body: data), kind: "api", providerId: providerId) }
    static func cli(_ text: String) throws -> UsageSnapshot { try read(Response(text: text), kind: "cli") }
    /// The CLI's screen read at `now` by a person in `zone`.
    static func cli(_ text: String, in zone: any TimeZoneSource, now: Date) throws -> UsageSnapshot {
        let definition = try ProviderFactory.builtIn("kimi")
        var platform = Platform.current
        platform.timeZone = zone
        let source = DataSources.make(definition.dataSource("cli")!, providerId: "kimi", platform: platform,
                                      network: MockNetworkClient(), scripts: ProviderFactory.builtInScripts,
                                      environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory,
                                      now: { now })
        return try source.read(Response(text: text))
    }
    static func reset(_ text: String) -> Date? { (try? cli("Weekly limit 100% left (resets in \(text))"))?.quotas.first?.resetsAt }
}
