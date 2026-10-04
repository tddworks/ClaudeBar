import Quotas
import Foundation

/// A data source's failure, naming the step that failed — *Couldn't read your
/// key* · *Couldn't connect* · *Couldn't find the numbers* — because each sends
/// the person somewhere different. `reason` is today's `UsageError`, so
/// everything that already reads a `UsageError` keeps reading one.
///
/// Never carries a secret or a response body.
public struct DataSourceError: Error, Sendable, Equatable, LocalizedError {
    public enum Step: String, Sendable, Equatable {
        case lookup
        case fetch
        case mapping
    }

    public let step: Step
    public let reason: UsageError

    public init(_ step: Step, _ reason: UsageError) {
        self.step = step
        self.reason = reason
    }

    public var errorDescription: String? {
        reason.errorDescription
    }

    /// Wraps any error thrown inside a step, keeping a `UsageError` as it is.
    static func wrap(_ error: Error, as step: Step) -> DataSourceError {
        if let error = error as? DataSourceError { return error }
        if let reason = error as? UsageError { return DataSourceError(step, reason) }
        return DataSourceError(step, .executionFailed(error.localizedDescription))
    }
}
