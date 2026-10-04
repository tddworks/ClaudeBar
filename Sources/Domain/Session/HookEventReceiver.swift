import Quotas
import DataSources
import Providers
import Foundation
import Mockable

/// Protocol for receiving hook events from Claude Code.
/// Infrastructure layer implements this (e.g., HookHTTPServer).
/// Domain layer consumes events through this abstraction.
@Mockable
public protocol HookEventReceiver: Sendable {
    /// Starts receiving events and returns a stream of session events
    func start() async throws -> AsyncStream<SessionEvent>

    /// Stops receiving events
    func stop() async
}
