import ClaudeBarKit
import Foundation
import Observation

/// The UI's one change signal (MODULAR_DESIGN §5): Kotlin moves `ClaudeBarCore.changes`
/// whenever anything a view shows changes; this republishes it through Observation. Every
/// face property that reads changing Kotlin state calls `track()` first, so SwiftUI re-renders
/// whatever read it.
@Observable
public final class KitObservation: @unchecked Sendable {
    public static let shared = KitObservation()

    public private(set) var revision: Int64 = 0

    @ObservationIgnored private var following: Task<Void, Never>?

    /// Registers the reading view as an observer of the kit.
    public static func track() { _ = shared.revision }

    /// Follows the kit's changes on the main actor; a second call replaces the first.
    @MainActor
    public func follow(_ kit: ClaudeBarCore) {
        following?.cancel()
        following = Task { @MainActor [weak self] in
            for await value in kit.changes {
                self?.revision = value.int64Value
            }
        }
    }
}

/// The kit this app runs — built once, on first use. Starting it builds every context; nothing
/// listens or refreshes until the app turns that on.
public enum Kit {
    public static let shared: ClaudeBarCore = ClaudeBarCore.start(
        definitions: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/definitions").path,
        home: NSHomeDirectory()
    )
}

extension ClaudeBarCore: @retroactive @unchecked Sendable {}
