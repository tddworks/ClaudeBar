import SwiftUI
import Domain
import Infrastructure

/// Notify! pane: publishing quota state to a linked iPhone.
///
/// Two cards, in the order the feature has to be set up. The link comes first
/// because nothing else in the pane means anything without it, and the second
/// card is disabled until one is saved: every control in it either sends
/// something to Notify! or decides what gets sent, and there is nowhere to send
/// it yet.
///
/// A saved ID narrows the second card, one control at a time. Notify! hands out
/// ids for groups, Macs and browsers as well as for phones, and the three
/// surfaces answer to that separately: a Mac or a browser keeps a widget
/// perfectly well and cannot show a Live Activity, while a group is a fan-out
/// target with no screen of its own and gets none of them. So each switch is
/// disabled by its own rule and carries its own sentence, and a Mac user reads
/// that most of the feature works for them rather than none of it. Saving such
/// an ID is still allowed. It is a real ID, the user may be about to replace it,
/// and refusing a save the gateway itself would accept reads as a bug.
/// Verify Device stays live for every kind, because it checks the credentials
/// rather than the surfaces and is the one useful thing to press here.
struct NotifyPane: View {
    let monitor: QuotaMonitor

    /// The app's publisher. Every write to the linked device goes through it,
    /// including this pane's own button: it serialises publishes, and two
    /// publishers racing to start a tile is exactly how a phone ends up with
    /// two of them.
    let driver: NotifyPublishDriver

    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    /// The two credentials, held only while the user is entering them. Once
    /// saved the token lives in the Keychain and never comes back into the
    /// field: the user already has it, so echoing a secret buys nothing.
    @State private var deviceIdField: String = ""
    @State private var tokenField: String = ""
    @State private var showToken: Bool = false

    /// What is on file, read in `onAppear` and again after every change made
    /// here. Asking the repository from `body` instead would reach into the
    /// Keychain on every re-render.
    @State private var linkedDeviceId: String = ""
    @State private var hasDeviceToken: Bool = false
    @State private var tokenIsInKeychain: Bool = false

    @State private var isVerifying: Bool = false
    @State private var verifyOutcome: NotifyActionOutcome?

    @State private var isPublishing: Bool = false
    @State private var publishOutcome: NotifyActionOutcome?

    var body: some View {
        SettingsPane(
            title: "Notify!",
            subtitle: "Push your quota to an iPhone as a Lock Screen Live Activity, a Lock Screen widget and a Home Screen widget, using the Notify! app."
        ) {
            linkCard
            publishCard
        }
        .onAppear {
            refreshLinkState()
        }
    }

    // MARK: - The link

