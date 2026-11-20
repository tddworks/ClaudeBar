import AppKit
import Domain
import Foundation
import IOKit.ps

/// `PowerStateProvider` backed by AppKit sleep/wake notifications and IOKit power
/// sources, so the background monitoring loop can pause while the user is away
/// and slow down on battery (issue #204).
///
/// - Display/system sleep is tracked via `NSWorkspace` notifications; the most
///   important one for #204 is `screensDidSleep`, which fires when the display
///   idles off while the machine keeps running — exactly when the old loop kept
///   spawning `claude /usage` and heating the CPU.
/// - Battery state is read on demand from IOKit's power sources (no AC/battery
///   notification exists, and the read is cheap), so the monitor polls it once
///   per tick.
///
/// Thread-safe (`@unchecked Sendable`): the asleep flag and the set of event
/// continuations are guarded by a lock, and IOKit reads are stateless.
public final class SystemPowerStateProvider: PowerStateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var displayAsleep = false
    private var continuations: [UUID: AsyncStream<PowerEvent>.Continuation] = [:]
    private var observers: [NSObjectProtocol] = []

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.handle(.willSleep)
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.handle(.didWake)
            })
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        lock.lock()
        let pending = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in pending { continuation.finish() }
    }

    public var isDisplayAsleep: Bool {
        lock.lock(); defer { lock.unlock() }
        return displayAsleep
    }

    public var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return false
        }
        return (sourceType as String) == kIOPSBatteryPowerValue
    }

    public func events() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    /// Updates the asleep flag and broadcasts the transition. The flag is updated
    /// before the event is emitted (per the `PowerStateProvider` contract) so a
    /// consumer re-checking `isDisplayAsleep` after an event sees the new state.
    private func handle(_ event: PowerEvent) {
        lock.lock()
        switch event {
        case .willSleep: displayAsleep = true
        case .didWake: displayAsleep = false
        }
        let listeners = Array(continuations.values)
        lock.unlock()
        for continuation in listeners { continuation.yield(event) }
    }
}
