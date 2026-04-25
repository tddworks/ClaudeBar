import SwiftUI
import WebKit

/// A card that embeds a WKWebView to display custom URL content for a provider.
/// Styled to match existing quota cards (same border, corner radius, background).
struct CustomWebCardView: View {
    let url: URL
    let delay: Double

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with link icon and domain
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(theme.accentPrimary)

                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 9, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textSecondary)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Spacer()

                // Open in browser button
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .foregroundColor(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // Embedded web view — scaled to fit card width
            WebViewRepresentable(url: url)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
    }
}

// MARK: - WKWebView Wrapper

struct WebViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        // Scale page content to fit the small card
        webView.pageZoom = 0.4
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial load and same-page navigation, open external links in browser
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
