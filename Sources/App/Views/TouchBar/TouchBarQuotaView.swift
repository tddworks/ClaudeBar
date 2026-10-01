import AppKit
import CoreGraphics
import Domain
import Infrastructure

// MARK: - Data Models

public struct TouchBarProviderGauge: Equatable, Sendable {
    public let providerId: String
    public let name: String
    /// The number drawn on the gauge. It is whatever the menu bar shows for the
    /// same quota: percent remaining, percent used, or the pace figure, per the
    /// display mode. Do not derive a status from it; use `status`.
    public let percentUsed: Double
    public let resetText: String?
    /// Health of the quota, computed from real usage (pace-aware when enabled).
    public let status: QuotaStatus
    public let hasQuota: Bool

    /// Colour tier for the number and bar.
    public enum Tone: Equatable, Sendable {
        /// No quota data yet; drawn dimmed with no bar.
        case none
        case healthy
        case warning
        /// Critical or depleted; drawn red with a "!" after the number.
        case alarm
    }

    /// Which colour the gauge draws in. Follows `status`, never the displayed
    /// number: in Remaining mode a 93% gauge is healthy and an 18% gauge is an alarm.
    public var tone: Tone {
        guard hasQuota else { return .none }
        switch status {
        case .healthy: return .healthy
        case .warning: return .warning
        case .critical, .depleted: return .alarm
        }
    }

    /// True when the gauge should draw the "!" alarm marker.
    public var isAlarm: Bool { tone == .alarm }

    public init(
        providerId: String,
        name: String,
        percentUsed: Double,
        resetText: String?,
        status: QuotaStatus,
        hasQuota: Bool = true
    ) {
        self.providerId = providerId
        self.name = name
        self.percentUsed = percentUsed
        self.resetText = resetText
        self.status = status
        self.hasQuota = hasQuota
    }
}

// MARK: - TouchBarQuotaView

/// Lightweight, battery-efficient Touch Bar view displaying live AI provider usage gauges.
/// Features centered positioning, color-coded progress bars, and direct tap-to-open interaction.
@MainActor
public final class TouchBarQuotaView: NSView {
    public static let sceneW: CGFloat = 600.0
    public static let sceneH: CGFloat = 30.0

    // MARK: - Properties

    public var gauges: [TouchBarProviderGauge] = [] {
        didSet {
            if gauges != oldValue {
                cachedIcons = gauges.map { loadProviderIcon(for: $0.providerId) }
                needsDisplay = true
            }
        }
    }

    public var sessionActive: Bool = false {
        didSet {
            if sessionActive != oldValue {
                needsDisplay = true
            }
        }
    }

    private var cachedIcons: [NSImage?] = []
    private var isRefreshing: Bool = false

    // MARK: - Layout Metrics

