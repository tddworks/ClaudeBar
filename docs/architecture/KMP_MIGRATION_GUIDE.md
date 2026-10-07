# Moving a Swift app to a Kotlin SDK — what we learned

How ClaudeBar moved everything but its UI from Swift to one Kotlin Multiplatform
SDK, `ClaudeBarKit/`, on branch `spike/kmp-shared-domain` (October 2026, 42
commits). This is the playbook to reuse and the traps to avoid. The design it
produced is [MODULAR_DESIGN.md](MODULAR_DESIGN.md); this page is how we got
there.

**The result:** Kotlin 2.4.20 + SKIE 0.10.15, one Gradle module, one
`ClaudeBarKit.xcframework`, a package per context. Swift keeps SwiftUI, AppKit
and page state. 3,017 Kotlin tests (JUnit and the native suite) and 220 Swift
tests. The AWS SDK, SwiftTerm, SweetCookieKit, Subprocess, SQLite.swift and
Mockable are gone.

## 1 · Decide these before writing code

| Decision | What we chose | Why |
|---|---|---|
| Bridge | **SKIE**, not Swift export (alpha) and not KMMBridge | Swift export didn't cover what we needed on macOS yet. KMMBridge publishes binaries, which a single repo doesn't need. SKIE gives Swift enums, `async`, `AsyncSequence` and Swift names. Re-check Swift export with each Kotlin release. |
| Shape of the SDK | **One Gradle module, a package per context**, with package rules enforced by a Konsist `ArchitectureTest` | Kotlin/Native gives each framework its own runtime and copy of every type, so two Kotlin frameworks can't share a `UsageQuota`. |
| Types | **Kotlin types everywhere**, plus a thin Swift *face* | No mirror Swift model to keep in sync. |
| Tests | **JUnit on a `jvm()` target**, plus a small native suite | Fast, and every Swift test had a JUnit home. `jvmMain` stays empty: the JVM is for tests only. |
| State | **Kotlin owns state and concurrency; Swift observes one change signal** | No `@Observable` mirror per aggregate. |

## 2 · The order that worked: bottom-up, one context at a time

Kotlin never calls Swift. So a context can only move once everything below it
has moved. We moved them in this order, keeping the Swift build green after
every commit:

1. **The model** (`quotas`): pure values and their laws. This step proves the
   bridge and the face pattern.
2. **Cross-cutting** (`diagnostics`, `storage`): logging, `settings.json`, the
   Keychain. Swift's own classes become faces over the Kotlin ones, so nothing
   above them changes.
3. **The engine** (`datasources`): the largest step, because it replaced four
   Swift libraries. Port each library behind a port, and prove it against
   recorded output (we diffed 50 captured terminal screens byte for byte) before
   anything depends on it.
4. **The lifecycle** (`providers`), then the **aggregates** (`monitoring`,
   `alerting`, `activity`, `leaderboard`), then **the composition root**
   (`kit`: `ClaudeBarCore.start`).
5. **The switch-over**, one context at a time: make the context public in
   Kotlin, write its face, rewire the App, delete its Swift twin and tests.

Two things in step 5 made the switch-over work:

- **Port the tests before you delete the Swift.** About 800 vendor tests ran on
  the Kotlin engine without a single production fix; that is what made the
  deletion safe. The Swift acceptance specs became JUnit `acceptance/` specs.
- **Expect dependencies to force a bigger cut than planned.** We planned
  "leaderboard and alerts, then providers". But the leaderboard reads the
  monitor's logins and the alerts read its snapshots, and Kotlin can't call the
  Swift monitor. So providers, monitor, alerting, leaderboard and Notify!
  switched as one cut. Check what each context *reads*, not only what it
  imports.

### How the big cut went

1. Write the composition in Kotlin (`SystemKit.start`): every adapter, wired once.
2. Make the API public by following the compiler. Flip a type to `public`
   (keep `internal constructor`), compile, and read the "exposes its internal
   type" errors. For each one, either publish that type or mark the member
   `internal`. A small script did the flipping. Engine internals
   (`Fetch`, `Mapping`, credential lookups, sign-in runners) stayed internal.
3. Delete the Swift targets and replace every `import Domain`/`Providers`/…
   with `import Kit`. Let the Swift compiler list what's left, and fix it in
   waves. It reports one wave of errors per pass, so expect a dozen rebuilds.
