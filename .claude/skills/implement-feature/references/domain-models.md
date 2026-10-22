# Rich Domain Model Patterns

The basic patterns. Before any change, think how the domain should be: [domain-shape.md](domain-shape.md) (seven questions for a domain easy to understand, with one reason to change and each concern on its own side).

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

    // User asks: "When does it reset?" — the fact; the card's sentence is the App's
    public var timeUntilReset: TimeInterval? { … }
}
```

The value answers in facts, and may write a fact it owns one way
(`formattedDollarUsed`, through `MoneyFormat`). A screen's sentences and labels
("Resets in 2h", "No forecast yet") are the App's, in its words type
(`QuotaCardText`), so the kernel never changes for a wording.

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
}
```

## Capabilities as Handles

A capability a product may or may not offer is declared in its definition and
reached through a handle that is `nil` when it isn't — never a flag, a cast
or a protocol every provider half-implements:

```swift
@MainActor @Observable
public final class Provider {
    public let definition: ProviderDefinition
    public private(set) var accounts: [Account]   // its logins
    /// *In use* — nil when the definition declares no sign-in to choose from.
    public var inUse: InUse? { ... }
}

if let inUse = provider.inUse { try inUse.use(account) }   // ask the product, never the login
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

    public static func from(percentRemaining: Double) -> QuotaStatus {
        switch percentRemaining {
        case 0: return .depleted
        case 0..<20: return .critical
        case 20..<50: return .warning
        default: return .healthy
        }
    }
}

// The colour is the App's, never the kernel's (no SwiftUI in Quotas)
extension QuotaStatus {
    var color: Color { … }   // Sources/App, beside the theme
}
```

## Actors for Thread Safety

Use actors for stateful domain services:

```swift
@MainActor @Observable
public final class QuotaMonitor {
    public let providers: Providers               // the providers you keep
    private var previousStatuses: [String: QuotaStatus] = [:]

    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for login in providers.lineup {
                group.addTask { await self.refresh(login) }
            }
        }
    }

    public var overallStatus: QuotaStatus {
        providers.lineup.compactMap { $0.snapshot?.overallStatus }.max() ?? .healthy
    }
}
```

## Values Built From Values

When a type starts answering a second kind of question, the question is a
concept of its own. Give it its own value, built from the one below, rather
than another read on the first (SRP):

```swift
// Days: the range — its days, the units it offers, a day's value in a unit
public struct Days { public var units: [Unit]; public var defaultUnit: Unit
                     public func total(in unit: Unit) -> Double }

// "Which models do I lean on?" — its own value, read in the unit the view chose
public struct ModelMix {
    public struct Part { public let line: ModelUsageLine; public let value: Double; public let share: Double }
    public let parts: [Part]                     // largest first; the unnamed line among them
    public var top: Part? { parts.first }
    public init(of days: Days, in unit: Days.Unit)
}

// "Two lines of one model add up" — the line owns its own sum
extension ModelUsageLine { static func + (lhs: Self, rhs: Self) -> Self }

// Anything that needs the top model reuses the mix; it never counts again
let top = ModelMix(of: week, in: unit).top
```

Each value gets its own suite on a neutral fixture. A part carries its own
share, so a view never asks the range about a line.

## Factory Methods

Use a static factory when a rule decides which value to build:

```swift
extension QuotaStatus {
    static func from(percentRemaining: Double) -> QuotaStatus {
        // Business rule encapsulated here
    }
}
```