import SwiftUI
import Domain

/// A card view displaying a single quota metric.
/// Directly uses the rich domain model - no ViewModel needed.
struct QuotaCardView: View {
    let quota: UsageQuota

    @State private var settings = AppSettings.shared

    private var displayMode: UsageDisplayMode {
        settings.usageDisplayMode
    }

    /// Display color for dollar-based quotas based on dollar thresholds.
    private var dollarDisplayColor: Color {
        guard let amount = quota.dollarRemaining else { return quota.status.displayColor }
        let value = NSDecimalNumber(decimal: amount).doubleValue
        if value <= 5 { return .red }
        if value <= 20 { return .orange }
        return .green
    }

    /// Effective display mode: falls back to .used when pace is unknown
    private var effectiveDisplayMode: UsageDisplayMode {
        if displayMode == .pace && quota.pace == .unknown {
            return .used
        }
        return displayMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            Text(quota.quotaType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Value display
            if let dollarText = quota.formattedDollarRemaining {
                Text("\(dollarText) remaining")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(dollarDisplayColor)
            } else {
                Text("\(Int(quota.displayPercent(mode: effectiveDisplayMode)))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(effectiveDisplayMode == .pace ? quota.pace.displayColor : quota.status.displayColor)
            }

            // Progress bar with pace tick
            VStack(spacing: 1) {
                GeometryReader { geometry in
                    let progressPercent = quota.displayProgressPercent(mode: effectiveDisplayMode)
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 4)

                        // Fill (clamp width to 0-100%)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(quota.status.displayColor)
                            .frame(width: geometry.size.width * max(0, min(100, progressPercent)) / 100, height: 4)
                    }
                }
                .frame(height: 4)

                // Expected pace tick mark
                if let expectedPercent = quota.expectedProgressPercent(mode: effectiveDisplayMode) {
                    GeometryReader { geometry in
                        let tickX = geometry.size.width * max(0, min(100, expectedPercent)) / 100
                        Path { path in
                            path.move(to: CGPoint(x: tickX - 3, y: 4))
                            path.addLine(to: CGPoint(x: tickX + 3, y: 4))
                            path.addLine(to: CGPoint(x: tickX, y: 0))
                            path.closeSubpath()
                        }
                        .fill(Color.secondary.opacity(0.6))
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}
