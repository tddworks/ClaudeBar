import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import Diagnostics

/// *SHARE MY RANK* — over the popover: the image as it will be posted, its
/// shape and name, and Copy image · Save… · Share…. Nothing is uploaded; the
/// image goes to the clipboard, a file or the Mac's share menu.
struct RankShareOverlay: View {
    let card: RankCard
    let monitor: QuotaMonitor
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var shape: RankCard.Shape = .square
    @State private var masksName = AppSettings.shared.hideLeaderboardName
    @State private var copied = false

    private var image: RankCardImage {
        RankCardImage(card: card, shape: shape, name: leaderboardName(card.username, hidden: masksName),
                      providerName: { leaderboardProviderName($0, in: monitor) }, theme: theme, colorScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 12) {
                HStack {
                    Text("Share my rank")
                        .font(theme.font(size: 15, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                preview

                option("Shape") {
                    Picker("Shape", selection: $shape) {
                        Text("Square").tag(RankCard.Shape.square)
                        Text("Wide").tag(RankCard.Shape.wide)
                    }
                }
                option("Name") {
                    Picker("Name", selection: $masksName) {
                        Text(leaderboardName(card.username, hidden: false)).tag(false)
                        Text(leaderboardName(card.username, hidden: true)).tag(true)
                    }
                }

                actions

                Text("An image of what's on your card. Nothing is uploaded; the board's address is printed on it.")
                    .font(theme.font(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(theme.cardGradient)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
            .padding(12)
        }
    }

    /// The image, scaled to fit the sheet: what you see is what gets copied.
    private var preview: some View {
        let size = RankCardImage.points(shape)
        let fit = min(1, 300 / size.width, 300 / size.height)
        return image
            .scaleEffect(fit)
            .frame(width: size.width * fit, height: size.height * fit)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.glassBackground))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the image")
    }

    private func option<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label).font(theme.font(size: 12, weight: .semibold)).foregroundStyle(theme.textPrimary)
            Spacer()
            control().pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            actionButton(copied ? "Copied" : "Copy image", systemImage: copied ? "checkmark" : "doc.on.doc", primary: true) { copy() }
            actionButton("Save…", systemImage: "square.and.arrow.down", primary: false) { save() }
            if let png = image.png(), let rendered = NSImage(data: png) {
                ShareLink(item: Image(nsImage: rendered), preview: SharePreview("My ClaudeBar rank", image: Image(nsImage: rendered))) {
                    actionLabel("Share…", systemImage: "square.and.arrow.up", primary: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, systemImage: systemImage, primary: primary) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, systemImage: String, primary: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(theme.font(size: 12, weight: .bold))
            .lineLimit(1)
            .foregroundStyle(primary ? theme.textOnStatus : theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                    .fill(primary ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.glassBackground))
                    .overlay(RoundedRectangle(cornerRadius: theme.pillCornerRadius).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
    }

    // MARK: Copy, save

    private func copy() {
        guard let png = image.png() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        copied = true
        AppLog.ui.info("Copied the rank card image")
    }

    private func save() {
        guard let png = image.png() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "claudebar-rank-\(card.view.period.rawValue).png"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
        } catch {
            AppLog.ui.error("Couldn't save the rank card image: \(error.localizedDescription)")
        }
    }
}
