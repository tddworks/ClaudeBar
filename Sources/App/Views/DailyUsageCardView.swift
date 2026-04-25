import SwiftUI
import Domain

/// Displays a single daily usage metric (cost, tokens, or working time)
/// matching the existing WrappedStatCard glassmorphism style.
struct DailyUsageCardView: View {
    let metric: DailyUsageMetric
    let report: DailyUsageReport
    let delay: Double

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false
    @State private var animateProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row with icon and label
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: metric.iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(metric.color)

                    Text(metric.label.uppercased())
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)
                }

                Spacer(minLength: 4)
            }

            // Large value display
            HStack(alignment: .firstTextBaseline) {
                Text(primaryValue)
                    .font(.system(size: 24, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text(metric.unitLabel)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.progressTrack)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [metric.color.opacity(0.8), metric.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: animateProgress ? geo.size.width * progress : 0)
                        .animation(.spring().delay(delay + 0.2), value: animateProgress)
                }
            }
            .frame(height: 5)

            // Delta comparison line
            if let deltaText = formattedDelta {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 7))

                    Text(deltaText)
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                }
                .foregroundColor(deltaColor)
                .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            animateProgress = true
        }
    }

    // MARK: - Computed Properties

    private var primaryValue: String {
        switch metric {
        case .cost: return report.today.formattedCost
        case .tokens: return report.today.formattedTokens
        case .workingTime: return report.today.formattedWorkingTime
        }
    }

    private var progress: Double {
        switch metric {
        case .cost: return min(1, max(0, report.costProgress))
        case .tokens: return min(1, max(0, report.tokenProgress))
        case .workingTime: return min(1, max(0, report.timeProgress))
        }
    }

    private var formattedDelta: String? {
        guard !report.previous.isEmpty else { return nil }
        let date = report.previous.formattedDate
        switch metric {
        case .cost:
            let delta = report.formattedCostDelta
            if let pct = report.costChangePercent {
                return "Vs \(date) \(delta) (\(String(format: "%.1f", abs(pct)))%)"
            }
            return "Vs \(date) \(delta)"
        case .tokens:
            let delta = report.formattedTokenDelta
            if let pct = report.tokenChangePercent {
                return "Vs \(date) \(delta) (\(String(format: "%.1f", abs(pct)))%)"
            }
            return "Vs \(date) \(delta)"
        case .workingTime:
            let delta = report.formattedTimeDelta
            if let pct = report.timeChangePercent {
                return "Vs \(date) \(delta) (\(String(format: "%.1f", abs(pct)))%)"
            }
            return "Vs \(date) \(delta)"
        }
    }

    private var deltaColor: Color {
        switch metric {
        case .cost:
            return report.costDelta <= 0 ? .green : .orange
        case .tokens:
            return report.tokenDelta <= 0 ? .green : .orange
        case .workingTime:
            return theme.textTertiary
        }
    }
}

// MARK: - Metric Type

enum DailyUsageMetric {
    case cost
    case tokens
    case workingTime

    var label: String {
        switch self {
        case .cost: return "Cost Usage"
        case .tokens: return "Token Usage"
        case .workingTime: return "Working Time"
        }
    }

    var iconName: String {
        switch self {
        case .cost: return "dollarsign.circle.fill"
        case .tokens: return "number.circle.fill"
        case .workingTime: return "clock.fill"
        }
    }

    var unitLabel: String {
        switch self {
        case .cost: return "Spent"
        case .tokens: return "Tokens"
        case .workingTime: return "Duration"
        }
    }

    var color: Color {
        switch self {
        case .cost: return .yellow
        case .tokens: return .green
        case .workingTime: return .purple
        }
    }
}
