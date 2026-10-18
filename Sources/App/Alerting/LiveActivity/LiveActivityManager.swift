import Foundation
import Domain
import Infrastructure

/// Placeholder for ActivityKit Live Activity integration.
///
/// ActivityKit types (`ActivityAttributes`, `Activity`) are currently marked as
/// explicitly unavailable on macOS — even in macOS 26. When Apple adds macOS
/// support for Live Activities, this manager can be activated to show session
/// status as a system-level Live Activity.
///
/// In the meantime, session tracking is handled by `SessionIndicatorView`
/// in the menu bar popover, which works on all macOS versions.
///
/// To activate when ActivityKit becomes available on macOS:
/// 1. Create `Sources/HookActivityWidget/` with ActivityAttributes + Widget view
/// 2. Add widget extension target to Project.swift
/// 3. Uncomment the ActivityKit code below
public final class LiveActivityManager: @unchecked Sendable {
    public init() {}

    /// Starts tracking a session. Currently a no-op on macOS.
    public func startActivity(for session: ClaudeSession) {
        AppLog.hooks.debug("Live Activity not available on macOS — using menu popover instead")
    }

    /// Updates tracking for a session. Currently a no-op on macOS.
    public func updateActivity(for session: ClaudeSession) {
        // No-op until ActivityKit is available on macOS
    }

    /// Ends tracking for a session. Currently a no-op on macOS.
    public func endActivity() {
        // No-op until ActivityKit is available on macOS
    }
}
