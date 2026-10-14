import SwiftUI
import Domain

// The devices' surfaces (design §2a, slice 15), drawn from
// design-concept/leaderboard/devices.html. The rules are the membership's:
// these only show what it answers and tell it what the person chose.

/// A day as the Devices list writes it: "Oct 10".
private func deviceDay(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day())
}

/// A `yyyy-MM-dd` day, as `DailyTokens.day` writes it, back to a date in this Mac's calendar.
private func deviceDay(fromDay day: String) -> Date? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

/// A failure in the person's words: the domain's own text.
@MainActor
func leaderboardMessage(_ error: any Error) -> String {
    (error as? LeaderboardError)?.errorDescription ?? error.localizedDescription
}

// MARK: - Settings → Leaderboard → Devices

/// *DEVICES* — each Mac or PC of the member, as `/me` last listed them: in
/// use oldest first, then removed ones. *Remove…* offers what the membership
/// offers for that device; a removed one offers *Delete its days…*. In this
/// Mac's own first week it sees only itself, and says when the week ends.
struct LeaderboardDevicesCard: View {
    let leaderboard: AppLeaderboard

    @Environment(\.appTheme) private var theme
    @State private var removing: Device?
    @State private var deletingDaysOf: Device?
    @State private var isAdding = false
    @State private var message: (text: String, isError: Bool)?
    @State private var isWorking = false

    private var membership: LeaderboardMembership { leaderboard.membership }
    private var me: Device? { membership.thisDevice }
    private var myFirstWeekEnds: Date? { me.flatMap { membership.firstWeekEnds(for: $0) } }

    /// In use oldest first, then removed ones, most recently removed first.
    private var listed: [Device] {
        let inUse = membership.devices.filter { !$0.isRemoved }.sorted { $0.addedAt < $1.addedAt }
        let removed = membership.devices.filter(\.isRemoved).sorted { ($0.removedAt ?? .distantPast) > ($1.removedAt ?? .distantPast) }
        return inUse + removed
    }

