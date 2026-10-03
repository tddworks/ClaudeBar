# Stop using ViewModels - TDD with rich domain models is all you need

Hey r/SwiftUI!

Hot take: **ViewModels are unnecessary boilerplate in most SwiftUI apps.** We should avoid them.

I've been building **ClaudeBar** (open-source macOS menu bar app) with zero ViewModels. Views consume `@Observable` domain models directly. After months of development, I'm convinced this is the better approach.

## Why ViewModels Are a Problem

### 1. They duplicate state

```swift
// ViewModel copies domain state into @Published
class QuotaViewModel: ObservableObject {
    @Published var percentRemaining: Double = 0  // copy
    @Published var statusText: String = ""       // copy

    func update(from quota: UsageQuota) {
        self.percentRemaining = quota.percentRemaining
        self.statusText = quota.status.displayName
    }
}
```

Now you have two sources of truth. State sync bugs incoming.

### 2. They're testing theater

You write tests for ViewModels, but you're not testing real business logic. You're testing a middleman that forwards data.

### 3. They violate DRY

One ViewModel per view. Each one re-implements the same patterns: fetch, map, publish. Copy-paste architecture.

### 4. They hide domain anemia

When business logic lives in ViewModels, your domain models become dumb data bags. The real problem is anemic domain models - ViewModels are a symptom, not a solution.

## The Alternative: Rich Domain Models + TDD

**Put behavior where it belongs - in the domain:**

```swift
public struct UsageQuota: Sendable, Equatable {
    public let percentRemaining: Double

    // Domain owns its behavior
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    public var isDepleted: Bool { percentRemaining <= 0 }
    public var needsAttention: Bool { status.needsAttention }
    public var badgeText: String { status.badgeText }
}
```

**Test the domain, not a middleman:**

```swift
@Test func `quota is critical when below 20 percent`() {
    let quota = UsageQuota(percentRemaining: 15)

    #expect(quota.status == .critical)
    #expect(quota.needsAttention == true)
}

@Test func `provider updates snapshot after refresh`() async throws {
    let provider = makeProvider(probe: mockProbe)

    _ = try await provider.refresh()

    #expect(provider.snapshot != nil)
}
```

**Views become trivial - just render state:**

```swift
struct QuotaCard: View {
    let quota: UsageQuota  // Rich domain model

    var body: some View {
        VStack {
            Text("\(Int(quota.percentRemaining))%")
            Text(quota.badgeText)
            ProgressBar(value: quota.percentRemaining)
        }
        .foregroundStyle(quota.status.color)
    }
}
```

No ViewModel. No state duplication. The view is so simple it barely needs testing.

## The Architecture That Emerges

```
┌─────────────────────────────────────────┐
│  SwiftUI Views                          │
│  - Render domain state                  │
│  - Zero business logic                  │
│  - No ViewModels                        │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Domain Layer (@Observable)             │
│  - Single source of truth               │
│  - Rich models with behavior            │
│  - Thoroughly TDD tested                │
│  - Protocol-based DI                    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Infrastructure Layer                   │
│  - Implements domain protocols          │
│  - CLI, network, storage                │
└─────────────────────────────────────────┘
```

## "But I Need View-Specific Logic!"

Common objection. Here's the thing:

- **Formatting?** → Put it in the domain model or a simple extension
- **Derived state?** → Computed properties on the domain model
- **Multiple data sources?** → One `@Observable` coordinator (still domain, not ViewModel)

If you truly have view-specific presentation logic that doesn't belong in domain, extract it to a plain struct or function. You don't need a stateful `ObservableObject` for that.

## TDD Is the Enabler

This only works if you actually TDD your domain. Rich domain models without tests are just a different flavor of chaos.

Chicago School TDD (test state changes, not mock interactions) keeps the domain honest. When every business rule has a test, views can trust the domain completely.

## Try It

Next time you reach for a ViewModel, ask: *"Can this behavior live in the domain model?"*

Usually, yes.

- GitHub: [github.com/tddworks/claudebar](https://github.com/tddworks/claudebar)
- Full architecture docs in repo

Anyone else ditched ViewModels? What's been your experience?