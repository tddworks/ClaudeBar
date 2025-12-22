# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeBar is a macOS menu bar application that monitors AI coding assistant usage quotas (Claude, Codex, Gemini). It probes CLI tools to fetch quota information and displays it in a menu bar interface with system notifications for status changes.

## Build & Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run a specific test file
swift test --filter DomainTests

# Run a specific test
swift test --filter "QuotaMonitorTests/monitor fetches usage from a single provider"

# Run the app (requires macOS 15+)
swift run ClaudeBar
```

## Architecture

The project follows a layered architecture with protocol-based dependency injection:

### Layers

- **Domain** (`Sources/Domain/`): Pure business logic with no external dependencies
  - Provider (`Provider/`): `AIProvider` protocol, `UsageProbe` protocol, and rich models (`UsageQuota`, `UsageSnapshot`, `QuotaStatus`)
  - Monitor (`Monitor/`): `QuotaMonitor` actor and `StatusChangeObserver` protocol

- **Infrastructure** (`Sources/Infrastructure/`): Technical implementations
  - CLI (`CLI/`): Probes and protocols for CLI interaction
    - `ClaudeUsageProbe` - probes Claude CLI, uses `CLIExecutor` for testability
    - `CodexUsageProbe` - delegates to `CodexRPCClient` (single dependency)
    - `CodexRPCClient` protocol - "Is it available?" and "Get my stats"
    - `DefaultCodexRPCClient` - RPC via `RPCTransport`, falls back to TTY via `CLIExecutor`
    - `CLIExecutor` protocol - abstracts CLI interaction (locate binary, execute commands)
    - `RPCTransport` protocol - abstracts JSON-RPC communication
    - `GeminiUsageProbe` - coordinates `GeminiAPIProbe` with network client
    - `GeminiProjectRepository` - discovers Gemini projects for quota lookup
  - Adapters (`Adapters/`): Pure adapters for 3rd party interaction (excluded from coverage)
    - `PTYCommandRunner` - runs CLI commands with PTY for interactive prompts
    - `ProcessRPCTransport` - JSON-RPC over Process stdin/stdout pipes
    - `DefaultCLIExecutor` - real CLI execution using PTYCommandRunner
  - Network (`Network/`): `NetworkClient` protocol for HTTP abstraction
  - Notifications (`Notifications/`): `NotificationQuotaObserver` - macOS notification center

- **App** (`Sources/App/`): SwiftUI menu bar application
  - Views directly consume domain models (no ViewModel layer)
  - `AppState` is an `@Observable` class shared across views
  - `StatusBarIcon` - menu bar icon with status indicator

### Key Patterns

- **Protocol-Based DI**: Domain defines protocols (`UsageProbe`, `StatusChangeObserver`), infrastructure provides implementations
- **Actor-based concurrency**: `QuotaMonitor` is an actor for thread-safe state management
- **Mockable protocol mocks**: Uses `@Mockable` macro from Mockable package for test doubles
- **Swift Testing framework**: Tests use `@Test` and `@Suite` attributes, not XCTest
- **Adapters folder**: Pure 3rd-party wrappers excluded from code coverage

### Testability Design

The codebase separates testable logic from external system interaction:

- **Protocols with `@Mockable`**: `CLIExecutor`, `RPCTransport`, `CodexRPCClient`, `NetworkClient` - all mockable for unit tests
- **Adapters folder**: Pure adapters (`PTYCommandRunner`, `ProcessRPCTransport`) are excluded from code coverage since they only wrap system APIs
- **Parsing logic**: Kept as static/internal methods for direct testing without mocks

### Adding a New AI Provider

1. Create a new provider class implementing `AIProvider` in `Sources/Domain/Provider/`
2. Create probe in `Sources/Infrastructure/CLI/` implementing `UsageProbe`
3. Register provider in `ClaudeBarApp.init()`
4. Add parsing tests in `Tests/InfrastructureTests/CLI/`

## Dependencies

- **Sparkle**: Auto-update framework for macOS
- **Mockable**: Protocol mocking for tests via Swift macros
