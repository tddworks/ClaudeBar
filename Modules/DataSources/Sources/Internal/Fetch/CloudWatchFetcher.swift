import Diagnostics
import Quotas
import Foundation

/// `cloudWatch` — today's sums, one row per dimension value in each region,
/// priced when the call names a price list. A region that fails is logged and
/// left out; every region failing is the failure.
struct CloudWatchFetcher: Fetching {
    let call: CloudWatchCall
    let client: (any CloudWatchClient)?
    let catalog: (any PriceCatalog)?
    let now: @Sendable () -> Date

    func isReady() -> Bool { client != nil && !call.regionList.isEmpty }

    func fetch(with credential: Credential?) async throws -> Response {
        guard let client else { throw UsageError.executionFailed("This build can't read cloud metrics") }
        let regions = call.regionList
        guard !regions.isEmpty else { throw UsageError.executionFailed("No regions configured") }
        let end = now()
        let start = Calendar.current.startOfDay(for: end)

        var rows: [[String: Any]] = []
        var firstError: Error?
        var answered = false
        for region in regions {
            do {
                let sums = try await client.sums(namespace: call.namespace, dimension: call.dimension, metrics: call.metrics,
                                                 region: region, profile: call.profileName, from: start, to: end)
                answered = true
                for (id, metrics) in sums.sorted(by: { $0.key < $1.key }) {
                    var row: [String: Any] = ["id": id, "region": region]
                    for (name, value) in metrics { row[name] = value }
                    rows.append(row)
                }
            } catch {
                AppLog.probes.warning("\(call.namespace) metrics in \(region) failed: \(error.localizedDescription)")
                firstError = firstError ?? error
            }
        }
        if !answered, let firstError { throw firstError }

        var body: [String: Any] = ["rows": rows, "periodStart": start.timeIntervalSince1970]
        if let service = call.prices, let catalog {
            let ids = Array(Set(rows.compactMap { $0["id"] as? String })).sorted()
            body["prices"] = ids.isEmpty ? [:] : await catalog.prices(service: service, ids: ids)
        }
        return Response(body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    }
}
