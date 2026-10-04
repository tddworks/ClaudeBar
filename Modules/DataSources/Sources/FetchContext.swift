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
}
