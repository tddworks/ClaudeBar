import AppKit
import Observation
import Kit

/// The leaderboard's page state: what the popover shows over the board — the rank being shared,
/// the notice after turning it off, the *Turn off ▾* menu. The membership, uploads and the
/// board are Kotlin's (`ClaudeBarKit.Leaderboard`); views read `membership` and `uploader`.
@MainActor
@Observable
final class Leaderboard {
    @ObservationIgnored let kit: ClaudeBarKit.Leaderboard
    var membership: LeaderboardMembership { kit.membership }
    var uploader: LeaderboardUploader { kit.uploader }
    let boardPage = URL(string: "https://claudebar.tddworks.com/leaderboard/")!
    let globePage = URL(string: "https://claudebar.tddworks.com/leaderboard/#globe-section")!
    /// The rank the member is sharing, while *Share my rank* is open over the popover.
    private(set) var sharing: RankCard?
    /// What the popover says once, after the Leaderboard was turned off there.
    private(set) var offNotice: LeaderboardOffNotice?
    /// *Turn off ▾* is open over the popover.
    private(set) var showsTurnOffMenu = false

    init(_ kit: ClaudeBarKit.Leaderboard) {
        self.kit = kit
    }

    /// Joins, then sends the last thirty days in the background so the first
    /// rank shows without waiting an hour, and the tab switches at once.
    func join(as username: Username, sharing: Set<String>, sharesCountry: Bool = false, link: ProfileLink? = nil) async throws {
        try value(of: await kit.join(username: username, sharing: sharing, sharesCountry: sharesCountry, link: link))
    }

    /// The popover's Refresh: uploads now, whatever tab is open. Nothing
    /// happens when not joined.
    func refresh() async {
        try? await kit.refresh()
    }

    /// Today's days for `providers`, exactly as an upload would send them —
    /// for the join form's preview.
    func preview(sharing providers: Set<String>) async -> [DailyTokens] {
        (try? await kit.preview(providers: providers)) ?? []
    }

    // MARK: On and off

    /// Hides the tab and stops uploads; a member stays a member. From the
    /// popover it says so once, with a way back.
    func turnOff(noting: Bool = true) {
        showsTurnOffMenu = false
        offNotice = noting ? (membership.isJoined ? .paused : .hidden) : nil
        kit.turnOff()
    }

    /// Brings the tab back and catches up at once on the days missed.
    func turnOn() {
        offNotice = nil
        kit.turnOn()
    }

    func dismissOffNotice() {
        offNotice = nil
    }

    func toggleTurnOffMenu() {
        showsTurnOffMenu.toggle()
    }

    func closeTurnOffMenu() {
        showsTurnOffMenu = false
    }

    /// *Share* on *Your rank*: opens *Share my rank* with this card.
    func share(_ card: RankCard) {
        sharing = card
    }

    func stopSharing() {
        sharing = nil
    }

    // MARK: Membership — Kotlin answers with an outcome; a refusal throws its words here.

    func rename(to name: Username) async throws {
        try value(of: await kit.rename(newName: name))
    }

    func setVisible(_ visible: Bool) async throws {
        try value(of: await kit.setVisible(visible: visible))
    }

    func setSharesCountry(_ shares: Bool) async throws {
        try value(of: await kit.setSharesCountry(shares: shares))
    }

    func setLink(_ link: ProfileLink?) async throws {
        try value(of: await kit.setLink(link: link))
    }

    func leave() async throws {
        try value(of: await kit.leave())
    }

    func share(provider: String) throws {
        try value(of: kit.share(provider: provider))
    }

    /// *Export my data* — the file's text.
    func exportMyData() async throws -> String {
        try value(of: await kit.exportMyData()).map { String($0) } ?? ""
    }

    func myStanding(in view: BoardView) async throws -> MemberSummary? {
        try value(of: await kit.myStanding(view: view))
    }

    func board(in view: BoardView) async throws -> [Standing] {
        (try value(of: await kit.board(view: view)) as? [Standing]) ?? []
    }

    func globe() async throws -> GlobeSummary? {
        try value(of: await kit.globe())
    }
}

/// What the popover says after the Leaderboard was turned off in it.
enum LeaderboardOffNotice {
    /// Not joined: only the tab went away.
    case hidden
    /// Joined: uploads stopped too; the membership stays.
    case paused

    var text: String {
        switch self {
        case .hidden: "Leaderboard hidden. Turn it back on in Settings → Leaderboard."
        case .paused: "Leaderboard paused and hidden. Nothing uploads; your name and days stay. Turn it back on in Settings → Leaderboard."
        }
    }
}

/// Your username as the popover prints it: `@itshan`, or `@i•••` when hidden.
func leaderboardName(_ username: String, hidden: Bool) -> String {
    hidden ? "@\(username.prefix(1))•••" : "@\(username)"
}

/// A two-letter country as people read it, "🇳🇱 Netherlands", or `🌍 ••` when
/// *hide my globe country* is on.
func leaderboardCountryLabel(_ code: String, hidden: Bool) -> String {
    hidden ? "🌍 ••" : leaderboardCountryLabel(code)
}

/// A two-letter country as people read it: its flag and its name, "🇳🇱 Netherlands".
func leaderboardCountryLabel(_ code: String) -> String {
    let flag = String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }))
    let name = Locale.current.localizedString(forRegionCode: code) ?? code
    return "\(flag) \(name)"
}
