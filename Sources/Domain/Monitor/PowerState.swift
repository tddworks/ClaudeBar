import Quotas
import DataSources
import Providers
import Foundation

/// A sleep/wake transition the background monitoring loop reacts to.
public enum PowerEvent: Sendable {
    /// The system or display is going to sleep — the loop pauses.
    case willSleep
    /// The system or display woke — the loop resumes and refreshes immediately.
    case didWake
}

/// Supplies the energy-relevant power state the background monitoring loop uses
/// to avoid burning power while the user is away (issue #204): it pauses polling
/// while the display/system is asleep, refreshes immediately on wake, and
/// stretches the cadence while on battery.
///
/// Injected as an *optional* into `QuotaMonitor`. A `nil` provider disables all
/// energy-awareness, preserving the plain timed loop — which keeps tests that
/// don't care about power simple and is why the designated init defaults it to
/// `nil`. The app wires a real `SystemPowerStateProvider` via the convenience
/// init.
public protocol PowerStateProvider: Sendable {
    /// Whether the display (or the whole system) is currently asleep. While this
    /// is `true` the loop pauses — no refresh, no probe subprocess spawn.
    var isDisplayAsleep: Bool { get }

    /// Whether the machine is currently running on battery power. While `true`
    /// the loop stretches its cadence to reduce drain.
    var isOnBattery: Bool { get }

    /// A stream of sleep/wake transitions, used to wake the paused loop the
    /// instant the display/system comes back so the menu-bar number refreshes
    /// promptly. Implementations MUST update `isDisplayAsleep` to reflect the new
    /// state before (or as) they emit the corresponding event, so a loop that
    /// re-checks `isDisplayAsleep` after each event sees a consistent value.
    func events() -> AsyncStream<PowerEvent>
}
