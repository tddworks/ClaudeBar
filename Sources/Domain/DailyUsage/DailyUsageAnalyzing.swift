import Foundation
import Mockable

/// Protocol for analyzing daily usage from Claude Code session logs.
@Mockable
public protocol DailyUsageAnalyzing: Sendable {
    /// Analyze usage for today and the previous day, producing a comparison report.
    func analyzeToday() async throws -> DailyUsageReport
}
