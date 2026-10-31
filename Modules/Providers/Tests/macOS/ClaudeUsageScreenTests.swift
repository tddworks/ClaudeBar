#if os(macOS)
import DataSources
import Quotas
import Foundation
import Testing

/// Claude Code's `/usage` screen read by `claude.json`'s `cli` data source:
/// drawn by the terminal emulator (`"screen": "rendered"`), then
/// `claude-usage-screen.js`, with the account from `~/.claude.json`.
///
/// Ported from `ClaudeUsageProbeParsingTests` and `ClaudeAccountInfoResolverTests`;
/// the fixtures are theirs, verbatim.
@Suite
struct ClaudeUsageScreenTests {

    // MARK: - Sample CLI Output

    static let sampleClaudeOutput = """
    Claude Code v1.0.27

    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m

    Current week (all models)
    ██████████░░░░░░░░░░ 35% left
    Resets Jan 15, 3:30pm (America/Los_Angeles)

    Current week (Opus)
    ████████████████████ 80% left
    Resets Jan 15, 3:30pm (America/Los_Angeles)

    Account: user@example.com
    Organization: Acme Corp
    Login method: Claude Max
    """

    static let exhaustedQuotaOutput = """
    Claude Code v1.0.27

    Current session
    ░░░░░░░░░░░░░░░░░░░░ 0% left
    Resets in 30m

    Current week (all models)
    ██████████░░░░░░░░░░ 35% left
    Resets Jan 15, 3:30pm
    """

    static let usedPercentOutput = """
    Current session
    ████████████████████ 25% used

    Current week (all models)
    ████████████░░░░░░░░ 60% used
    """

    static let fableQuotaOutput = """
    Claude Code v2.1.198

    Current session
    ██████████░░░░░░░░░░ 23% used
    Resets 1:09am (America/Chicago)

    Current week (all models)
    ██░░░░░░░░░░░░░░░░░░ 10% used
    Resets Jul 2 at 4:59am (America/Chicago)

    Current week (Fable)
    ████░░░░░░░░░░░░░░░░ 17% used
    Resets Jul 2 at 5:59am (America/Chicago)
    """

    /// 2026-06-15 12:00:00 UTC — a fixed clock for reset times.
    static let now = Date(timeIntervalSince1970: 1_781_524_800)

    // MARK: - Parsing Percentages

    @Test
    func `should show a healthy session with 65% left when the screen prints percent left`() throws {
        let snapshot = try read(Self.sampleClaudeOutput)

        #expect(snapshot.sessionQuota?.percentRemaining == 65)
        #expect(snapshot.sessionQuota?.status == .healthy)
    }

    @Test
    func `should show the weekly window as a warning at 35% left`() throws {
        let snapshot = try read(Self.sampleClaudeOutput)

        #expect(snapshot.weeklyQuota?.percentRemaining == 35)
        #expect(snapshot.weeklyQuota?.status == .warning)
    }

    @Test
    func `should show the Opus weekly window on its own`() throws {
        let snapshot = try read(Self.sampleClaudeOutput)

        let opusQuota = snapshot.quota(for: .modelSpecific("opus"))
        #expect(opusQuota?.percentRemaining == 80)
        #expect(opusQuota?.status == .healthy)
    }

    /// Claude Code 2.1.289's `/usage`: the session's cost and the plugin
    /// skill-listing footprint sit above the limits, and an advice section below.
    static let costAndFootprintAboveTheLimitsOutput = """
    Settings  Status  Config  Usage  Stats

    Session

    Total cost:            $0.0000
    Total duration (API):  0s
    Total duration (wall): 1s
    Total code changes:    0 lines added, 0 lines removed
    Usage:                 0 input, 0 output, 0 cache read, 0 cache write

    Plugin skill-listing footprint
    What each plugin's skill descriptions add to the system prompt (cached input after the first turn).

    feature-dev                 1 skill · ~26 tok/turn

    Total                       ~26 tok/turn

    Current session
    ██████████████░░░░░░░░░░░░░░░░░░░░░░░░░  37% used
    Resets 3:59pm (Asia/Shanghai)

    Current week (all models)
    ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  21% used
    Resets Oct 11 at 10:59am (Asia/Shanghai)

    Current week (Fable)
    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0% used
    Resets Oct 11 at 11am (Asia/Shanghai)

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine — does not include other devices or claude.ai
    """

