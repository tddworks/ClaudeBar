import SwiftUI
import Kit

extension ProfileLink.Platform {
    /// The brand mark in the asset catalog (Simple Icons 16.34.0, CC0), a template image.
    var markImage: String {
        switch self {
        case .x: "LinkX"
        case .instagram: "LinkInstagram"
        case .github: "LinkGitHub"
        }
    }
}

/// A member's profile link on the board: the bare brand mark, which opens
/// the profile. Says plainly that it isn't verified.
struct ProfileLinkIcon: View {
    let link: ProfileLink
    let username: String

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {

        let _ = KitObservation.track()
        Link(destination: URL(string: link.url)!) {
            Image(link.platform.markImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundStyle(isHovering ? theme.textPrimary : theme.textTertiary)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(link.platform.prefix)\(link.handle) · linked by @\(username) · not verified")
        .accessibilityLabel("@\(username) on \(link.platform.name), not verified")
    }
}

/// Choosing a platform and typing a handle, with the platform's own rule
/// checked as you type. `link` is the handle as a valid link, or nil.
struct ProfileLinkField: View {
    @Binding var platform: ProfileLink.Platform?
    @Binding var handle: String
    /// Offer "None" first, as the join form does.
    var offersNone = false

    @Environment(\.appTheme) private var theme

    var link: ProfileLink? { platform.flatMap { ProfileLink.typed(handle, on: $0) } }

    var body: some View {

        let _ = KitObservation.track()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if offersNone {
                    chip(nil, title: "None", image: nil)
                }
                ForEach(ProfileLink.Platform.allCases, id: \.self) { option in
                    chip(option, title: option.name, image: option.markImage)
                }
            }
            if let platform {
                HStack(spacing: 2) {
                    Text(platform.prefix)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                    TextField("", text: $handle, prompt: Text("handle").foregroundStyle(theme.textTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                        .autocorrectionDisabled()
                        .accessibilityLabel("\(platform.name) handle")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.glassBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)))
                Text(hint)
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(hintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hint: String {
        guard let platform else { return "" }
        if handle.trimmingCharacters(in: .whitespaces).isEmpty { return "\(platform.rule). Your handle only, not a link." }
        guard let link else { return "That isn't a \(platform.name) handle: \(platform.rule)." }
        return "Links to \(link.platform.prefix)\(link.handle). Anyone can type any handle, so it's shown as not verified."
    }

    private var hintColor: Color {
        guard platform != nil, !handle.trimmingCharacters(in: .whitespaces).isEmpty else { return theme.textTertiary }
        return link == nil ? theme.statusCritical : theme.textSecondary
    }

    private func chip(_ option: ProfileLink.Platform?, title: String, image: String?) -> some View {
        let isOn = platform == option
        return Button { platform = option } label: {
            HStack(spacing: 5) {
                if let image {
                    Image(image).renderingMode(.template).resizable().scaledToFit().frame(width: 10, height: 10)
                }
                Text(title).font(theme.font(size: 11, weight: .bold))
            }
            .foregroundStyle(isOn ? AnyShapeStyle(theme.cardGradient) : AnyShapeStyle(theme.textSecondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isOn ? theme.glassBorder : Color.clear)
                .overlay(Capsule().stroke(isOn ? Color.clear : theme.glassBorder.opacity(0.35), lineWidth: 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