    var body: some View {
        SettingsCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Devices")
                        .font(theme.font(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Each Mac or PC on \(membership.username?.description ?? "your membership") signs with its own key. Up to five in use.")
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if myFirstWeekEnds == nil {
                    SettingsActionButton(title: "Add a device", iconName: "plus", style: .secondary) {
                        isAdding.toggle()
                        message = nil
                    }
                    .disabled(isWorking)
                }
            }
            .padding(.bottom, 12)

            if listed.isEmpty {
                Text("Reading your devices…")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            ForEach(Array(listed.enumerated()), id: \.element.publicKey) { index, device in
                if index > 0 { SettingsRowDivider() }
                row(device)
            }
            if let ends = myFirstWeekEnds {
                Text("This Mac's first week ends \(deviceDay(ends)). Until then it sees only itself, and can't add or remove devices, rename or leave: a device added by mistake can't take over the member.")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            if isAdding {
                SettingsRowDivider()
                LeaderboardAddDeviceView(membership: membership) { added in
                    isAdding = false
                    message = ("\(added.label) was added. It waits a week before it can add or remove devices.", false)
                }
            }
            if let message {
                Text(message.text)
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(message.isError ? theme.statusCritical : theme.statusHealthy)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .task { _ = try? await membership.summary(period: .sevenDays) }
        .confirmationDialog(removing.map(removeTitle) ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { device in
            ForEach(membership.removals(of: device), id: \.self) { removal in
                Button(removalTitle(removal, of: device), role: .destructive) { remove(device, removal) }
            }
        } message: { device in
            Text(removeMessage(device))
        }
        .confirmationDialog(deletingDaysOf.map { "Delete \($0.label)'s days?" } ?? "",
                            isPresented: Binding(get: { deletingDaysOf != nil }, set: { if !$0 { deletingDaysOf = nil } }),
                            presenting: deletingDaysOf) { device in
            Button("Delete its days", role: .destructive) {
                run("\(device.label)'s days were deleted.") { try await membership.deleteDays(of: device) }
            }
        } message: { _ in
            Text("Every day it sent is deleted from the board. Use this when it counted days twice, after a reinstall or a copy.")
        }
    }

    private func row(_ device: Device) -> some View {
        let isMe = device.publicKey == me?.publicKey
        let firstWeek = membership.firstWeekEnds(for: device)
        return HStack(spacing: 10) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(device.isRemoved ? theme.textTertiary : theme.textPrimary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.label.value)
                        .font(theme.font(size: 13, weight: .semibold))
                        .foregroundStyle(device.isRemoved ? theme.textTertiary : theme.textPrimary)
                    if isMe { chip("THIS MAC", fill: theme.accentPrimary, text: theme.textOnStatus) }
                    if firstWeek != nil, !isMe { chip("FIRST WEEK", fill: theme.statusWarning.opacity(0.25), text: theme.textPrimary) }
                    if device.isRemoved { chip("REMOVED", fill: theme.glassBackground, text: theme.textTertiary) }
                }
                Text(detail(device, firstWeek: firstWeek, isMe: isMe))
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if device.isRemoved {
                SettingsActionButton(title: "Delete its days…", iconName: "trash", style: .secondary) { deletingDaysOf = device }
                    .disabled(isWorking || myFirstWeekEnds != nil)
            } else if !membership.removals(of: device).isEmpty, myFirstWeekEnds == nil || isMe {
                SettingsActionButton(title: "Remove…", iconName: "minus.circle", style: .secondary) { removing = device }
                    .disabled(isWorking)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ text: String, fill: Color, text color: Color) -> some View {
        Text(text)
            .font(theme.font(size: 8, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }

    private func detail(_ device: Device, firstWeek: Date?, isMe: Bool) -> String {
        if let removedAt = device.removedAt {
            let by = device.removedBy.map { " by \($0.label)" } ?? ""
            return "Removed \(deviceDay(removedAt))\(by) · its days still count"
        }
        let added = "Added \(deviceDay(device.addedAt))"
        guard let firstWeek, !isMe else { return added }
        return "\(added) · can add or remove devices from \(deviceDay(firstWeek))"
    }

    private func removeTitle(_ device: Device) -> String {
        device.publicKey == me?.publicKey ? "Remove this Mac from \(membership.username?.description ?? "the member")?" : "Remove \(device.label)?"
    }

    private func removeMessage(_ device: Device) -> String {
        if device.publicKey == me?.publicKey {
            return "Its key stops working and this Mac forgets the membership. The days it sent stay; your other devices go on."
        }
        if membership.removals(of: device).contains(.deletingItsDays) {
            return "Its key stops working at once. It was added \(device.addedAt.formatted(.relative(presentation: .named))): if it isn't yours, delete the days it sent too."
        }
        return "Its key stops working at once. The days it sent stay and count; you can delete them afterwards."
    }

    private func removalTitle(_ removal: Removal, of device: Device) -> String {
        switch removal {
        case .keepingItsDays: device.publicKey == me?.publicKey ? "Remove this Mac" : "Remove"
        case .deletingItsDays: "Remove and delete its days"
        }
    }

    private func remove(_ device: Device, _ removal: Removal) {
        let done = device.publicKey == me?.publicKey
            ? "This Mac was removed. Its days stay with the member."
            : removal == .deletingItsDays ? "\(device.label) was removed and its days deleted." : "\(device.label) was removed."
        run(done) { try await membership.remove(device, removal) }
    }

    private func run(_ done: String, _ work: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await work()
                message = (done, false)
            } catch {
                message = (leaderboardMessage(error), true)
            }
        }
    }
}

// MARK: - Settings → Add a device

/// *Add a device*, on a Mac the member has: type the code the new Mac shows,
/// see what approving it would add, then **Approve**. Never approved blind.
struct LeaderboardAddDeviceView: View {
    let membership: LeaderboardMembership
    let onAdded: (Device) -> Void

    @Environment(\.appTheme) private var theme
    @State private var typed = ""
    @State private var pending: (code: DeviceCode, device: PendingDevice)?
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a device")
                .font(theme.font(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            if let pending {
                Text("Add “\(pending.device.label)”?")
                    .font(theme.font(size: 12, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("It asked \(pending.device.requestedAt.formatted(.relative(presentation: .named))) with code \(pending.code.description).")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.textSecondary)
                Text("Only approve a code you can see on your own Mac. Someone who reads you their code wants to send their days as you.")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    SettingsActionButton(title: "Cancel", iconName: "xmark", style: .secondary) { self.pending = nil; error = nil }
                    SettingsActionButton(title: "Approve", iconName: "checkmark", style: .prominent, isBusy: isWorking) {
                        approve(pending.code)
                    }
                    .disabled(isWorking)
                }
            } else {
                Text("On the new Mac, open the Leaderboard tab and choose Already a member? Add this Mac. Type the code it shows.")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    SettingsTextField(placeholder: "WDJB-MJHT", text: $typed)
                        .frame(width: 140)
                        .accessibilityLabel("Code shown on the new Mac")
                    SettingsActionButton(title: "Look up", iconName: "magnifyingglass", style: .prominent, isBusy: isWorking) {
                        lookUp()
                    }
                    .disabled(DeviceCode(typed) == nil || isWorking)
                }
            }
            if let error {
                Text(error)
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func lookUp() {
        guard let code = DeviceCode(typed) else { return }
        work {
            pending = (code, try await membership.pendingDevice(code: code))
        }
    }

    private func approve(_ code: DeviceCode) {
        work {
            try await membership.approve(code: code)
            let added = membership.devices.last { $0.label == pending?.device.label } ?? membership.devices.last
            pending = nil
            typed = ""
            if let added { onAdded(added) }
        }
    }

    private func work(_ body: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        error = nil
        Task { @MainActor in
            defer { isWorking = false }
            do { try await body() } catch { self.error = leaderboardMessage(error) }
        }
    }
}

// MARK: - A key copied from another Mac

/// *THIS MAC HAS A COPY OF A KEY* — at the top of the tab and of Settings
/// while the key's machine hash isn't this Mac's. Nothing uploads until it is
/// answered; the card says plainly what keeping the key means.
struct LeaderboardCopiedKeyView: View {
    let leaderboard: AppLeaderboard

    @Environment(\.appTheme) private var theme

    private var membership: LeaderboardMembership { leaderboard.membership }
    /// The Mac the key came from, as the member's devices name it.
    private var otherMac: String { membership.thisDevice?.label.value ?? "another Mac" }
    private var member: String { membership.username?.description ?? "your membership" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let code = membership.ownDeviceRequest?.code, leaderboard.isBecomingOwnDevice {
                firstWeek(code)
            } else {
                question
            }
            if let failure = leaderboard.copyFailure {
                Text(failure.errorDescription ?? "")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("THIS MAC HAS A COPY OF A KEY")
            Text("This Mac has a copy of \(otherMac)'s leaderboard key")
                .font(theme.font(size: 14, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Migration Assistant or a restore brought it here. Two Macs on one key overwrite each other's days, so this Mac isn't uploading until you choose.")
                .font(theme.font(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            choice(title: "Both Macs stay in use",
                   text: "This Mac gets its own key, added as a device of \(member). It uploads from where \(otherMac) left off, and waits a week before it can add or remove devices.",
                   button: "Make this Mac its own device", prominent: true) { leaderboard.becomeOwnDevice() }
            choice(title: "The other Mac is gone, or this is it after a repair",
                   text: "This Mac keeps the key and goes on as \(otherMac). If the other Mac is still in use, the two will overwrite each other's days.",
                   button: "Keep the key here", prominent: false) { leaderboard.keepKeyHere() }
        }
    }

    private func firstWeek(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("MAKE THIS MAC ITS OWN DEVICE")
            Text("Another of your devices approves this one")
                .font(theme.font(size: 14, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text("\(otherMac)'s key was added less than a week ago, so it can't approve. On another device of \(member): Settings → Leaderboard → Devices → Add a device.")
                .font(theme.font(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LeaderboardCodeView(code: code)
            waiting
            Button { leaderboard.keepKeyHere() } label: {
                Text("Keep the key here instead")
                    .font(theme.font(size: 12, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(Capsule().fill(theme.glassBackground))
                    .overlay(Capsule().stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            }
            .buttonStyle(.plain)
        }
    }

    private var waiting: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
            Text("Waiting for approval · the code works for 10 minutes")
                .font(theme.font(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(theme.font(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(theme.textSecondary)
    }

    private func choice(title: String, text: String, button: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(theme.font(size: 12, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text(text)
                .font(theme.font(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                HStack(spacing: 6) {
                    if prominent, leaderboard.isBecomingOwnDevice {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    }
                    Text(button)
                }
                .font(theme.font(size: 11, weight: .bold))
                .foregroundStyle(prominent ? theme.textOnStatus : theme.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(prominent ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.glassBackground)))
                .overlay(Capsule().stroke(prominent ? Color.clear : theme.glassBorder, lineWidth: theme.cardBorderWidth))
            }
            .buttonStyle(.plain)
            .disabled(leaderboard.isBecomingOwnDevice)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(prominent ? theme.accentPrimary.opacity(0.12) : theme.glassBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
    }
}

/// A device's code as a new Mac shows it: `WDJB-MJHT`, large, to read off
/// the screen and type on another Mac.
struct LeaderboardCodeView: View {
    let code: DeviceCode

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(code.description)
            .font(.system(size: 24, weight: .bold, design: .monospaced))
            .tracking(3)
            .foregroundStyle(theme.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.glassBorder, style: StrokeStyle(lineWidth: max(1.5, theme.cardBorderWidth), dash: [6, 4]))
            )
            .accessibilityLabel("Code \(code.value.map(String.init).joined(separator: " "))")
    }
}

// MARK: - Popover: a device was added

/// *NEW DEVICE* — a device added since this one last looked, once each, with
/// *Remove…* beside it: the same choice as Settings.
struct LeaderboardDeviceAddedCard: View {
    let leaderboard: AppLeaderboard
    let device: Device

    @Environment(\.appTheme) private var theme
    @State private var confirming = false
    @State private var error: String?

    private var membership: LeaderboardMembership { leaderboard.membership }

    var body: some View {
        LeaderboardCard {
            HStack(alignment: .top) {
                Text("NEW DEVICE")
                    .font(theme.font(size: 9, weight: .heavy))
                    .foregroundStyle(theme.textOnStatus)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(theme.accentPrimary))
                Spacer(minLength: 0)
                Button { membership.markShown(device) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            Text("\(device.label) was added to \(membership.username?.description ?? "your membership")")
                .font(theme.font(size: 13, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(deviceDay(device.addedAt)). If it isn't yours, remove it: its key stops at once.")
                .font(theme.font(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                pill("Remove…") { confirming = true }
                pill("It's mine") { membership.markShown(device) }
            }
            if let error {
                Text(error)
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Remove \(device.label)?", isPresented: $confirming) {
            ForEach(membership.removals(of: device), id: \.self) { removal in
                Button(removal == .deletingItsDays ? "Remove and delete its days" : "Remove", role: .destructive) {
                    Task { @MainActor in
                        do {
                            try await membership.remove(device, removal)
                            membership.markShown(device)
                        } catch {
                            self.error = leaderboardMessage(error)
                        }
                    }
                }
            }
        } message: {
            Text(membership.removals(of: device).contains(.deletingItsDays)
                 ? "Its key stops working at once. If it isn't yours, delete the days it sent too."
                 : "Its key stops working at once. The days it sent stay and count.")
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.font(size: 11, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(theme.glassBackground))
                .overlay(Capsule().stroke(theme.glassBorder, lineWidth: max(1, theme.cardBorderWidth * 0.6)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Popover: add this Mac to a member

/// *ADD THIS MAC* — the new Mac's side: its code and the wait, then the
/// member it was approved for and "Is that you?", or the code expired.
/// Nothing is kept or uploaded until the person agrees.
struct LeaderboardAddThisMacView: View {
    let leaderboard: AppLeaderboard
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var sharing: Set<String> = []
    @State private var error: String?
    @State private var isWorking = false

    private var membership: LeaderboardMembership { leaderboard.membership }
    private var shareable: [String] { membership.shareableProviders.sorted() }

    var body: some View {
        LeaderboardCard {
            Text("ADD THIS MAC")
                .font(theme.font(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.textSecondary)
            if leaderboard.requestFailure == .codeExpired || leaderboard.request?.stage == .expired {
                expired
            } else if let failure = leaderboard.requestFailure, leaderboard.request == nil {
                failed(failure)
            } else if let request = leaderboard.request, case .approved(let member) = request.stage {
                approved(member)
            } else if let request = leaderboard.request {
                waiting(request)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let error {
                Text(error)
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if sharing.isEmpty { sharing = Set(shareable) } }
    }

    private func waiting(_ request: DeviceRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type this on a Mac that's on the leaderboard")
                .font(theme.font(size: 14, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            LeaderboardCodeView(code: request.code)
            Text("There: Settings → Leaderboard → Devices → Add a device. This Mac is called \(membership.suggestedLabel).")
                .font(theme.font(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
                Text("Waiting for approval · the code works for 10 minutes")
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            wideButton("Cancel", prominent: false) { leaderboard.cancelRequest() }
        }
    }

    private func approved(_ member: Username) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approved for \(member.description)")
                .font(theme.font(size: 14, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text("Is that you? Nothing is kept or uploaded until you say so.")
                .font(theme.font(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("SHARE TOKENS FROM")
                .font(theme.font(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.textSecondary)
            if shareable.isEmpty {
                Text("No provider on this Mac keeps token logs yet. Claude, Codex, Mistral, Oh My Pi and OpenCode do.")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shareable, id: \.self) { id in
                        ProviderPill(providerId: id, providerName: leaderboardProviderName(id, in: monitor),
                                     isSelected: sharing.contains(id), hasData: true) {
                            if sharing.contains(id) { sharing.remove(id) } else { sharing.insert(id) }
                        }
                        .accessibilityAddTraits(sharing.contains(id) ? .isSelected : [])
                    }
                }
                .padding(4)
            }
            wideButton(sharing.isEmpty ? "Pick at least one provider" : "Join as \(member.description)", prominent: true) {
                do {
                    try leaderboard.joinThroughRequest(sharing: sharing)
                } catch {
                    self.error = leaderboardMessage(error)
                }
            }
            .disabled(sharing.isEmpty || isWorking)
            .opacity(sharing.isEmpty ? 0.5 : 1)
            textButton("That's not me · remove this Mac") {
                isWorking = true
                Task { @MainActor in
                    defer { isWorking = false }
                    do { try await leaderboard.declineRequest() } catch { self.error = leaderboardMessage(error) }
                }
            }
        }
    }

    private var expired: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The code expired before it was approved.")
                .font(theme.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.statusCritical)
            wideButton("Get a new code", prominent: true) { Task { await leaderboard.requestToJoin() } }
            textButton("Back to joining") { leaderboard.cancelRequest() }
        }
    }

    private func failed(_ failure: LeaderboardError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(failure.errorDescription ?? "")
                .font(theme.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.statusCritical)
                .fixedSize(horizontal: false, vertical: true)
            wideButton("Try again", prominent: true) { Task { await leaderboard.requestToJoin() } }
            textButton("Back to joining") { leaderboard.cancelRequest() }
        }
    }

    private func wideButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.font(size: 13, weight: .bold))
                .foregroundStyle(prominent ? theme.textOnStatus : theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                    .fill(prominent ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.glassBackground)))
                .overlay(RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                    .stroke(prominent ? Color.clear : theme.glassBorder, lineWidth: theme.cardBorderWidth))
        }
        .buttonStyle(.plain)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.font(size: 11, weight: .semibold))
                .underline()
                .foregroundStyle(theme.textSecondary)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Popover footer lines

/// The footer's warning about refused days, or `nil`: the earliest one, in
/// words, and how many more. Each is sent again with every upload for 30 days.
@MainActor
func leaderboardRefusedLine(_ refused: [RefusedDay], monitor: QuotaMonitor) -> String? {
    guard let first = refused.min(by: { $0.day < $1.day }) else { return nil }
    let more = refused.count > 1 ? " (and \(refused.count - 1) more)" : ""
    let day = deviceDay(fromDay: first.day).map { deviceDay($0) } ?? first.day
    return "\(leaderboardProviderName(first.provider, in: monitor)) on \(day) wasn't counted\(more): \(first.why). Sent again each hour for 30 days."
}
