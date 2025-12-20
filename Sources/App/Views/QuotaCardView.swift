import SwiftUI
import Domain

/// A card view displaying a single quota metric.
/// Directly uses the rich domain model - no ViewModel needed.
struct QuotaCardView: View {
    let quota: UsageQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label
            Text(quota.quotaType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Percentage
            Text("\(Int(quota.percentRemaining))%")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 4)

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * quota.percentRemaining / 100, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }

    private var statusColor: Color {
        switch quota.status {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        case .depleted: .red
        }
    }
}
