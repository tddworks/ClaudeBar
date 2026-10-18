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

    /// Status considering burn rate setting
    private var effectiveStatus: QuotaStatus {
        quota.status(under: settings.statusPolicy)
    }

    /// Display color for dollar-based quotas based on dollar thresholds.
    private var dollarDisplayColor: Color {
        guard let amount = quota.dollarRemaining else { return effectiveStatus.displayColor }
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
                    .foregroundStyle(effectiveDisplayMode == .pace ? quota.pace.displayColor : effectiveStatus.displayColor)
            }

            QuotaCardBar(quota: quota)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}
