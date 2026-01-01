# Swift 6.2 @Observable Patterns

## @Observable vs ObservableObject

Swift 6.2 introduces `@Observable` macro replacing `ObservableObject`:

```swift
// Swift 6.2 - Use this
@Observable
final class AppState {
    var providers: [any AIProvider] = []
    var isRefreshing: Bool = false
}

// Old pattern - Don't use
class AppState: ObservableObject {
    @Published var providers: [any AIProvider] = []
    @Published var isRefreshing: Bool = false
}
```

## No ViewModel Layer

Views consume domain models directly:

```swift
// Direct domain model consumption
struct ProviderSectionView: View {
    let snapshot: UsageSnapshot  // Domain model

    var body: some View {
        VStack {
            Text(snapshot.overallStatus.displayName)
            ForEach(snapshot.quotas, id: \.quotaType) { quota in
                QuotaCardView(quota: quota)
            }
        }
    }
}
```

## @State with @Observable

Use `@State` to own `@Observable` objects in views:

```swift
@main
struct ClaudeBarApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appState: appState)
        }
    }
}
```

## Sendable Conformance

`@Observable` classes need `@unchecked Sendable` for actor isolation:

```swift
@Observable
public final class ClaudeProvider: AIProvider, @unchecked Sendable {
    public let id: String = "claude"
    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
}
```

## Computed Properties

Use computed properties for derived state:

```swift
@Observable
final class AppState {
    var providers: [any AIProvider] = []

    // Derived from providers - no @Published needed
    var overallStatus: QuotaStatus {
        providers.compactMap(\.snapshot?.overallStatus).max() ?? .healthy
    }

    var isRefreshing: Bool {
        providers.contains { $0.isSyncing }
    }
}
```

## Environment with @Observable

Pass `@Observable` objects through environment when needed:

```swift
struct MenuContentView: View {
    let appState: AppState

    var body: some View {
        ProviderListView()
            .environment(appState)
    }
}

struct ProviderListView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ForEach(appState.providers, id: \.id) { provider in
            ProviderRow(provider: provider)
        }
    }
}
```