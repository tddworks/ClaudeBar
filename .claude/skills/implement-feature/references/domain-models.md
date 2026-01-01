# Rich Domain Model Patterns

## User's Mental Model

Domain models should match how users think about the domain:

```swift
// User thinks: "What's my quota status?"
public struct UsageQuota: Sendable, Equatable {
    public let percentRemaining: Double
    public let quotaType: QuotaType
    public let providerId: String
    public let resetsAt: Date?

    // User asks: "Am I running low?"
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    // User asks: "Is it empty?"
    public var isDepleted: Bool { percentRemaining <= 0 }

    // User asks: "Should I worry?"
    public var needsAttention: Bool { status.needsAttention }

    // User asks: "When does it reset?"
    public var resetDescription: String? {
        guard let timeUntilReset else { return nil }
        // Human-readable format
    }
}
```

## Behavior Over Data

Encapsulate domain rules in the model:

```swift
public struct UsageSnapshot: Sendable, Equatable {
    public let providerId: String
    public let quotas: [UsageQuota]
    public let capturedAt: Date

    // Domain rule: overall status is worst quota
    public var overallStatus: QuotaStatus {
        quotas.map(\.status).max() ?? .healthy
    }

    // Domain rule: lowest quota needs attention first
    public var lowestQuota: UsageQuota? {
        quotas.min()
    }

    // Domain rule: stale after 5 minutes
    public var isStale: Bool {
        capturedAt.timeIntervalSinceNow < -300
    }

    public var ageDescription: String {
        // Human-readable age
    }
}
```

## Protocols for Capabilities

Define protocols for what entities can do:

```swift
public protocol AIProvider: AnyObject, Sendable, Identifiable {
    var id: String { get }
    var name: String { get }
    var isSyncing: Bool { get }
    var snapshot: UsageSnapshot? { get }
    var lastError: Error? { get }

    func isAvailable() async -> Bool
    func refresh() async throws -> UsageSnapshot
}
```

## Value Types for Data

Use structs for immutable data with behavior:

```swift
public struct UsageQuota: Sendable, Equatable, Hashable, Comparable {
    // Immutable data
    public let percentRemaining: Double

    // Computed behavior
    public var percentUsed: Double { 100 - percentRemaining }

    // Comparable for sorting
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.percentRemaining < rhs.percentRemaining
    }
}
```

## Enums for States

Use enums with behavior for finite states:

```swift
public enum QuotaStatus: Int, Comparable, Sendable {
    case healthy = 0
    case warning = 1
    case critical = 2
    case depleted = 3

    public var needsAttention: Bool {
        self >= .warning
    }

    public var displayColor: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .orange
        case .critical, .depleted: return .red
        }
    }

    public static func from(percentRemaining: Double) -> QuotaStatus {
        switch percentRemaining {
        case 0: return .depleted
        case 0..<20: return .critical
        case 20..<50: return .warning
        default: return .healthy
        }
    }
}
```

## Actors for Thread Safety

Use actors for stateful domain services:

```swift
public actor QuotaMonitor {
    private let providers: [any AIProvider]
    private var previousStatuses: [String: QuotaStatus] = [:]

    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask { await self.refreshProvider(provider) }
            }
        }
    }

    public func overallStatus() -> QuotaStatus {
        providers.compactMap(\.snapshot?.overallStatus).max() ?? .healthy
    }
}
```

## Factory Methods

Use static methods for complex construction:

```swift
extension UsageQuota {
    static func from(cliOutput: String, providerId: String) throws -> UsageQuota {
        // Parse CLI output into domain model
    }
}

extension QuotaStatus {
    static func from(percentRemaining: Double) -> QuotaStatus {
        // Business rule encapsulated here
    }
}
```