import ClaudeBarQuotas
import Foundation

// The platform edge stays Swift: here a stub; in the app, the CLI/Keychain/URLSession fetch.
final class StubSource: NSObject, QuotaSource {
    // SKIE hides the suspend requirement as `__fetch`; a Swift implementer must use that name.
    func __fetch() async throws -> [Quota] {
        [
            Quota(left: LeftShare(percent: 90), type: QuotaTypeSession.shared, providerId: "claude",
                  resetsAtMillis: nil, windowMillis: nil),
            Quota(left: LeftShare(percent: 12), type: QuotaTypeWeekly.shared, providerId: "claude",
                  resetsAtMillis: nil, windowMillis: nil),
        ]
    }
}

let now = Int64(Date().timeIntervalSince1970 * 1000)

// 1. Enums: a native Swift enum, exhaustive switch.
func label(_ status: QuotaStatus) -> String {
    switch status {
    case .healthy: "healthy"
    case .warning: "warning"
    case .critical: "critical"
    case .depleted: "depleted"
    }
}

// 2. Sealed: exhaustive switch via onEnum(of:).
func describe(_ type: QuotaType) -> String {
    switch onEnum(of: type) {
    case .session: "5h"
    case .weekly: "7d"
    case .modelSpecific(let m): m.modelName
    case .timeLimit(let t): t.name
    }
}

print("key round-trip:", QuotaTypeCompanion.shared.fromQuotaKey(quotaKey: "model:opus").map(describe) ?? "nil")
print("display name:", QuotaTypeModelSpecific(modelName: "opus sonnet").displayName)

let balance = Quota(left: LeftBalance(remaining: Money(minorUnits: 1240, currency: "USD"), ceiling: nil),
                    type: QuotaTypeTimeLimit(name: "Credits"), providerId: "openrouter",
                    resetsAtMillis: nil, windowMillis: nil)
print("balance percentLeft:", balance.percentLeft as Any, "status:", label(balance.status))

// 3. suspend → async, StateFlow → AsyncSequence.
let feed = QuotaFeed(source: StubSource(), policy: StatusPolicyAbsolute.shared)
let watcher = Task {
    for await status in feed.overall {
        print("flow emitted:", label(status))
        if status == .critical { break }
    }
}
let result = try await feed.refresh(nowMillis: now)
print("refresh returned:", label(result))
await watcher.value

// 4. Sendable: Kotlin classes arrive non-Sendable, so Swift 6 refuses to send them across
//    actors. They are immutable data classes, so the app would vouch for each one by hand.
extension Quota: @retroactive @unchecked Sendable {}
func requireSendable<T: Sendable>(_ value: T) -> T { value }
let sendable = balance
let crossed = await Task.detached { [sendable] in requireSendable(sendable).providerId }.value
print("crossed actor boundary:", crossed)
