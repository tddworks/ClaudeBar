import DataSources
import Foundation
import Providers
import Quotas

/// Kimi's mappings read through its definition, as the old probes' fixtures were.
enum KimiDefinitionFixtures {
    static func read(_ response: Response, kind: String, providerId: String = "kimi") throws -> UsageSnapshot {
        let definition = try Providers.builtIn("kimi")
        let source = DataSources.make(definition.dataSource(kind)!, providerId: providerId, scripts: Providers.builtInScripts,
                                      environment: { _ in nil })
        do { return try source.read(response) }
        catch let error as DataSourceError { throw error.reason }
    }
    static func api(_ data: Data, providerId: String) throws -> UsageSnapshot { try read(Response(body: data), kind: "api", providerId: providerId) }
    static func cli(_ text: String) throws -> UsageSnapshot { try read(Response(text: text), kind: "cli") }
    static func reset(_ text: String) -> Date? { (try? cli("Weekly limit 100% left (resets in \(text))"))?.quotas.first?.resetsAt }
}
