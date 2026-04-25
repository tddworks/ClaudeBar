import SwiftUI
import Domain

/// Displays a single extension metric card with value, unit, progress bar, and optional delta.
/// Follows the same glassmorphism style as DailyUsageCardView.
struct ExtensionMetricCardView: View {
    let metric: ExtensionMetric
    let delay: Double

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false
    @State private var animateProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row with icon and label
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 5) {
                    if let iconName = metric.icon {
                        Image(systemName: iconName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(accentColor)
                    }

                    Text(metric.label.uppercased())
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)
                }

                Spacer(minLength: 4)
            }

            // Large value display
            HStack(alignment: .firstTextBaseline) {
                Text(metric.value)
                    .font(.system(size: 24, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer()

                Text(metric.unit)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // Progress bar (if progress provided)
            if let progress = metric.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressTrack)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(
                                colors: [accentColor.opacity(0.8), accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: animateProgress ? geo.size.width * min(1, max(0, progress)) : 0)
                            .animation(.spring().delay(delay + 0.2), value: animateProgress)
                    }
                }
                .frame(height: 5)
            }

            // Delta comparison line
            if let delta = metric.delta {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 7))

                    Text(deltaText(delta))
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                }
                .foregroundColor(theme.textTertiary)
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

    // MARK: - Private

    private var accentColor: Color {
        if let hex = metric.color {
            return Color(hex: hex) ?? theme.accentPrimary
        }
        return theme.accentPrimary
    }

    private func deltaText(_ delta: MetricDelta) -> String {
        if let pct = delta.percent {
            return "Vs \(delta.vs) \(delta.value) (\(String(format: "%.1f", abs(pct)))%)"
        }
        return "Vs \(delta.vs) \(delta.value)"
    }
}

// MARK: - Color from Hex

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6,
              let int = UInt64(hex, radix: 16) else {
            return nil
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