4. Move what was page state all along (menu-bar labels, popover sizes, status
   colours, the app's own settings) into the App, not into Kotlin.
5. Smoke-run the app on a throwaway home (`scripts/demo-screenshots.sh` with
   `CFFIXED_USER_HOME`). Check that `status.json` and the log show providers
   refreshing.

## 3 · The bridge rules, and the traps behind each one

| Trap | What happens | Rule |
|---|---|---|
| A Kotlin exception reaches Swift | **The app crashes.** Only exceptions declared with `@Throws` cross the bridge. | **Values cross, exceptions don't.** A command that can fail returns `Outcome<T>` (`Done`/`Refused(reason)`), `RefreshOutcome` or `ConnectionOutcome`. Swift reads them through `value(of:)`, which throws a `KitRefusal`. Watch especially for non-suspend functions that throw (`definition(id:)`, `install()`): they must not be public. |
| A public class implements `List`/`Iterable` | It exports as `unavailable("can't be imported")`. | Expose `val all: List<T>`. Then make the type a `RandomAccessCollection` in the face (`Accounts`, `ResponseFields`). |
| A Swift extension of a generic Kotlin class uses `T` | "cannot access the class's generic parameters at runtime". | Use a free generic function (`value(of:)`), or a non-generic member (`refusalOrNull`). |
| Kotlin default arguments | They don't cross, and SKIE's default-argument interop failed to link. | Add convenience overloads in the face (`refresh(providerId:)`, `BoardView(period:)`). |
| `Int`, `Long`, `Double?`, `Boolean` from `suspend` | They become `Int32`, `Int64`, `KotlinDouble?` and `KotlinBoolean`. | Add face views (`belowPercent: Int`, `leftPercent: Double?`, `canRefresh(_:) -> Bool`) so views count in `Int`. |
| Sealed classes | Swift sees classes, not enums, and `switch` won't work. | Add a `shape` enum in the face for every sealed type a view switches on. Only the face calls `onEnum(of:)`. |
| Companion objects | `Type.companion.of(…)` leaks into views. | Add a static Swift name in the face (`NotifyDeviceLink.pasted(_:)`, `ClaudeBarCore.start(definitions:home:)`). |
| A Kotlin class bound with `$draft.url` or `@Bindable` | It doesn't work: Kotlin classes aren't value types and aren't `@Observable`. | Keep form state in a Swift struct (`ProviderDraftForm`), and build the Kotlin object only when you act on it. Bind other fields with `Binding(get:set:)`. |
| `@Environment(Type.self)` with a Kotlin class | It requires `Observable`. | Add `extension Type: @retroactive Observable {}`. The protocol asks for nothing, because tracking comes from the change signal. |
| `Codable` on a Kotlin type | Not possible. | Encode in Kotlin and hand Swift a `String` (`Leaderboard.exportMyData()`). Use Swift `Stored`/`Reported` structs only where Swift still owns the JSON. |
| Name clashes | A type named like the framework (`ClaudeBarKit`) or like an App type (`Leaderboard`). | Call the core `ClaudeBarCore`. Refer to the Kotlin type by its module name, `ClaudeBarKit.Leaderboard`. |
| Kotlin errors are not Swift `Error`s | `Result<Response, DataSourceError>` and `catch let e as UsageError` don't compile. | Add `extension KotlinThrowable: @retroactive Error {}` and a `localizedDescription` from `message`. |
| Swift `Sendable` | Strict concurrency rejects Kotlin types. | Add `@retroactive @unchecked Sendable` per type in the face. Kotlin values are immutable, and Kotlin/Native objects are thread-safe. |

**The face is one folder** (`Modules/Kit`). If a grep for
`onEnum|KotlinLong|Int32(|.companion` finds anything outside it, a helper is
missing. Keeping it to one folder means moving to Swift export later only
touches that folder.

## 4 · Observation: one change signal, tracked by every body

The first design merged a fixed list of each aggregate's `revision` flows at
start. **It can't work.** Logins, configurations and guest passes are created
while the app runs, so no list made at start can name them all.

What works instead:

- Every aggregate bumps its own `storage.Revision`, which also bumps one
  process-wide counter, `ClaudeBarCore.changes`.
- `KitObservation` (`@Observable`) follows that counter on the main actor.
- **Every SwiftUI `body` and every `ObservationRenderSync` read calls
  `KitObservation.track()`.** A blanket edit did it.

The invalidation is coarse: one change re-renders what's visible. That's fine
for a menu-bar popover.

## 5 · Testing during and after

- **TDD stays the rule.** Every new Kotlin piece got a JUnit test first or
  alongside: `ProviderWorkshop`, `NotifyPublisher`, the `Leaderboard` facade,
  the sign-in command.
- **App tests that need real providers start their own kit** over a temporary
  home (`Tests/AppTests/Support/TestKit.swift`), seeded with a
  `settings.json`, custom definitions and extension manifests. That uses public
  API only, with no test hooks in the SDK.
- **Swift tests of domain behaviour move to JUnit** before the Swift is
  deleted. For each one, check whether JUnit already covers it. Port what isn't
  covered (we found two Swift-only cases this way).
- **Fixture files move with their tests.** The leaderboard's shared
  `vectors.json` lived in a deleted Swift folder, and 11 JUnit tests failed
  until it moved to `src/jvmTest/resources`.

## 6 · Commands we used every round

```bash
./scripts/build-kotlin.sh                        # framework; rerun after any Kotlin edit
(cd ClaudeBarKit && ./gradlew compileKotlinMacosArm64 -q 2>&1 | grep '^e:')   # exposure errors
tuist generate --no-open                         # after adding or deleting Swift files
xcodebuild build-for-testing … -derivedDataPath <scratch>   # a private DerivedData: another
xcodebuild test-without-building …                          #   running ClaudeBar holds the default
(cd ClaudeBarKit && ./gradlew jvmTest macosArm64Test)
```

## 7 · If we did it again

- **Write the bridge rules (§3) down on day one**, before the first public
  type. Most of the switch-over's churn was adapting the App to bridge facts we
  could have known up front.
- **Map who reads whom across contexts** before planning the switch-over, so
  the cuts are honest.
- **Treat page state as page state early.** Menu-bar formatting and popover
  sizes never belonged in the domain. Moving them to the App first would have
  shrunk the Kotlin API.
- **Make non-UI drivers Kotlin from the start.** The Notify! publisher was
  first written as an App driver, then ported. The status export and the
  menu-bar text are still App drivers ([MODULAR_DESIGN §9](MODULAR_DESIGN.md#9--open)).