    @Test
    func `should read the limits when the session's cost and the plugin footprint sit above them`() throws {
        let snapshot = try read(Self.costAndFootprintAboveTheLimitsOutput,
                                config: #"{"oauthAccount":{"billingType":"stripe_subscription"}}"#)

        #expect(snapshot.sessionQuota?.percentRemaining == 63)
        #expect(snapshot.weeklyQuota?.percentRemaining == 79)
        #expect(snapshot.quota(for: .modelSpecific("fable"))?.percentRemaining == 100)
        #expect(snapshot.quota(for: .modelSpecific("fable"))?.resetText?.contains("11am") == true)
    }

    @Test
    func `should show the Fable weekly window with its own reset time`() throws {
        let snapshot = try read(Self.fableQuotaOutput)

        // 17% used = 83% remaining, reset from the Fable section (not all-models)
        let fableQuota = snapshot.quota(for: .modelSpecific("fable"))
        #expect(fableQuota?.percentRemaining == 83)
        #expect(fableQuota?.status == .healthy)
        #expect(fableQuota?.resetText?.contains("5:59am") == true)
    }

    static let fableQuotaWithoutOwnResetOutput = """
    Current session
    ██████████░░░░░░░░░░ 23% used
    Resets 1:09am (America/Chicago)

    Current week (all models)
    ██░░░░░░░░░░░░░░░░░░ 10% used
    Resets Jul 2 at 4:59am (America/Chicago)

    Current week (Fable)
    ████░░░░░░░░░░░░░░░░ 17% used
    """

    @Test
    func `should give the Fable window the weekly reset when its section prints none`() throws {
        let snapshot = try read(Self.fableQuotaWithoutOwnResetOutput)

        // inherits the all-models weekly reset
        let fableQuota = snapshot.quota(for: .modelSpecific("fable"))
        #expect(fableQuota?.percentRemaining == 83)
        #expect(fableQuota?.resetText?.contains("4:59am") == true)
    }

    @Test
    func `should show no Fable window when the screen has no Fable section`() throws {
        let snapshot = try read(Self.sampleClaudeOutput)

        #expect(snapshot.quota(for: .modelSpecific("fable")) == nil)
    }

    @Test
    func `should show percent left when the screen prints percent used`() throws {
        let snapshot = try read(Self.usedPercentOutput)

        // 25% used = 75% left, 60% used = 40% left
        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
    }

    @Test
    func `should show the session as depleted at 0% left`() throws {
        let snapshot = try read(Self.exhaustedQuotaOutput)

        #expect(snapshot.sessionQuota?.percentRemaining == 0)
        #expect(snapshot.sessionQuota?.status == .depleted)
        #expect(snapshot.sessionQuota?.isDepleted == true)
    }

    // MARK: - Account Info from ~/.claude.json

    @Test
    func `should show the account email and organization from Claude Code's config`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", displayName: "Acme Corp")

        let snapshot = try claude.readRawUsageScreen(Self.sampleClaudeOutput)

        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "Acme Corp")
    }

    @Test
    func `should show no account when there is no config, even though the screen prints one`() throws {
        // The screen prints "Account:" and "Organization:" rows; they are not read.
        let snapshot = try read(Self.sampleClaudeOutput)

        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
    }

    @Test
    func `should show the signed-in email and display name`() throws {
        let snapshot = try read(Self.sampleClaudeOutput, config: """
        {
            "oauthAccount": {
                "accountUuid": "abc-123",
                "emailAddress": "user@example.com",
                "organizationUuid": "org-456",
                "displayName": "testuser",
                "billingType": "stripe_subscription"
            }
        }
        """)

        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "testuser")
    }

    @Test
    func `should show only the email when the account has no display name`() throws {
        let snapshot = try read(Self.sampleClaudeOutput, config: """
        {
            "oauthAccount": {
                "emailAddress": "user@example.com"
            }
        }
        """)

        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == nil)
    }

    @Test
    func `should show only the display name when the account has no email`() throws {
        let snapshot = try read(Self.sampleClaudeOutput, config: """
        {
            "oauthAccount": {
                "displayName": "testuser"
            }
        }
        """)

        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == "testuser")
    }

    @Test
    func `should show no account when the config has no signed-in account`() throws {
        let snapshot = try read(Self.sampleClaudeOutput, config: """
        { "numStartups": 100 }
        """)

        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
    }

    @Test
    func `should show no account when the signed-in account has neither email nor name`() throws {
        let snapshot = try read(Self.sampleClaudeOutput, config: """
        {
            "oauthAccount": {
                "accountUuid": "abc-123",
                "organizationUuid": "org-456"
            }
        }
        """)

        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
    }

    @Test
    func `should still show the quotas, with no account, when the config is damaged`() throws {
        let snapshot = try read(Self.sampleClaudeOutput, config: "not valid json {{{")

        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
        #expect(snapshot.sessionQuota?.percentRemaining == 65)
    }

    @Test
    func `should say the CLI missed the subscription when a subscriber's screen shows API billing`() {
        #expect(throws: UsageError.executionFailed(Self.subscriptionMisread)) {
            try read(Self.apiBillingCostPanelOutput, config: """
            {
                "oauthAccount": {
                    "emailAddress": "user@example.com",
                    "billingType": "apple_subscription"
                }
            }
            """)
        }
    }

    @Test
    func `should say the CLI missed the subscription even when the subscriber's account has no name (#271)`() {
        // The billing type decides whether a `/usage` cost panel means "this is
        // an API account" or "the CLI could not see the subscription" (#271),
        // so it is read on its own.
        #expect(throws: UsageError.executionFailed(Self.subscriptionMisread)) {
            try read(Self.apiBillingCostPanelOutput, config: """
            {
                "oauthAccount": {
                    "accountUuid": "abc-123",
                    "billingType": "stripe_subscription"
                }
            }
            """)
        }
    }

    @Test
    func `should fall back to session cost when the account names no billing type`() {
        #expect(throws: UsageError.subscriptionRequired) {
            try read(Self.apiBillingCostPanelOutput, config: """
            {
                "oauthAccount": {
                    "emailAddress": "user@example.com"
                }
            }
            """)
        }
    }

    // MARK: - Error Detection

    static let trustPromptOutput = """
    Do you trust the files in this folder?
    /Users/test/project

    Yes, proceed (y)
    No, cancel (n)
    """

    // New trust prompt format introduced in later Claude CLI versions
    static let newTrustPromptOutput = """
    Accessing workspace:

    /Users/testuser/Library/Application Support/ClaudeBar/Probe

    Quick safety check: Is this a project you created or one you trust? (Like your own code, a well-known open source project, or work from your team). If not, take a moment to review what's in this folder first.

    Claude Code'll be able to read, edit, and execute files here.

    ❯ 1. Yes, I trust this folder
      2. No, exit
    """

    static let authErrorOutput = """
    authentication_error: Your session has expired.
    Please run `claude login` to authenticate.
    """

    @Test
    func `should ask to trust the folder when Claude Code prompts for folder trust`() {
        #expect(throws: UsageError.folderTrustRequired) {
            try read(Self.trustPromptOutput)
        }
    }

    @Test
    func `should ask to trust the folder when Claude Code shows its newer trust prompt`() {
        #expect(throws: UsageError.folderTrustRequired) {
            try read(Self.newTrustPromptOutput)
        }
    }

    @Test
    func `should ask to sign in again when Claude Code's session has expired`() {
        #expect(throws: UsageError.authenticationRequired) {
            try read(Self.authErrorOutput)
        }
    }

    // MARK: - Reset Time Parsing

    @Test
    func `should show when the session resets, counted from now`() throws {
        let snapshot = try read(Self.sampleClaudeOutput, now: Self.now)

        let sessionQuota = snapshot.sessionQuota
        #expect(sessionQuota?.resetsAt == Self.now.addingTimeInterval(2 * 3600 + 15 * 60))
        #expect(sessionQuota?.resetText == "Resets in 2h 15m")
        #expect(sessionQuota?.resetDescription != nil)
    }

    @Test
    func `should show a session reset 30 minutes away`() throws {
        let snapshot = try read(Self.exhaustedQuotaOutput, now: Self.now)

        #expect(snapshot.sessionQuota?.resetsAt == Self.now.addingTimeInterval(30 * 60))
    }

    @Test
    func `should print "Resets" before a reset line that lacks it`() throws {
        let snapshot = try read("""
        Current session
        ████████████████░░░░ 65% left
        in 2h
        """, now: Self.now)

        #expect(snapshot.sessionQuota?.resetText == "Resets in 2h")
        #expect(snapshot.sessionQuota?.resetsAt == Self.now.addingTimeInterval(7200))
    }

    @Test
    func `should show no reset when the screen prints none`() throws {
        let snapshot = try read(Self.usedPercentOutput)

        #expect(snapshot.sessionQuota?.resetText == nil)
        #expect(snapshot.sessionQuota?.resetsAt == nil)
    }

    // MARK: - Absolute Reset Time Parsing (resetsAt populated)

    @Test
    func `should know the reset time and elapsed share when the reset is a time of day`() throws {
        // Pro header with "Resets 4:59pm (America/New_York)"
        let snapshot = try read(Self.proHeaderOutput)

        // resetsAt must be a Date, not nil (enables pace tick)
        let sessionQuota = snapshot.sessionQuota
        #expect(sessionQuota?.resetsAt != nil, "resetsAt should be populated for 'Resets 4:59pm (TZ)' format")
        #expect(sessionQuota?.percentTimeElapsed != nil, "percentTimeElapsed should be computable")
    }

    @Test
    func `should know the reset moment when the reset is a date at a time in another time zone`() throws {
        // real CLI output with "Resets Dec 25 at 4:59am (Asia/Shanghai)"
        let snapshot = try read(Self.realCliOutput, now: Self.now)

        // 2:59pm Shanghai is 06:59 UTC — already past at noon UTC, so tomorrow.
        #expect(snapshot.sessionQuota?.resetsAt == utc(2026, 6, 16, 6, 59))
        #expect(snapshot.weeklyQuota?.resetsAt == utc(2026, 12, 24, 20, 59))
    }

    @Test
    func `should place a reset date already past this year in next year`() throws {
        // "Resets Jan 15, 3:30pm (America/Los_Angeles)" — past this year, so next year
        let snapshot = try read(Self.sampleClaudeOutput, now: Self.now)

        #expect(snapshot.weeklyQuota?.resetsAt == utc(2027, 1, 15, 23, 30))
        #expect(snapshot.quota(for: .modelSpecific("opus"))?.resetsAt == utc(2027, 1, 15, 23, 30))
    }

    @Test
    func `should know the reset moments of a Claude API account's windows`() throws {
        // "Resets 9pm (Asia/Shanghai)" and "Resets Feb 12 at 4pm (Asia/Shanghai)"
        let snapshot = try read(Self.claudeApiWithQuotasOutput, now: Self.now)

        // 9pm Shanghai is 13:00 UTC, still ahead at noon UTC
        #expect(snapshot.sessionQuota?.resetsAt == utc(2026, 6, 15, 13, 0))
        #expect(snapshot.weeklyQuota?.resetsAt == utc(2027, 2, 12, 8, 0))
    }

    // MARK: - Reset on Same Line as Percentage (CLI v2.1.109+ format)

    // Real output from Claude CLI where reset text and percentage share the same line
    // (no separate progress bar line, no separate reset line)
    static let resetOnSameLineOutput = """
    Current session
      Resets 3pm (Europe/Amsterdam)                      27% used


      Current week (all models)
      Resets Apr 16 at 4:59pm (Europe/Amsterdam)         40% used

      Current week (Sonnet only)
      Resets Apr 17 at 11:59am (Europe/Amsterdam)        0% used
    """

    @Test
    func `should show each window's percent when the reset and percent share a line`() throws {
        let snapshot = try read(Self.resetOnSameLineOutput)

        #expect(snapshot.sessionQuota?.percentRemaining == 73) // 27% used = 73% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 60)  // 40% used = 60% remaining
        #expect(snapshot.quota(for: .modelSpecific("sonnet"))?.percentRemaining == 100) // 0% used
    }

    @Test
    func `should know each window's reset when the reset and percent share a line`() throws {
        let snapshot = try read(Self.resetOnSameLineOutput, now: Self.now)

        // 3pm Amsterdam (CEST) is 13:00 UTC, still ahead at noon UTC
        #expect(snapshot.sessionQuota?.resetsAt == utc(2026, 6, 15, 13, 0))
        #expect(snapshot.weeklyQuota?.resetsAt == utc(2027, 4, 16, 14, 59))
        // Sonnet shares the all-models weekly reset, as before
        #expect(snapshot.quota(for: .modelSpecific("sonnet"))?.resetsAt == utc(2027, 4, 16, 14, 59))
    }

    // MARK: - ANSI Code Handling

    static let ansiColoredOutput = """
    \u{1B}[32mCurrent session\u{1B}[0m
    ████████████████░░░░ \u{1B}[33m65% left\u{1B}[0m
    Resets in 2h 15m
    """

    @Test
    func `should show the session when the screen is coloured`() throws {
        let snapshot = try read(Self.ansiColoredOutput)

        #expect(snapshot.sessionQuota?.percentRemaining == 65)
    }

    // MARK: - Account Type Detection from Header

    // /usage header for Max account
    static let maxHeaderOutput = """
    Opus 4.5 · Claude Max · user@example.com's Organization

    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m
    """

    // /usage header for Pro account
    static let proHeaderOutput = """
    Opus 4.5 · Claude Pro · Organization

    Current session
    █████░░░░░░░░░░░░░░░ 1% used
    Resets 4:59pm (America/New_York)
    """

    // Real CLI output format with Settings header
    static let realCliOutput = """
    Opus 4.5 · Claude Pro · Some User
    ~/Projects/ClaudeBar

    Settings: Status  Config  Usage (tab to cycle)

    Current session
    ▌                                                  1% used
    Resets 2:59pm (Asia/Shanghai)

    Current week (all models)
    █████                                              16% used
    Resets Dec 25 at 4:59am (Asia/Shanghai)

    Extra usage
    Extra usage not enabled • /extra-usage to enable

    Esc to cancel
    """

    // Real CLI output with ANSI escape codes (from actual terminal)
    static let realCliOutputWithAnsi = """
    \u{1B}[?25l\u{1B}[?2004h\u{1B}[?25h\u{1B}[?2004l\u{1B}[?2026h
    Opus 4.5 · Claude Pro · Some User
    ~/Projects/ClaudeBar

    \u{1B}[33mSettings:\u{1B}[0m Status  Config  \u{1B}[7mUsage\u{1B}[0m (tab to cycle)

    \u{1B}[1mCurrent session\u{1B}[0m
    \u{1B}[34m▌\u{1B}[0m                                                  1% used
    Resets 2:59pm (Asia/Shanghai)

    \u{1B}[1mCurrent week (all models)\u{1B}[0m
    \u{1B}[34m█████\u{1B}[0m                                              16% used
    Resets Dec 25 at 4:59am (Asia/Shanghai)

    \u{1B}[1mExtra usage\u{1B}[0m
    Extra usage not enabled • /extra-usage to enable

    Esc to cancel
    \u{1B}[?2026l
    """

    @Test
    func `should show the Pro plan, session and weekly windows, and no extra usage, under the Settings header`() throws {
        let snapshot = try read(Self.realCliOutput)

        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.sessionQuota?.percentRemaining == 99) // 1% used = 99% left
        #expect(snapshot.weeklyQuota?.percentRemaining == 84) // 16% used = 84% left
        #expect(snapshot.costUsage == nil) // Extra usage not enabled
    }

    @Test
    func `should show the Pro plan and windows when the real screen carries terminal escape codes`() throws {
        let snapshot = try read(Self.realCliOutputWithAnsi)

        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.sessionQuota?.percentRemaining == 99) // 1% used = 99% left
        #expect(snapshot.weeklyQuota?.percentRemaining == 84) // 16% used = 84% left
    }

    @Test
    func `should show the Max plan when the header names it`() throws {
        #expect(try read(Self.maxHeaderOutput).accountTier == .claudeMax)
    }

    @Test
    func `should show the Pro plan when the header names it`() throws {
        #expect(try read(Self.proHeaderOutput).accountTier == .claudePro)
    }

    @Test
    func `should show the Max plan when there is no header but there are quotas`() throws {
        #expect(try read("Current session\n75% left").accountTier == .claudeMax)
    }

    @Test
    func `should show the Max plan when there is no header but quotas and extra usage`() throws {
        let output = """
        Current session
        75% left

        Extra usage
        $5.00 / $20.00 spent
        """

        // Both Max and Pro can have Extra usage, defaults to Max without header
        #expect(try read(output).accountTier == .claudeMax)
    }

    // MARK: - Extra Usage Parsing

    static let proWithExtraUsageOutput = """
    Opus 4.5 · Claude Pro · Organization

    Current session
    █████░░░░░░░░░░░░░░░ 1% used
    Resets 4:59pm (America/New_York)

    Current week (all models)
    █████████████████░░░ 36% used
    Resets Dec 25 at 2:59pm (America/New_York)

    Extra usage
    █████░░░░░░░░░░░░░░░ 27% used
    $5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)
    """

    static let maxWithExtraUsageNotEnabled = """
    Opus 4.5 · Claude Max · Organization

    Current session
    ████████████████░░░░ 82% used
    Resets 3pm (Asia/Shanghai)

    Extra usage
    Extra usage not enabled · /extra-usage to enable
    """

    @Test
    func `should show a Pro account's extra-usage spend against its limit`() throws {
        let costUsage = try read(Self.proWithExtraUsageOutput).costUsage

        #expect(costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(costUsage?.budget == Decimal(string: "20.00"))
        #expect(costUsage?.kind == .extraUsage)
    }

    @Test
    func `should show extra-usage spend, limit and reset`() throws {
        let costUsage = try read("""
        Current session
        75% left

        Extra usage
        $5.41 / $20.00 spent · Resets Jan 1, 2026
        """).costUsage

        #expect(costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(costUsage?.budget == Decimal(string: "20.00"))
        #expect(costUsage?.resetText?.contains("Resets Jan 1, 2026") == true)
    }

    @Test
    func `should show extra-usage spend when the amounts have no dollar sign`() throws {
        let costUsage = try read("""
        Current session
        75% left

        Extra usage
        5.41 / 20.00 spent
        """).costUsage

        #expect(costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(costUsage?.budget == Decimal(string: "20.00"))
    }

    @Test
    func `should show extra-usage spend when the amounts have thousands separators`() throws {
        let costUsage = try read("""
        Current session
        75% left

        Extra usage
        $1,234.50 / $2,000.00 spent
        """).costUsage

        #expect(costUsage?.totalCost == Decimal(string: "1234.50"))
        #expect(costUsage?.budget == Decimal(string: "2000.00"))
    }

    @Test
    func `should show no extra usage when it isn't enabled`() throws {
        let snapshot = try read(Self.maxWithExtraUsageNotEnabled)

        #expect(snapshot.costUsage == nil)
        #expect(snapshot.sessionQuota?.percentRemaining == 18)
    }

    @Test
    func `should show no extra usage when the screen has no extra-usage section`() throws {
        let output = """
        Current session
        65% left
        """

        #expect(try read(output).costUsage == nil)
    }

    @Test
    func `should show a Pro account's quotas together with its extra-usage spend`() throws {
        let snapshot = try read(Self.proWithExtraUsageOutput)

        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20.00"))
        #expect(snapshot.quotas.count >= 1)
    }

    @Test
    func `should know when extra usage resets when the reset sits mid-line`() throws {
        // "$5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)"
        // "Resets" appears mid-line, not at the start
        let snapshot = try read(Self.proWithExtraUsageOutput, now: Self.now)

        #expect(snapshot.costUsage?.resetsAt == utc(2026, 1, 1, 5, 0),
                "resetsAt should be populated when 'Resets' appears mid-line in cost line")
        #expect(snapshot.costUsage?.resetText?.contains("Resets Jan 1, 2026") == true)
    }

    // MARK: - API Usage Billing Account Detection

    // Real output from API Usage Billing account showing subscription-only message
    static let apiUsageBillingOutput = """
    Sonnet 4.5 · API Usage Billing · dzienisz
    ~/Library/Application Support/ClaudeBar/Probe

    Settings: Status  Config  Usage (tab to cycle)

    /usage is only available for subscription plans.

    Esc to cancel
    """

    // Subscription account that has added Extra Usage credits. The CLI header shows
    // only "API Usage Billing" (no Pro/Max tier word), but valid quota bars still
    // appear — there is NO "/usage is only available for subscription plans" error.
    static let apiUsageBillingWithQuotasOutput = """
    ▐▛███▜▌   Claude Code v2.1.34
    ▝▜█████▛▘  Sonnet 4.5 · API Usage Billing · user@example.com
    ▘▘ ▝▝    ~/Library/Application Support/ClaudeBar/Probe

    ❯ /usage
    Settings:  Status   Config   Usage  (←/→ or tab to cycle)


    Current session
    ██▌                                                5% used
    Resets 9pm (Asia/Shanghai)

    Current week (all models)
    █████████▌                                         19% used
    Resets Feb 12 at 4pm (Asia/Shanghai)

    Esc to cancel
    """

    // Claude API account (subscription with quotas, different from API Usage Billing)
    static let claudeApiWithQuotasOutput = """
    ▐▛███▜▌   Claude Code v2.1.34
    ▝▜█████▛▘  Sonnet 4.5 · Claude API
    ▘▘ ▝▝    ~/Library/Application Support/ClaudeBar/Probe

    ❯ /usage
    Settings:  Status   Config   Usage  (←/→ or tab to cycle)


    Current session
    ██▌                                                5% used
    Resets 9pm (Asia/Shanghai)

    Current week (all models)
    █████████▌                                         19% used
    Resets Feb 12 at 4pm (Asia/Shanghai)

    Current week (Sonnet only)
    ███▌                                               7% used
    Resets Feb 9 at 8pm (Asia/Shanghai)

    Esc to cancel
    """

    @Test
    func `should show a subscription plan when the header says API Usage Billing but quotas show`() throws {
        // header has "API Usage Billing" but no subscription-only error, and the
        // output contains real quota bars (subscription with Extra Usage credits).
        let accountType = try read(Self.apiUsageBillingWithQuotasOutput).accountTier

        // must NOT be .claudeApi; quota fallback defaults to .claudeMax
        #expect(accountType != .claudeApi)
        #expect(accountType == .claudeMax)
    }

    @Test
    func `should show a subscriber's windows when Extra Usage credits put API Usage Billing in the header`() throws {
        let snapshot = try read(Self.apiUsageBillingWithQuotasOutput)

        // quotas parsed; no fall-through to /cost
        #expect(snapshot.accountTier == .claudeMax)
        #expect(snapshot.sessionQuota?.percentRemaining == 95) // 5% used → 95% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 81)  // 19% used → 81% remaining
    }

    @Test
    func `should fall back to session cost when Claude says usage is for subscription plans only`() {
        #expect(throws: UsageError.subscriptionRequired) {
            try read("/usage is only available for subscription plans.")
        }
    }

    @Test
    func `should show the Max plan when a Claude API header comes with quotas`() throws {
        let output = """
        Sonnet 4.5 · Claude API

        Current session
        75% left
        """

        // Should NOT be treated as .claudeApi (which is for pay-as-you-go);
        // defaults to .claudeMax since it has quota data
        #expect(try read(output).accountTier == .claudeMax)
    }

    @Test
    func `should show a Claude API account's session, weekly and Sonnet windows`() throws {
        let snapshot = try read(Self.claudeApiWithQuotasOutput)

        // Should parse quotas, not throw subscriptionRequired
        #expect(snapshot.accountTier == .claudeMax) // Defaults to Max for API accounts with quotas
        #expect(snapshot.sessionQuota?.percentRemaining == 95) // 5% used = 95% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 81) // 19% used = 81% remaining
        #expect(snapshot.quota(for: .modelSpecific("sonnet"))?.percentRemaining == 93) // 7% used = 93% remaining
    }

    @Test
    func `should fall back to session cost when an API-billing account opens the usage screen`() {
        #expect(throws: UsageError.subscriptionRequired) {
            try read(Self.apiUsageBillingOutput)
        }
    }

    // MARK: - Terminal Rendering

    @Test
    func `should read the session where cursor movements placed the text`() throws {
        // "Hello" + move 5 columns right + "World", on the label and the reset rows
        let snapshot = try read(
            "Current session\r\n████████\u{1B}[30C20% used\r\nResets\u{1B}[1Cin 2h 15m",
            now: Self.now
        )

        #expect(snapshot.sessionQuota?.percentRemaining == 80)
        #expect(snapshot.sessionQuota?.resetText == "Resets in 2h 15m")
        #expect(snapshot.sessionQuota?.resetsAt == Self.now.addingTimeInterval(2 * 3600 + 15 * 60))
    }

    @Test
    func `should show the session when colour codes sit inside its label`() throws {
        // Green colored text + reset + normal
        let snapshot = try read("\u{1B}[32mCurrent\u{1B}[0m session\n\u{1B}[33m42%\u{1B}[0m left")

        #expect(snapshot.sessionQuota?.percentRemaining == 42)
    }

    @Test
    func `should show the windows that scrolled off the visible screen`() throws {
        // the CLI /usage screen grew past 50 rows (usage-contribution report),
        // pushing the quota sections above the visible screen into scrollback
        let filler = (1...60).map { "contributing insight line \($0)" }.joined(separator: "\n")
        let output = """
        Current session
        ██████████████████████████████▌                    61% used
        Resets 1:09am (America/Chicago)

        Current week (all models)
        █████████                                          18% used
        Resets Jul 2 at 4:59am (America/Chicago)

        Current week (Fable)
        ████████████████                                   32% used
        Resets Jul 2 at 5:59am (America/Chicago)

        What's contributing to your limits usage?
        \(filler)
        """

        let snapshot = try read(output)

        #expect(snapshot.sessionQuota?.percentRemaining == 39)
        #expect(snapshot.weeklyQuota?.percentRemaining == 82)
        #expect(snapshot.quota(for: .modelSpecific("fable"))?.percentRemaining == 68)
    }

    @Test
    func `should show the session and weekly windows from a cleanly rendered screen`() throws {
        // clean terminal output as rendered by SwiftTerm
        let output = """
        Opus 4.5 · Claude Max · user@example.com's Organization

        Current session
        ████████                                         20% used
        Resets 6pm (Asia/Shanghai)

        Current week (all models)
        ███████████▌                                     23% used
        Resets Jan 15, 4pm (Asia/Shanghai)
        """

        let snapshot = try read(output)

        #expect(snapshot.sessionQuota?.percentRemaining == 80) // 20% used = 80% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 77)  // 23% used = 77% remaining
    }

    // MARK: - Terminal Rendering Deduplication

    @Test
    func `should show each reset once, with its moment, when a redraw doubles the reset line`() throws {
        // terminal rendering artifact where cursor misalignment causes
        // reset text to appear twice on a single line
        let output = """
        Opus 4.5 · Claude Pro · Organization

        Current session
        █████░░░░░░░░░░░░░░░ 6% used
        Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)

        Current week (all models)
        █████████████████░░░ 36% used
        Resets Dec 25 at 2:59pm (America/New_York)Resets Dec 25 at 2:59pm (America/New_York)
        """

        let snapshot = try read(output, now: Self.now)

        // quotas parse with clean reset text
        let session = snapshot.sessionQuota
        #expect(session?.resetsAt == utc(2026, 6, 15, 20, 59), "resetsAt should be populated despite duplicated text")
        #expect(session?.resetText == "Resets 4:59pm (America/New_York)")
        // Should NOT contain the duplication
        #expect(session?.resetText?.components(separatedBy: "Resets").count == 2,
                "resetText should contain 'Resets' exactly once (prefix + content)")

        let weekly = snapshot.weeklyQuota
        #expect(weekly?.resetsAt == utc(2026, 12, 25, 19, 59), "weekly resetsAt should be populated despite duplicated text")
        #expect(weekly?.resetText == "Resets Dec 25 at 2:59pm (America/New_York)")
    }

    @Test
    func `should print "Resets" once when a redraw doubles the reset line`() throws {
        let text = """
        Current session
        ████ 6% used
        Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)
        """

        let resetText = try #require(try read(text).sessionQuota?.resetText)

        let resetsCount = resetText.components(separatedBy: "Resets").count - 1
        #expect(resetsCount == 1, "Should contain 'Resets' exactly once, got \(resetsCount) in: \(resetText)")
    }

    // MARK: - Unfinished / API-billing Screens (issue #271)

    /// The Usage tab as it looks before the quota request comes back.
    static let stillLoadingOutput = """
    Claude Code v2.1.251
    Opus 5 (1M context) · Claude Max

      Settings  Status  Config  Usage  Stats

      Session
        Total cost:            $0.0000
        Total duration (API):  0s
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write

        Loading usage data…

      Esc to cancel
    """

    /// The Usage tab for a session the CLI resolved to API billing: a cost panel,
    /// no quota bars, and nothing left to wait for.
    static let apiBillingCostPanelOutput = """
    Claude Code v2.1.251
    Opus 5 (1M context) · API Usage Billing

      Settings  Status  Config  Usage  Stats

      Session
        Total cost:            $0.0000
        Total duration (API):  0s
        Total duration (wall): 0s
        Total code changes:    0 lines added, 0 lines removed
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write

      Esc to cancel
    """

    static let subscriptionMisread =
        "The Claude CLI did not see this account's subscription — its usage screen reported API billing instead of a plan. "
        + "Run `claude auth login` again, or switch Claude to API mode in Settings."

    @Test
    func `should say usage never finished loading when the screen is still loading`() {
        #expect(throws: UsageError.executionFailed(
            "Claude usage data did not finish loading — the usage endpoint may be rate limited. Try again in a moment."
        )) {
            try read(Self.stillLoadingOutput)
        }
    }

    @Test
    func `should show session cost when the usage panel has lost its header`() throws {
        let panel = "Session\nTotal cost: $0.0000\nTotal duration (API): 0s\nEsc to cancel"
        #expect(throws: UsageError.subscriptionRequired) { try read(panel) }
    }

    @Test
    func `should explain reconnection when a subscription account shows a headerless cost panel`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "stripe_subscription")
        #expect(throws: UsageError.executionFailed(Self.subscriptionMisread)) {
            try claude.readUsageScreen("Session\nTotal cost: $0.0000\nTotal duration (API): 0s\nEsc to cancel")
        }
    }

    @Test
    func `should fall back to session cost when the screen shows the API-billing cost panel`() {
        #expect(throws: UsageError.subscriptionRequired) {
            try read(Self.apiBillingCostPanelOutput)
        }
    }

    @Test
    func `should say the CLI missed the subscription when a subscriber gets the API-billing cost panel (#271)`() throws {
        // A Max plan billed through Apple still renders the API-billing cost
        // panel when the CLI cannot see the subscription (#271). Answering with
        // `/cost` would report $0.00 and no quota, and — because it succeeds —
        // would stop the provider from trying the usage API, which can still
        // read the real quota. Fail instead, so that fallback runs.
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "apple_subscription")

        #expect(throws: UsageError.executionFailed(Self.subscriptionMisread)) {
            try claude.readRawUsageScreen(Self.apiBillingCostPanelOutput)
        }
    }

    @Test
    func `should fall back to session cost when a pay-as-you-go account gets the cost panel`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "api")

        #expect(throws: UsageError.subscriptionRequired) {
            try claude.readRawUsageScreen(Self.apiBillingCostPanelOutput)
        }
    }

    // MARK: - /cost Hand-offs That Would Misreport (issue #317)

    /// The other route into `/cost`. "/usage is only available for subscription
    /// plans" hands off to `cliCost`; a subscription that reaches it gets the
    /// probe session's own $0.00 — and because that *succeeds*, the usage API
    /// that can read its real quota never runs.
    static let subscriptionOnlyMessageOutput = """
    Claude Code v2.1.274
    Opus 5 (1M context) · API Usage Billing

      Session
        Total cost:            $0.0000
        Total duration (API):  0s
        Total duration (wall): 1s
        Total code changes:    0 lines added, 0 lines removed
        Usage: 0 input, 0 output, 0 cache read, 0 cache write

    /usage is only available for subscription plans. /cost shows session cost.
    """

    @Test
    func `should say the CLI missed the subscription when a subscriber is told usage is for subscription plans only (#317)`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "apple_subscription")

        #expect(throws: UsageError.executionFailed(Self.subscriptionMisread)) {
            try claude.readRawUsageScreen(Self.subscriptionOnlyMessageOutput)
        }
    }

    @Test
    func `should fall back to session cost when a pay-as-you-go account is told usage is for subscription plans only`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "user@example.com", billingType: "api")

        #expect(throws: UsageError.subscriptionRequired) {
            try claude.readRawUsageScreen(Self.subscriptionOnlyMessageOutput)
        }
    }

    @Test
    func `should show the windows when a subscriber's header mentions API Usage Billing beside quotas`() throws {
        // Extra Usage credits put "API Usage Billing" in a subscription header —
        // the quota bars are what decide, not the header.
        let output = """
        Claude Code v2.1.251
        Opus 5 (1M context) · API Usage Billing

        Current session
        ████ 25% used

        Current week (all models)
        ████ 60% used
        """

        let snapshot = try read(output)

        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
    }

    // MARK: - Ultra (the old Max 20x), Max (5x) and team seats

    /// [Inferred] `/usage` for a verified Ultra account: Claude says "If you
    /// don't see a Current session bar, your account is verified"
    /// (support.claude.com/en/articles/17728952), so only the weekly bars remain.
    static let verifiedUltraOutput = """
    Claude Code v2.1.301
    Opus 5.5 · Claude Ultra · user@example.com's Organization

    Current week (all models)
    █░░░░░░░░░░░░░░░░░░░ 3% used
    Resets Nov 6 at 1pm (UTC)

    Current week (Fable)
    ░░░░░░░░░░░░░░░░░░░░ 0% used
    Resets Nov 6 at 1pm (UTC)
    """

    @Test
    func `should show only the weekly and Fable limits when a verified Ultra account has no session bar`() throws {
        let snapshot = try read(Self.verifiedUltraOutput)

        #expect(snapshot.quotas.map(\.quotaType) == [.weekly, .modelSpecific("fable")])
        #expect(snapshot.sessionQuota == nil)
        #expect(snapshot.weeklyQuota?.percentRemaining == 97)
        #expect(snapshot.quota(for: .modelSpecific("fable"))?.percentRemaining == 100)
        #expect(snapshot.accountTier == .custom("ULTRA"))
    }

    @Test
    func `should still say the usage was not found when the screen has neither a session nor a weekly bar`() {
        #expect(throws: UsageError.parseFailed("Could not find session usage")) {
            try read("Opus 5.5 · Claude Ultra · Organization\n\nNothing to show")
        }
    }

    @Test
    func `should show an Ultra account without a session bar when only Claude Code's config names Ultra`() throws {
        // The header still says Max; `~/.claude.json` has the account on the Ultra (20x) limits.
        let output = Self.verifiedUltraOutput.replacingOccurrences(of: "Claude Ultra", with: "Claude Max")

        let snapshot = try read(output, config: account("claude_max", "default_claude_max_20x"))

        #expect(snapshot.quotas.map(\.quotaType) == [.weekly, .modelSpecific("fable")])
        #expect(snapshot.accountTier == .custom("ULTRA"))
    }

    @Test
    func `should still say the session was not found when a Max screen has a weekly bar but no session row yet`() {
        // A capture taken before the session row was painted: only Ultra has no 5-hour limit.
        let output = Self.verifiedUltraOutput.replacingOccurrences(of: "Claude Ultra", with: "Claude Max")

        #expect(throws: UsageError.parseFailed("Could not find session usage")) {
            try read(output, config: account("claude_max", "default_claude_max_5x"))
        }
    }

    @Test
    func `should still say the session was not found when a Pro screen has a weekly bar but no session row yet`() {
        let output = Self.verifiedUltraOutput.replacingOccurrences(of: "Claude Ultra", with: "Claude Pro")

        #expect(throws: UsageError.parseFailed("Could not find session usage")) {
            try read(output)
        }
    }

    @Test
    func `should not take a number from the contributing-usage section for a weekly row that has none yet`() throws {
        let output = """
        Opus 5.5 · Claude Max · Organization

        Current session
        █████░░░░░░░░░░░░░░░ 25% used
        Resets 3:59pm (UTC)

        Current week (all models)
        ░░░░░░░░░░░░░░░░░░░░

        What's contributing to your limits usage?
        Approximate, based on local sessions on this machine
        Subagents  40% used
        """

        let snapshot = try read(output)

        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota == nil)
    }

    @Test
    func `should not take the contributing-usage heading for the weekly reset when the weekly row prints none`() throws {
        let output = """
        Current session
        █████░░░░░░░░░░░░░░░ 25% used

        Current week (all models)
        ████████████░░░░░░░░ 60% used

        what's contributing to your limits usage?
        Approximate, based on local sessions on this machine
        """

        let snapshot = try read(output)

        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
        #expect(snapshot.weeklyQuota?.resetText == nil)
    }

    @Test
    func `should not take the weekly bar's number for a session row that has none yet`() {
        // The session row is painted, its bar not filled yet; the weekly bar below has its number.
        let output = """
        Opus 5.5 · Claude Max · Organization

        Current session
        ░░░░░░░░░░░░░░░░░░░░

        Current week (all models)
        █████░░░░░░░░░░░░░░░ 25% used
        Resets Nov 6 at 1pm (UTC)
        """

        #expect(throws: UsageError.parseFailed("Could not find session usage")) {
            try read(output)
        }
    }

    @Test
    func `should not give the session the weekly reset when the session prints none`() throws {
        let output = """
        Current session
        █████░░░░░░░░░░░░░░░ 25% used

        Current week (all models)
        ████████████░░░░░░░░ 60% used
        Resets Nov 6 at 1pm (UTC)
        """

        let snapshot = try read(output)

        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.sessionQuota?.resetText == nil)
        #expect(snapshot.sessionQuota?.resetsAt == nil)
        #expect(snapshot.weeklyQuota?.resetText?.contains("Nov 6") == true)
    }

    /// `~/.claude.json` as Claude Code keeps it after reading the profile.
    private func account(_ organizationType: String, _ tier: String) -> String {
        #"{"oauthAccount":{"billingType":"stripe_subscription","organizationType":"\#(organizationType)","organizationRateLimitTier":"\#(tier)"}}"#
    }

    @Test
    func `should badge ULTRA when the header says Max but the account is on the Ultra (20x) limits`() throws {
        // Claude Code prints "Claude Max" for an Ultra account until it has the plan's new name.
        let snapshot = try read(Self.maxHeaderOutput, config: account("claude_max", "default_claude_max_20x"))

        #expect(snapshot.accountTier == .custom("ULTRA"))
    }

    @Test
    func `should badge MAX for a Max 5x account`() throws {
        let snapshot = try read(Self.maxHeaderOutput, config: account("claude_max", "default_claude_max_5x"))

        #expect(snapshot.accountTier == .claudeMax)
    }

    @Test
    func `should badge TEAM, not MAX, for a team premium seat on the Max 5x limits`() throws {
        let output = """
        Opus 5.5 · Claude Team · Example Org

        Current session
        ████ 25% used

        Current week (all models)
        ████ 60% used
        """

        let snapshot = try read(output, config: account("claude_team", "default_claude_max_5x"))

        #expect(snapshot.accountTier == .custom("TEAM"))
    }

    // MARK: - Helpers

    /// The screen as the `cli` data source reads it: rendered, then scripted,
    /// with `config` as `~/.claude.json` when given.
    private func read(_ screen: String, config: String? = nil, now: Date? = nil) throws -> UsageSnapshot {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        if let now { claude.now = now }
        if let config {
            try Data(config.utf8).write(to: claude.home.appendingPathComponent(".claude.json"))
        }
        return try claude.readRawUsageScreen(screen)
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
#endif
