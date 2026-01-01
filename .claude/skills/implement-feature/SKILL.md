---
name: implement-feature
description: |
  Guide for implementing features in ClaudeBar following TDD, rich domain models, and Swift 6.2 patterns. Use this skill when:
  (1) Adding new functionality to the app
  (2) Creating domain models that follow user's mental model
  (3) Building SwiftUI views that consume domain models directly
  (4) User asks "how do I implement X" or "add feature Y"
  (5) Implementing any feature that spans Domain, Infrastructure, and App layers
---

# Implement Feature in ClaudeBar

Implement features using TDD, rich domain models, and Swift 6.2 patterns.

## Core Principles

### 1. Rich Domain Models (User's Mental Model)

Domain models encapsulate behavior, not just data:

```swift
// Rich domain model with behavior
public struct UsageQuota: Sendable, Equatable {
    public let percentRemaining: Double

    // Domain behavior - computed from state
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    public var isDepleted: Bool { percentRemaining <= 0 }
    public var needsAttention: Bool { status.needsAttention }
}
```

### 2. Swift 6.2 Patterns (No ViewModel Layer)

Use `@Observable` classes with views consuming domain models directly:

```swift
@Observable
final class AppState {
    var providers: [any AIProvider] = []
    var overallStatus: QuotaStatus {
        providers.compactMap(\.snapshot?.overallStatus).max() ?? .healthy
    }
}

struct ProviderSectionView: View {
    let snapshot: UsageSnapshot  // Domain model directly

    var body: some View {
        Text(snapshot.overallStatus.displayName)
    }
}
```

### 3. Protocol-Based DI with @Mockable

```swift
@Mockable
public protocol UsageProbe: Sendable {
    func probe() async throws -> UsageSnapshot
    func isAvailable() async -> Bool
}
```

## Architecture

```
Domain (Sources/Domain/)
├── Rich models with behavior
├── Protocols defining capabilities
└── Actors for thread-safe services

Infrastructure (Sources/Infrastructure/)
├── Protocol implementations
├── CLI probes, network clients
└── Adapters (excluded from coverage)

App (Sources/App/)
├── Views with domain models
├── @Observable AppState
└── No ViewModel layer
```

## TDD Workflow

### Phase 1: Domain Model Tests

```swift
@Suite
struct FeatureModelTests {
    @Test func `model computes status from state`() {
        let model = FeatureModel(value: 50)
        #expect(model.status == .normal)
    }
}
```

### Phase 2: Infrastructure Tests

```swift
@Suite
struct FeatureServiceTests {
    @Test func `service returns data on success`() async throws {
        let mockClient = MockNetworkClient()
        given(mockClient).fetch(...).willReturn(Data())

        let service = FeatureService(client: mockClient)
        let result = try await service.fetch()

        #expect(result != nil)
    }
}
```

### Phase 3: Integration

Wire up in `ClaudeBarApp.swift` and create views.

## References

- [Swift 6.2 @Observable patterns](references/swift-observable.md)
- [Rich domain model patterns](references/domain-models.md)
- [TDD test patterns](references/tdd-patterns.md)

## Checklist

- [ ] Define domain models in `Sources/Domain/` with behavior
- [ ] Write domain model tests (test behavior, not data)
- [ ] Define protocols with `@Mockable`
- [ ] Implement infrastructure in `Sources/Infrastructure/`
- [ ] Write infrastructure tests with mocks
- [ ] Create views consuming domain models directly
- [ ] Use `@Observable` for shared state
- [ ] Run `swift test` to verify all tests pass