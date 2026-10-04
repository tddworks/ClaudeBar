# TDD Test Patterns (Chicago School)

We follow **Chicago school TDD** (state-based testing):

| Chicago School (We Use This)          | London School (Avoid)                    |
|---------------------------------------|------------------------------------------|
| Test state changes and return values  | Test interactions between objects        |
| Mocks stub data, not verify calls     | Mocks verify method calls were made      |
| Focus on "what" (outcomes)            | Focus on "how" (behavior)                |
| Design emerges from tests             | Design upfront, tests verify design      |
| Fewer, coarser-grained tests          | Many fine-grained interaction tests      |

## Swift Testing Framework

Use `@Test` and `@Suite` instead of XCTest:

```swift
import Testing
import Foundation
@testable import Domain

@Suite
struct UsageQuotaTests {
    @Test func `quota at zero percent is depleted`() {
        let quota = UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "test")
        #expect(quota.status == .depleted)
        #expect(quota.isDepleted == true)
    }
}
```

## Given-When-Then Structure

```swift
@Test func `quota between 20 and 50 percent shows warning`() {
    // Given
    let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")

    // When
    let status = quota.status

    // Then
    #expect(status == .warning)
}
```

## Mocking with @Mockable (Chicago Style)

Ports — what lies outside the app — are `@Mockable` protocols at a module's
root:

```swift
@Mockable
public protocol NetworkClient: Sendable {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse)
}

@Mockable
public protocol CLIExecutor: Sendable {
    func locate(_ binary: String) -> String?
    func execute(binary: String, args: [String], input: String?, timeout: TimeInterval,
                 workingDirectory: URL?, autoResponses: [String: String]) async throws -> CLIResult
}
```

**Chicago school mock usage** — stub what the port answers, assert on the
resulting state. A provider's tests run its **real definition** through the real
`Provider` and `DataSource`, with only the connections stubbed:

```swift
@MainActor
@Suite
struct CodexDefinitionTests {
    @Test
    func `rpc reads the session and weekly windows`() async throws {
        // Given - STUB the connection to answer with a captured response
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":30},"secondary":{"usedPercent":50}}}}"#)
        let codex = try stub.make("codex")

        // When
        let usage = try await codex.refresh()

        // Then - verify STATE, not that methods were called
        #expect(usage.quota(for: .session)?.percentRemaining == 70)
        #expect(codex.answeredBy == "rpc")
        #expect(codex.lastError == nil)
        // ❌ AVOID: verify(stub.transport).send(.any).called(2)  // London school
    }
}
```

**Key principle**: Use `given().willReturn()` / `willProduce` to stub data.
Avoid `verify().called()`. In `@MainActor` suites, mark `willProduce` and
`.matching` closures `@Sendable` — Mockable calls them off the main actor.

## Mapping Tests

A mapping is tested by the response it reads, through the definition — never
by calling a parser directly:

```swift
@Test
func `api without a key says so at the lookup step`() async throws {
    let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
    defer { stub.cleanUp() }
    let codex = try stub.make("codex")

    await #expect(throws: UsageError.self) { try await codex.refresh() }
    #expect(codex.lastFailedStep == .lookup)
}
```

A mapping script (`*.js`) is tested the same way, with real captured screens
(`ClaudeUsageScreenTests` reads 60+ of them through `ClaudeHarness`). A new
generic rule is tested in `Modules/DataSources/Tests/` against a small
inline definition.

## Test Organization

```
Modules/
├── DataSources/Tests/        # DataSource, workers, OAuth, HTTP, process runners
└── Providers/Tests/          # golden tests per definition: CodexDefinitionTests, ClaudeAPITests …
    └── Support/              # StubbedProvider, ClaudeHarness, InMemoryProviderSettings
Tests/
├── DomainTests/              # QuotaMonitor, legacy providers, the kernel's behaviour
├── InfrastructureTests/      # legacy probes, storage, notifications
├── AppTests/                 # view logic
└── AcceptanceTests/          # specs composing real modules with stubbed ports
```

## Running Tests

```bash
tuist test Providers         # one module's tests (schemes: Providers, DataSources, Domain, Infrastructure, AppTests, AcceptanceTests)
tuist test                     # everything
# tuist caches results; to force a re-run of one suite:
xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar-Workspace \
  -destination 'platform=macOS,arch=arm64' -only-testing:ProvidersTests/ClaudeAPITests
```

## Chicago School Summary

### What to Test

| Test Type           | What to Assert                                    |
|---------------------|---------------------------------------------------|
| Domain models       | Computed properties, state after mutations        |
| Services/Probes     | Return values, thrown errors, resulting state     |
| Actors              | State after operations complete                   |

### What NOT to Test

- That a method was called N times
- The order of internal method calls
- Implementation details that don't affect observable state

### Red-Green-Refactor Cycle

```
1. RED    - Write a failing test that asserts expected STATE
2. GREEN  - Write minimal code to make the test pass
3. REFACTOR - Improve code while keeping tests green
```

Design emerges from this cycle - don't design upfront, let tests guide you.