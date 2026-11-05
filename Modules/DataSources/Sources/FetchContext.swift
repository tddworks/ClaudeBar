import Foundation

/// Ambient quality-of-service for the CLIs a fetch starts, propagated via a task
/// local so the background monitoring loop can run CLI spawns (e.g. `claude
/// /usage` driven through a pseudo-terminal) at a low priority without threading
/// a parameter through every fetch API.
///
/// The background loop binds `.utility` around its refreshes (issue #204); any
/// CLI `Process` created within that scope reads this value and inherits it. On
/// Apple Silicon a lowered `Process.qualityOfService` keeps the spawned process
/// tree on efficiency cores and throttled, cutting the idle heat that #204
/// reported. Interactive refreshes leave it at `.default`, so user-driven work
/// stays responsive.
///
/// Task-local values set before a `withTaskGroup` are inherited by its child
/// tasks, so binding it once around `refresh(...)` covers the per-provider
/// refreshes the monitor fans out.
public enum FetchContext {
    @TaskLocal public static var qualityOfService: QualityOfService = .default

    /// Seconds a CLI a fetch starts may take to start, on top of its timeout.
    ///
    /// A timeout stops a CLI that stalled; one that is still loading from a
    /// cold disk hasn't. In a WSL distro, WSL hands the page cache back to
    /// Windows once the distro idles, so a read every ten minutes starts
    /// CLIs of a few hundred MiB from the disk, and they can take longer to
    /// show or answer anything than their timeouts allow (#685 has the
    /// figures). A host that starts its CLIs that way binds this around its
    /// refresh, as the background loop binds `qualityOfService`.
    ///
    /// It is spent only while the CLI hasn't shown that it started: a
    /// terminal's screen still blank, a JSON-RPC CLI's first request not yet
    /// answered. Once it has, the timeout counts from then, so a CLI that
    /// starts at once is given exactly its timeout. A command, which answers
    /// when it ends, gets it on top of its timeout. Nothing binds it on the
    /// Mac, where it stays 0.
    @TaskLocal public static var startAllowance: TimeInterval = 0
}