    private let cellGap: CGFloat = 16.0

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.sceneW, height: Self.sceneH))
        self.allowedTouchTypes = [.direct]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool { false }
    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Refresh Feedback

    public func triggerRefreshPulse() {
        isRefreshing = true
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isRefreshing = false
            self?.needsDisplay = true
        }
    }

    // MARK: - Touch Interaction

    public override func touchesBegan(with event: NSEvent) {
        guard let _ = event.touches(matching: .any, in: self).first else { return }
        // Tapping anywhere on the Touch Bar quota view opens ClaudeBar
        if let url = URL(string: "claudebar://open") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()

        guard !gauges.isEmpty else { return }

        let n = CGFloat(gauges.count)
        // Adaptive cell width: distribute available width evenly, minimum 80pt per cell.
        // Recompute totalWidth from the clamped cellW to ensure centering is correct.
        let availableW: CGFloat = min(580.0, bounds.width - 20.0)
        let cellW = max(80.0, (availableW - (n - 1) * cellGap) / n)
        let totalWidth = n * cellW + (n - 1) * cellGap

        // Smart label visibility: suppress elements that won't fit at small sizes
        let showResetText = cellW >= 120.0
        let showName = cellW >= 100.0

        // Center the gauges horizontally; never start so far left that cells bleed off-screen
        let startX = max(4.0, (bounds.width - totalWidth) / 2.0)

        for (i, gauge) in gauges.enumerated() {
            let cx = startX + CGFloat(i) * (cellW + cellGap)
            let icon = (i < cachedIcons.count) ? cachedIcons[i] : nil

            // Draw vertical separator between multiple cells
            if i > 0 {
                let sepX = cx - cellGap / 2.0
                NSColor(white: 1.0, alpha: 0.20).set()
                NSRect(x: sepX, y: 4.0, width: 1.0, height: 22.0).fill()
            }

            drawGaugeCell(gauge, icon: icon, x: cx, width: cellW,
                          showName: showName, showResetText: showResetText)
        }
    }

    private func drawGaugeCell(
        _ gauge: TouchBarProviderGauge,
        icon: NSImage?,
        x: CGFloat,
        width: CGFloat,
        showName: Bool = true,
        showResetText: Bool = true
    ) {
        let textY: CGFloat = 15.0
        let barY: CGFloat  = 3.0
        let barH: CGFloat  = 7.0

        let pct = Int(gauge.percentUsed)
        let alarm = gauge.isAlarm

        // Colour follows the quota's status, not the displayed number: that
        // number is percent remaining in Remaining and Pace modes, so
        // thresholding it painted 93% remaining red and 18% remaining blue.
        let ink: NSColor
        switch gauge.tone {
        case .none:
            ink = NSColor(white: 1.0, alpha: 0.60)
        case .alarm:
            ink = NSColor(srgbRed: 0.902, green: 0.208, blue: 0.180, alpha: 1.0) // Alert Red
        case .warning:
            ink = NSColor(srgbRed: 0.949, green: 0.706, blue: 0.161, alpha: 1.0) // Warning Amber
        case .healthy:
            ink = NSColor(srgbRed: 0.173, green: 0.533, blue: 0.945, alpha: 1.0) // Healthy Blue
        }

        // 1. Draw Provider Icon
        var nameX = x
        let iconRect = NSRect(x: x, y: textY - 1.0, width: 14.0, height: 14.0)
        if let icon {
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(roundedRect: iconRect, xRadius: 3.0, yRadius: 3.0)
            clip.addClip()
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            nameX += 18.0
        } else {
            let symName = ProviderVisualIdentityLookup.symbolIcon(for: gauge.providerId)
            if let sym = NSImage(systemSymbolName: symName, accessibilityDescription: nil) {
                let conf = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
                if let configSym = sym.withSymbolConfiguration(conf) {
                    configSym.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    nameX += 18.0
                }
            }
        }

        // 2. Draw Percentage + Alarm Right-aligned
        var numStr = gauge.hasQuota ? "\(pct)%" : "—"
        if alarm {
            numStr += " !"
        }
        if isRefreshing {
            numStr = "🔄 " + numStr
        }

        let numAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: ink
        ]
        let numW = (numStr as NSString).size(withAttributes: numAttr).width
        let numX = x + width - numW
        (numStr as NSString).draw(at: NSPoint(x: numX, y: textY - 1.0), withAttributes: numAttr)

        // 3. Draw Provider Name & Reset Countdown Note (safely constrained so they never collide with percentage)
        let availableMiddleW = max(0, numX - 6.0 - nameX)
        if showName && availableMiddleW > 10.0 {
            let pStyle = NSMutableParagraphStyle()
            pStyle.lineBreakMode = .byTruncatingTail

            let nameAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.90),
                .paragraphStyle: pStyle
            ]

            let noteAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.55)
            ]

            let fullResetW = (showResetText && gauge.resetText != nil && !gauge.resetText!.isEmpty)
                ? (gauge.resetText! as NSString).size(withAttributes: noteAttr).width : 0

            let naturalNameW = (gauge.name as NSString).size(withAttributes: nameAttr).width

            // Check if both name and reset countdown fit side-by-side with padding
            let canFitReset = showResetText && fullResetW > 0 && (naturalNameW + 5.0 + fullResetW <= availableMiddleW)
            let maxNameW = canFitReset ? (availableMiddleW - fullResetW - 5.0) : availableMiddleW

            let nameRect = NSRect(x: nameX, y: textY, width: maxNameW, height: 14.0)
            (gauge.name as NSString).draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttr)

            if canFitReset, let reset = gauge.resetText {
                let actualNameW = min(naturalNameW, maxNameW)
                let resetX = nameX + actualNameW + 4.0
                (reset as NSString).draw(at: NSPoint(x: resetX, y: textY + 1.0), withAttributes: noteAttr)
            }
        }

        // 5. Progress Bar Track (100% reference)
        let trackRect = NSRect(x: x, y: barY, width: width, height: barH)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 2.0, yRadius: 2.0)
        NSColor(white: 1.0, alpha: 0.30).set()
        trackPath.fill()

        // 6. Filled Bar
        let fillW = gauge.hasQuota ? max(0, min(width, width * CGFloat(pct) / 100.0)) : 0
        if fillW > 0 {
            let fillRect = NSRect(x: x, y: barY, width: fillW, height: barH)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2.0, yRadius: 2.0)
            ink.set()
            fillPath.fill()
        }
    }

    private func loadProviderIcon(for providerId: String) -> NSImage? {
        let assetName = ProviderVisualIdentityLookup.iconAssetName(for: providerId)
        guard let source = NSImage(named: assetName), source.size.width > 0, source.size.height > 0 else {
            return nil
        }
        let size = NSSize(width: 14, height: 14)
        let scale = min(size.width / source.size.width, size.height / source.size.height)
        let fitted = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let icon = NSImage(size: size, flipped: false) { bounds in
            let rect = NSRect(x: (bounds.width - fitted.width) / 2,
                              y: (bounds.height - fitted.height) / 2,
                              width: fitted.width, height: fitted.height)
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        icon.isTemplate = false
        return icon
    }
}
