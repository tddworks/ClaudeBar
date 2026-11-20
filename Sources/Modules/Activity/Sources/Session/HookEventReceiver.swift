import Quotas
import DataSources
import Providers
import Foundation
import Mockable

/// Where Claude Code's hook events arrive: `Activity.makeHookReceiver()` hands
/// out this machine's (the local hook server).
@Mockable
public protocol HookEventReceiver: Sendable {
    /// Starts receiving events and returns a stream of session events
    func start() async throws -> AsyncStream<SessionEvent>

    /// Stops receiving events
    func stop()
}
