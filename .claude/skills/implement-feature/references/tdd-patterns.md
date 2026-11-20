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
@testable import Quotas   // the module under test; @testable reaches its Internal/

@Suite
struct UsageQuotaTests {
    @Test func `should show a quota as depleted when nothing is left`() {
        let quota = UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "test")
        #expect(quota.status == .depleted)
        #expect(quota.isDepleted == true)
    }
}
```

## Naming tests

A test name is the behaviour it guards, as one sentence in a backtick
identifier:

```
should <outcome the person / menu bar / login / provider observes> [when <domain situation>]
```

- **Say what the person gets, not which code runs.** The actors are the
  person reading their quotas, the menu bar and its pills, a login, a
  provider, a CLI or API ClaudeBar asks. The name never holds a method or
  type name (`refresh`, `UsageSnapshot`), a JSON key (`usedPercent`), or a
  mechanism verb (`returns`, `parses`, `calls`, `maps`, `fires`).
- **The `when` is a fact about the world**, not a code path: "when the saved
  login is refused", not "when `fetch` throws".
- **Pair every happy path with its counterpart.** "should show the weekly
  window" travels with "should show no weekly window when the plan has none".
- **The body follows the sentence**: arrange the situation (stub the port),
  do one thing through the public surface, assert the resulting state
  (Chicago school: no `verify()`).

| Mechanism-shaped (avoid) | Business-shaped |
|---|---|
| `rpc reads the session and weekly windows` | `should show the session and weekly windows when Codex answers over RPC` |
| `a refused saved login asks to sign in again` | `should ask to sign in again when the saved login is refused` |
| `neither running nor signed in is not available` | `should be unavailable when the app is neither running nor signed in` |
| `an empty environment key falls back to the saved default key` | `should use the saved key when the environment key is empty` |
| `formats metric as expected` | `should print the cost in dollars with two decimals` |

Older tests predate this rule. Rename one to this shape when you change it
or its file; don't sweep files you aren't otherwise changing.

## Given-When-Then Structure

```swift
@Test func `should warn when between 20 and 50 percent is left`() {
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
    func `should show the session and weekly windows when Codex answers over RPC`() async throws {
        // Given - STUB the connection to answer with a captured response
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":30},"secondary":{"usedPercent":50}}}}"#)
        let codex = try stub.make("codex")
        let login = codex.defaultAccount

        // When
        let usage = try await codex.refresh(login)

        // Then - verify STATE, not that methods were called
        #expect(usage.quota(for: .session)?.percentRemaining == 70)
        #expect(login.answeredBy == "rpc")
        #expect(login.lastError == nil)
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
func `should say the key is missing when the API has no key`() async throws {
    let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
    defer { stub.cleanUp() }
    let codex = try stub.make("codex")
    let login = codex.defaultAccount

    await #expect(throws: UsageError.self) { try await codex.refresh(login) }
    #expect(login.lastFailedStep == .lookup)
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
Sources/Modules/<Context>/Tests/   # the Mac app's own modules: Activity, Alerting, LocalAPI, Storage
Tests/
├── AppTests/                 # view logic
└── AcceptanceTests/          # specs composing real modules with stubbed ports
```

## Running Tests

```bash
tuist test Providers         # one module's tests (a scheme per module, plus AppTests, AcceptanceTests)
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
| Workers/DataSources | Return values, thrown errors, resulting state     |
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