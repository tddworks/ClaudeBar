import SwiftUI
import Domain
import Matrix

/// The notch's contents: two lanes flanking the physical cutout when collapsed,
/// a panel underneath when expanded.
///
/// The middle of the collapsed bar is deliberately kept clear — on a display
/// with a real notch that space is the cutout, and anything drawn there is
/// invisible.
struct NotchRootView: View {
    @Bindable var state: NotchViewState

    /// Resolved here rather than injected, so the notch follows a theme change
    /// without the window having to be torn down and rebuilt. Reading the
    /// observable setting inside `body` is what registers that tracking.
    private var theme: any AppThemeProvider {
        ThemeRegistry.shared.resolveTheme(
            for: AppSettings.shared.themeMode,
            systemColorScheme: .dark,
            statusColors: AppSettings.shared.statusColorPolicy
        )
    }

    private var topCornerRadius: CGFloat { state.isExpanded ? 12 : 6 }
    private var bottomCornerRadius: CGFloat { state.isExpanded ? 22 : 14 }
    private var barHeight: CGFloat { state.metrics.closedSize.height }

    var body: some View {
        // Nothing to report draws nothing at all — not even the closed shape.
        // See NotchWindowController.update(content:).
        if state.activity == nil {
            Color.clear.frame(width: 0, height: 0)
        } else {
            notch
        }
    }

    private var notch: some View {
        VStack(spacing: 0) {
            collapsedBar
            if state.isExpanded {
                NotchPanelView(
                    content: state.content,
                    refresh: state.refresh,
                    snooze: state.snooze
                )
                .environment(\.appTheme, theme)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(width: 600)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .fixedSize()
        // Room for the flares, so the notch's frame is the notch's silhouette.
        // Everything downstream then lines up on one rect: the shape fills it
        // and onGeometryChange measures it.
        .padding(.horizontal, topCornerRadius)
        .background {
            NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
                .fill(.black)
        }
        // The notch is physical glass; it is black in every theme. Only the
        // panel hanging below it follows the app's theme.
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            state.contentSize = size
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.isExpanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: state.activity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, state.activity == nil ? 0 : 12)
            // Reserve the cutout itself — on a display with a real notch this
            // space is the hole, and anything drawn in it is invisible.
            Color.clear
                .frame(width: state.metrics.closedSize.width)
            trailing
                .padding(.trailing, state.activity == nil ? 0 : 12)
        }
        .frame(height: barHeight)
    }

    @ViewBuilder
    private var leading: some View {
        switch state.activity {
        case .working(let session):
            NotchLane {
                PhaseDot(color: .green, pulsing: true)
                NotchLabel(session.repoName)
            }
        case .agentsWorking(let session):
            NotchLane {
                DotmSquare3(size: 15, color: .blue)
                NotchLabel(session.repoName)
            }
        case .awaitingInput:
            NotchLane {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
                NotchLabel("Needs you")
            }
        case .finished(let session):
            NotchLane {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                NotchLabel(session.repoName)
            }
        case .quotaThreshold(let quota), .quotaGlance(let quota):
            NotchLane {
                NotchLabel(quota.compactTitle ?? quota.quotaType.shortLabel)
                Text("\(Int(quota.percentRemaining))%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(quotaColor(quota))
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state.activity {
        case .working(let session):
            NotchLane {
                ElapsedLabel(session: session).fixedSize()
                headlineGauge
            }
        case .agentsWorking(let session):
            NotchLane {
                NotchMeta("\(session.activeSubagentCount) agents")
                ElapsedLabel(session: session)
                headlineGauge
            }
        case .awaitingInput(let session):
            NotchMeta(session.pendingPrompt ?? "Waiting for you")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
        case .finished(let session):
            NotchLane {
                if session.completedTaskCount > 0 {
                    NotchMeta("\(session.completedTaskCount) tasks")
                }
                NotchMeta(session.durationDescription)
                headlineGauge
            }
        case .quotaThreshold(let quota), .quotaGlance(let quota):
            NotchLane {
                if state.content.isRefreshing {
                    DotmSquare3(size: 12, color: quotaColor(quota))
                } else {
                    QuotaBar(percentRemaining: quota.percentRemaining, color: quotaColor(quota))
                }
                if let reset = quota.compactResetTime {
                    NotchMeta(reset).fixedSize()
                }
            }
        case nil:
            EmptyView()
        }
    }

    /// The quota reading, carried alongside whatever else the notch is saying.
    /// A session running is not a reason to stop showing how much is left.
    @ViewBuilder
    private var headlineGauge: some View {
        if let quota = state.content.headline {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: 11)

                NotchMeta("\(quota.compactTitle ?? quota.quotaType.shortLabel) \(Int(quota.percentRemaining))%")
                    .fixedSize()

                if state.content.isRefreshing {
                    DotmSquare3(size: 11, color: quotaColor(quota))
                } else {
                    QuotaBar(percentRemaining: quota.percentRemaining, color: quotaColor(quota))
                }
            }
        }
    }

    private func quotaColor(_ quota: UsageQuota) -> Color {
        theme.statusColor(for: QuotaStatus.from(percentRemaining: quota.percentRemaining))
    }
}

// MARK: - Pieces

private struct NotchLane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 7) { content }
    }
}

private struct NotchLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
    }
}

private struct NotchMeta: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
    }
}

/// Ticks once a second so the elapsed time stays true without the rest of the
/// app having to repaint.
private struct ElapsedLabel: View {
    let session: ClaudeSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            NotchMeta(session.durationDescription)
        }
    }
}

private struct PhaseDot: View {
    let color: Color
    var pulsing: Bool = false

    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .scaleEffect(isBreathing ? 1.0 : 0.6)
                    .opacity(isBreathing ? 0.1 : 0.4)
            }
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

private struct QuotaBar: View {
    let percentRemaining: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.16))
            .frame(width: 52, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(width: 52 * max(0, min(1, percentRemaining / 100)))
            }
    }
}