    private var linkCard: some View {
        SettingsCard {
            SettingsFieldLabel(text: "DEVICE ID")
                .padding(.bottom, 6)

            TextField("", text: $deviceIdField, prompt: prompt("ABC12345"))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(fieldBackground)
                .onChange(of: deviceIdField) { _, _ in
                    absorbPastedPair()
                }

            HStack {
                SettingsFieldLabel(text: "TOKEN")

                Spacer()

                if hasDeviceToken {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text("Configured")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundStyle(theme.statusHealthy)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 6)

            HStack(spacing: 6) {
                // Masked by default, and only this field. The token is the
                // secret half; the device id is the half that travels in every
                // webhook URL the user has ever pasted anywhere, so hiding it
                // would protect nothing and cost them the ability to check it.
                Group {
                    if showToken {
                        TextField("", text: $tokenField, prompt: prompt("your device token"))
                    } else {
                        SecureField("", text: $tokenField, prompt: prompt("your device token"))
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(fieldBackground)

                Button {
                    showToken.toggle()
                } label: {
                    Image(systemName: showToken ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(theme.glassBackground)
                        )
                }
                .buttonStyle(.plain)
            }

            if hasDeviceToken, !tokenIsInKeychain {
                // The badge above says the token is on file. It would be easy to
                // read that as "in the Keychain", so where it actually went is
                // said out loud rather than left to be assumed.
                statusText(
                    "Stored in ClaudeBar's app credentials rather than the Keychain, which refuses builds that are not signed with a developer identity.",
                    tone: theme.textTertiary
                )
                .padding(.top, 6)
            }

            linkStatusLine
                .padding(.top, 8)

            HStack(spacing: 8) {
                NotifyPaneButton(
                    title: "Save Link",
                    iconName: "link"
                ) {
                    saveLink()
                }
                .disabled(pendingLink == nil)
                .opacity(pendingLink == nil ? 0.6 : 1)

                NotifyPaneButton(
                    title: isVerifying ? "Checking..." : "Verify Device",
                    iconName: "checkmark.shield.fill",
                    isProminent: false,
                    isBusy: isVerifying
                ) {
                    Task {
                        await verifyDevice()
                    }
                }
                .disabled(!isLinked || isVerifying)
                .opacity(isLinked ? 1 : 0.6)

                Spacer()

                if isLinked {
                    removeLinkButton
                }
            }
            .padding(.top, 12)

            if let verifyOutcome {
                NotifyOutcomeLine(outcome: verifyOutcome)
                    .padding(.top, 8)
            }

            Text("The check asks Notify! about the device, and Notify! allows only a few of those a minute. So it runs when you press it, never on its own.")
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(theme.textTertiary)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.glassBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.glassBorder, lineWidth: 1)
            )
    }

    /// Splits a whole notification URL across both fields when one is pasted
    /// into the id field.
    ///
    /// The pane asks for the two values separately, which is what the Notify!
    /// app shows and what the gateway actually wants. But the app also offers a
    /// ready made notification URL with both values in it, and someone who
    /// copies that will paste it into the first field they see. Rejecting it
    /// with "that is not a device ID" would be technically true and useless,
    /// when the id and the token are both right there in the text.
    ///
    /// Only runs on text that cannot be a bare id, so a normal id typed by hand
    /// is never touched, and the rewrite it performs leaves nothing splittable
    /// behind, so the change it triggers on this field ends there.
    private func absorbPastedPair() {
        let text = deviceIdField
        guard text.contains(where: { $0 == "/" || $0 == "?" || $0 == ":" || $0 == "," || $0.isWhitespace }) else {
            return
        }

        if let link = NotifyDeviceLink(pastedText: text) {
            deviceIdField = link.deviceId
            tokenField = link.token
            return
        }

        // A URL with no token on it still names the device, and the gateway's
        // own /link response hands back exactly that shape. Take the half that
        // is there and leave the token field to say what is missing.
        if let deviceId = NotifyDeviceLink.deviceId(inPastedText: text) {
            deviceIdField = deviceId
        }
    }

    /// What the field currently amounts to. The parsed device id is shown back
    /// before anything is saved, because a mistyped link and a working one look
    /// identical in a masked field, and the namespace it belongs to is named
    /// alongside it: a group link and an iPhone link are both perfectly valid
    /// and do very different things, so the moment to say which one this is
    /// comes before the save, not after a tile silently never appears.
    @ViewBuilder
    private var linkStatusLine: some View {
        if let pendingLink {
            VStack(alignment: .leading, spacing: 6) {
                if let reason = pendingLink.kind.liveActivityUnsupportedReason
                    ?? pendingLink.kind.widgetUnsupportedReason {
                    unsupportedReasonLine(reason, isProminent: true)
                }

                statusText(
                    "Reads as \(pendingLink.deviceId) (\(pendingLink.kind.displayName)). Save it to store the pair.",
                    tone: theme.textSecondary
                )
            }
        } else if !deviceIdField.isEmpty || !tokenField.isEmpty {
            statusText(incompleteEntryMessage, tone: theme.statusWarning)
        } else if isLinked {
            VStack(alignment: .leading, spacing: 6) {
                if let reason = savedLiveActivityReason ?? savedWidgetReason {
                    unsupportedReasonLine(reason, isProminent: true)
                }

                statusText("Linked to \(linkedDeviceId) (\(linkedKind.displayName)).", tone: theme.textSecondary)
            }
        } else {
            statusText(
                "Both values are in the Notify! app on your phone.",
                tone: theme.textSecondary
            )
        }
    }

    /// Says which half is missing or wrong, rather than that the pair is not
    /// valid. Two fields can only be incomplete in a small number of ways, and
    /// naming the one that applies is the difference between a hint and a
    /// verdict.
    private var incompleteEntryMessage: String {
        let deviceId = deviceIdField.trimmingCharacters(in: .whitespacesAndNewlines)

        if deviceId.isEmpty {
            return "Add the device ID as well."
        }
        if !NotifyDeviceLink.isValidDeviceId(deviceId) {
            return "That is not a Notify! device ID. An ID is 8 to 32 letters and digits, with no spaces."
        }
        return "Add the token as well. It sits beside the device ID in the Notify! app."
    }

    private func statusText(_ message: String, tone: Color) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The one sentence that says why a link cannot carry a Lock Screen
    /// surface, and what to paste instead.
    ///
    /// Shown twice at most, and never the same words twice. The link card
    /// carries the full sentence, including what to paste instead, because that
    /// is where the problem is and where the user is looking while pasting. The
    /// publish card carries only the short form, because a dimmed switch whose
    /// explanation sits in another card reads as a bug in ClaudeBar, while four
    /// copies of a long sentence reads as a wall of text.
    private func unsupportedReasonLine(_ reason: String, isProminent: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: isProminent ? 10 : 9))

            Text(reason)
                .font(
                    .system(
                        size: isProminent ? 11 : 10,
                        weight: isProminent ? .semibold : .medium,
                        design: theme.fontDesign
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.statusWarning)
    }

    private var removeLinkButton: some View {
        Button {
            removeLink()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 9))
                Text("Remove")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
            }
            .foregroundStyle(theme.statusCritical)
        }
        .buttonStyle(.plain)
    }

    // MARK: - What gets published

    private var publishCard: some View {
        SettingsCard {
            // One banner for the whole card rather than a copy of the same
            // sentence under every control it disables. The controls stay dimmed
            // and unusable, which is what says WHICH things are unavailable; the
            // banner says why, once, where the eye lands first.
            SettingsRow(
                title: "Publish to Notify!",
                subtitle: "Sends your quota percentages to Notify!, a third-party service, which delivers them to your phone."
            ) {
                SettingsSwitch(isOn: $settings.notifyEnabled)
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(
                    title: "Live Activity",
                    subtitle: "A tile on the Lock Screen. Needs the Notify! app to have been opened at least once on the phone, because until then Notify! holds nothing it can start a tile with."
                ) {
                    SettingsSwitch(isOn: $settings.notifyLiveActivityEnabled)
                }
                .disabled(!linkSupportsLiveActivity)
                .opacity(linkSupportsLiveActivity ? 1 : 0.6)

                // Back beside the control now that the surfaces are gated
                // separately. A Mac closes off this one switch and nothing else,
                // so there is exactly one sentence on screen rather than four.
                if let savedLiveActivityReason {
                    unsupportedReasonLine(savedLiveActivityReason)
                }

            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(
                    title: "Lock Screen widget",
                    subtitle: "A gauge showing one quota, small enough for the Lock Screen. iOS decides when a widget redraws, roughly every fifteen minutes."
                ) {
                    SettingsSwitch(isOn: $settings.notifyWidgetEnabled)
                }
                .disabled(!linkSupportsWidget)
                .opacity(linkSupportsWidget ? 1 : 0.6)

                if let savedWidgetReason {
                    unsupportedReasonLine(savedWidgetReason)
                }

            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(
                    title: "Home Screen widget",
                    subtitle: "The same content as the Live Activity, except that it stays put instead of appearing when something happens and vanishing after. Needs a recent Notify! app: turn it on under Settings then Home Screen Widgets in Notify!, then place it with iOS's own widget picker."
                ) {
                    SettingsSwitch(isOn: $settings.notifyScreenWidgetEnabled)
                }
                .disabled(!linkSupportsScreenWidget)
                .opacity(linkSupportsScreenWidget ? 1 : 0.6)

                if let savedScreenWidgetReason {
                    unsupportedReasonLine(savedScreenWidgetReason)
                }

            }

            // The gauge shows one window at a time, so which one only matters
            // while the widget is actually being published. It stays visible
            // when the link cannot draw a gauge, because the switch above it
            // may well have been turned on by an earlier iPhone link: hiding
            // the picker would leave the setting in place with nothing on
            // screen saying it is no longer reachable.
            if settings.notifyWidgetEnabled {
                SettingsRowDivider()

                VStack(alignment: .leading, spacing: 8) {
                    gaugeControls
                        .disabled(!linkSupportsWidget)
                        .opacity(linkSupportsWidget ? 1 : 0.6)

                }
            }

            SettingsRowDivider()

            publishNowRow
        }
        .disabled(!isLinked)
        .opacity(isLinked ? 1 : 0.6)
    }

    private var gaugeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsFieldLabel(text: "GAUGE PROVIDER")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        MenuBarChoiceButton(
                            iconName: "wand.and.stars",
                            label: "Automatic",
                            isSelected: isGaugeAutomatic
                        ) {
                            settings.notifyGaugeProviderId = ""
                            settings.notifyGaugeQuotaKey = ""
                        }

                        ForEach(gaugeProviders, id: \.id) { provider in
                            MenuBarProviderChoiceButton(
                                providerId: provider.id,
                                providerName: provider.name,
                                isSelected: settings.notifyGaugeProviderId == provider.id
                            ) {
                                settings.notifyGaugeProviderId = provider.id
                                selectFirstGaugeQuota()
                            }
                        }
                    }
                }
                .disabled(gaugeProviders.isEmpty)
            }

            if isGaugeAutomatic {
                Text("Automatic shows whichever quota needs attention most.")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsFieldLabel(text: "GAUGE QUOTA")

                    if gaugeQuotaOptions.isEmpty {
                        Text("No quota data")
                            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                                    .fill(theme.glassBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                                            .stroke(theme.glassBorder, lineWidth: 1)
                                    )
                            )
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(gaugeQuotaOptions, id: \.quotaType.quotaKey) { quota in
                                    MenuBarQuotaChoiceButton(
                                        title: quota.menuBarTitle ?? quota.quotaType.displayName,
                                        isSelected: settings.notifyGaugeQuotaKey == quota.quotaType.quotaKey
                                    ) {
                                        settings.notifyGaugeQuotaKey = quota.quotaType.quotaKey
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var publishNowRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                title: "Send an Update Now",
                subtitle: "Publishes the current quota straight away, so you can watch it land instead of waiting for the next refresh."
            ) {
                NotifyPaneButton(
                    title: isPublishing ? "Sending..." : "Send Now",
                    iconName: "paperplane.fill",
                    isBusy: isPublishing
                ) {
                    Task {
                        await publishNow()
                    }
                }
                .disabled(isPublishing || !settings.notifyEnabled || !linkSupportsAnySurface)
                .opacity(settings.notifyEnabled && linkSupportsAnySurface ? 1 : 0.6)
            }


            if let publishOutcome {
                NotifyOutcomeLine(outcome: publishOutcome)
            }
        }
    }

    // MARK: - Reading the state

    /// Whether both halves of a usable link are on file.
    private var isLinked: Bool {
        hasDeviceToken && !linkedDeviceId.isEmpty
    }

    /// The link the field currently spells out, or nil when it is empty or does
    /// not parse.
    private var pendingLink: NotifyDeviceLink? {
        NotifyDeviceLink(deviceId: deviceIdField, token: tokenField)
    }

    /// Which namespace the saved id belongs to, and so which surfaces the link
    /// can carry. Read from the id alone, which is the half of the link kept on
    /// hand here: the token stays in the Keychain, and it is the namespace that
    /// decides the surfaces anyway.
    ///
    /// With nothing saved the empty id lands on `.unrecognized`, which claims
    /// every surface. That is the right answer for this pane rather than a
    /// quirk to guard against: the publish card is already disabled wholesale
    /// on `isLinked`, and dimming its rows a second time would blame the user's
    /// phone for a link they have not pasted yet.
    private var linkedKind: NotifyDeviceKind {
        NotifyDeviceKind.kind(ofDeviceId: linkedDeviceId)
    }

    /// Whether the saved link can hold a tile.
    ///
    /// The surfaces are asked about separately even though the same three
    /// prefixes fail all of them today, because they fail for different reasons:
    /// the gateway refuses a Live Activity outright, while a widget is accepted
    /// and then drawn by nothing. Those are separate rules, and they could stop
    /// agreeing.
    private var linkSupportsLiveActivity: Bool {
        linkedKind.supportsLiveActivity
    }

    /// Whether a gauge written to the saved link would ever be drawn.
    private var linkSupportsWidget: Bool {
        linkedKind.supportsWidget
    }

    /// Whether a Home Screen tile written to the saved link would ever be drawn.
    /// The same answer as the Lock Screen widget today, asked separately because
    /// it is a separate route with its own rules.
    private var linkSupportsScreenWidget: Bool {
        linkedKind.supportsScreenWidget
    }

    /// Whether a publish has anywhere to land. It writes a tile, a gauge and a
    /// Home Screen tile and nothing else, so a link that can hold none of them
    /// leaves the button nothing to send.
    private var linkSupportsAnySurface: Bool {
        linkedKind.supportsAnySurface
    }

    /// The sentence to repeat beside anything the saved link cannot do, or nil
    /// when it can do everything. Asked only once a link is on file, so an
    /// empty pane stays quiet.
    /// The reason to show beside the Live Activity switch, and the one to show
    /// while the user is still typing, since for every kind that has a Live
    /// Activity problem that is the first thing they need to know.
    private var savedLiveActivityReason: String? {
        isLinked ? linkedKind.liveActivityUnsupportedReason : nil
    }

    /// Only a group has one of these. Every real device can keep a widget.
    private var savedWidgetReason: String? {
        isLinked ? linkedKind.widgetUnsupportedReason : nil
    }

    /// The same, for the Home Screen widget, which a group cannot keep either.
    private var savedScreenWidgetReason: String? {
        isLinked ? linkedKind.screenWidgetUnsupportedReason : nil
    }

    /// The publish card's own short form: what is closed off, not the full
    /// remedy, which the link card above already spells out.


    private var gaugeProviders: [any AIProvider] {
        monitor.enabledProviders
    }

    private var isGaugeAutomatic: Bool {
        settings.notifyGaugeProviderId.isEmpty
    }

    private var selectedGaugeProvider: (any AIProvider)? {
        gaugeProviders.first { $0.id == settings.notifyGaugeProviderId }
    }

    private var gaugeQuotaOptions: [UsageQuota] {
        selectedGaugeProvider?.snapshot?.quotas ?? []
    }

    // MARK: - Actions

    private func refreshLinkState() {
        linkedDeviceId = settings.notify.notifyDeviceId()
        hasDeviceToken = settings.notify.hasNotifyDeviceToken()
        tokenIsInKeychain = settings.notify.notifyDeviceTokenIsSecure()
    }

    private func saveLink() {
        guard let link = pendingLink else { return }

        // The repository decides whether the previous device's handles survive
        // this, because it is the only part of that rule that can be tested: a
        // link naming the same phone keeps them, a different phone does not.
        settings.notify.saveNotifyDeviceLink(link)

        refreshLinkState()

        // Saving a secret can fail, and it fails silently: the credential store
        // has no way to report a refusal, and the Keychain does refuse an
        // ad-hoc signed build. Pressing Save and watching nothing at all happen
        // is the worst version of that, so the pane asks whether the token is
        // actually on file before it congratulates anyone.
        guard hasDeviceToken else {
            verifyOutcome = NotifyActionOutcome(
                message: "Could not store the token on this Mac. Check Console for a Keychain error from ClaudeBar, and try again.",
                isFailure: true
            )
            return
        }

        deviceIdField = ""
        tokenField = ""
        showToken = false
        verifyOutcome = nil
        publishOutcome = nil

        // Never the id and never the token. The gateway answers a wrong token
        // and an unknown device with the same 403, so naming either would tell
        // a log reader nothing they could act on.
        AppLog.credentials.info("Saved a Notify! device link")

        // Credentials live outside observable state, so the publish driver has
        // no way to notice this on its own.
        NotificationCenter.default.post(name: .notifySettingsChanged, object: nil)
    }

    private func removeLink() {
        settings.notify.setNotifyDeviceId("")
        settings.notify.deleteNotifyDeviceToken()

        // The handles name a tile and two widgets belonging to credentials that
        // are now gone. Keeping them would risk writing to a stranger's surface
        // if the gateway ever reuses an id, so a later link starts by creating
        // its own.
        settings.notify.setNotifyActivityId(nil)
        settings.notify.setNotifyWidgetId(nil)
        settings.notify.setNotifyScreenWidgetId(nil)

        deviceIdField = ""
        tokenField = ""
        showToken = false
        verifyOutcome = nil
        publishOutcome = nil
        refreshLinkState()

        AppLog.credentials.info("Removed the Notify! device link")
    }

    private func verifyDevice() async {
        isVerifying = true
        verifyOutcome = nil
        defer { isVerifying = false }

        guard let link = settings.notify.notifyDeviceLink() else {
            verifyOutcome = NotifyActionOutcome(message: "Save a device link first.", isFailure: true)
            return
        }

        do {
            let info = try await NotifyGatewayClient().deviceInfo(link: link)
            verifyOutcome = NotifyActionOutcome(message: info.displayDescription, isFailure: false)
        } catch {
            verifyOutcome = NotifyActionOutcome(message: error.localizedDescription, isFailure: true)
        }
    }

    /// Publishes the current reading on the spot.
    ///
    /// Writes to the gateway directly rather than nudging the publish driver,
    /// because the driver is deliberately governed by `NotifyPublishGate` and
    /// this button exists precisely to skip the waiting. Each surface is sent
    /// and reported separately: a device that cannot do Live Activities at all
    /// still polls its widget happily, and one failure should not read as two.
    /// Publishes right now through the app's driver, and reports what happened.
    ///
    /// The pane deliberately owns none of this. The driver holds the stored tile
    /// and widget handles, the single in-flight publish, and the recovery paths
    /// for a dismissed tile and a refused handle. A second copy here would race
    /// the first over the same two handles.
    private func publishNow() async {
        isPublishing = true
        publishOutcome = nil
        defer { isPublishing = false }

        if let failure = await driver.publishNow() {
            publishOutcome = NotifyActionOutcome(message: failure, isFailure: true)
        } else {
            publishOutcome = NotifyActionOutcome(
                message: "Sent. It can take a moment to appear, and iOS redraws a widget on its own schedule.",
                isFailure: false
            )
        }
    }

    /// Points the gauge at the newly chosen provider's first window, so picking
    /// a provider is one click rather than two. An empty quota key would fall
    /// back to automatic and quietly ignore the provider just chosen.
    private func selectFirstGaugeQuota() {
        guard let first = gaugeQuotaOptions.first else { return }
        settings.notifyGaugeQuotaKey = first.quotaType.quotaKey
    }
}

// MARK: - Pane pieces

/// The outcome of one button press, shown until the next one.
///
/// The message and its tone are carried separately rather than sniffed out of
/// the text: a gateway error message is written by the gateway, and reading a
/// word out of it to decide the color would eventually paint a failure green.
private struct NotifyActionOutcome {
    let message: String
    let isFailure: Bool
}

private struct NotifyOutcomeLine: View {
    let outcome: NotifyActionOutcome

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(outcome.message)
            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(outcome.isFailure ? theme.statusCritical : theme.statusHealthy)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A pane action button in the Settings window's capsule language: filled with
/// the accent gradient when it is the obvious next step, glass when it sits
/// beside one.
private struct NotifyPaneButton: View {
    let title: String
    let iconName: String
    var isProminent: Bool = true
    var isBusy: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
            }
            .foregroundStyle(isProminent ? Color.white : theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
    }

    private var buttonBackground: some View {
        ZStack {
            if isProminent {
                Capsule().fill(theme.accentGradient)
            } else {
                Capsule().fill(theme.glassBackground)
            }

            Capsule().stroke(isProminent ? Color.clear : theme.glassBorder, lineWidth: 1)
        }
    }
}
