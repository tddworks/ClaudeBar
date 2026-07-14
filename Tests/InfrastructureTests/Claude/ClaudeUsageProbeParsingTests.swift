import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct ClaudeUsageProbeParsingTests {

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

    // MARK: - Parsing Percentages

    @Test
    func `parses session quota from left format`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 65)
        #expect(snapshot.sessionQuota?.status == .healthy)
    }

    @Test
    func `parses weekly quota from left format`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.weeklyQuota?.percentRemaining == 35)
        #expect(snapshot.weeklyQuota?.status == .warning)
    }

    @Test
    func `parses model specific quota like opus`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        let opusQuota = snapshot.quota(for: .modelSpecific("opus"))
        #expect(opusQuota?.percentRemaining == 80)
        #expect(opusQuota?.status == .healthy)
    }

    @Test
    func `parses fable weekly quota with its own reset time`() throws {
        // Given
        let output = Self.fableQuotaOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then - 17% used = 83% remaining, reset from the Fable section (not all-models)
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
    func `fable quota falls back to weekly reset when its section has none`() throws {
        // Given
        let output = Self.fableQuotaWithoutOwnResetOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then - inherits the all-models weekly reset
        let fableQuota = snapshot.quota(for: .modelSpecific("fable"))
        #expect(fableQuota?.percentRemaining == 83)
        #expect(fableQuota?.resetText?.contains("4:59am") == true)
    }

    @Test
    func `no fable quota when section absent`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.quota(for: .modelSpecific("fable")) == nil)
    }

    @Test
    func `converts used format to remaining`() throws {
        // Given
        let output = Self.usedPercentOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then - 25% used = 75% left, 60% used = 40% left
        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
    }

    @Test
    func `detects depleted quota at zero percent`() throws {
        // Given
        let output = Self.exhaustedQuotaOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 0)
        #expect(snapshot.sessionQuota?.status == .depleted)
        #expect(snapshot.sessionQuota?.isDepleted == true)
    }

    // MARK: - Account Info from Resolver

    @Test
    func `account info comes from resolver not CLI output`() throws {
        // Given - resolver provides account info
        let mockResolver = MockAccountInfoResolving()
        given(mockResolver).resolve().willReturn(AccountInfo(email: "user@example.com", organization: "Acme Corp"))

        // When - parse with resolver
        let snapshot = try ClaudeUsageProbe.parse(Self.sampleClaudeOutput, accountInfoResolver: mockResolver)

        // Then - account info from resolver
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "Acme Corp")
    }

    @Test
    func `account info is nil when resolver returns nil`() throws {
        // Given - no resolver (default)
        let snapshot = try simulateParse(text: Self.sampleClaudeOutput)

        // Then - no account info
        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
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
    func `detects folder trust prompt and throws error`() throws {
        // Given
        let output = Self.trustPromptOutput

        // When & Then
        #expect(throws: ProbeError.self) {
            try simulateParse(text: output)
        }
    }

    @Test
    func `detects new folder trust prompt format and throws error`() throws {
        // Given - New trust prompt format with "Is this a project you created or one you trust"
        let output = Self.newTrustPromptOutput

        // When & Then
        #expect(throws: ProbeError.self) {
            try simulateParse(text: output)
        }
    }

    @Test
    func `detects authentication error and throws error`() throws {
        // Given
        let output = Self.authErrorOutput

        // When & Then
        #expect(throws: ProbeError.self) {
            try simulateParse(text: output)
        }
    }

    // MARK: - Reset Time Parsing

    @Test
    func `parses session reset time from output`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then
        let sessionQuota = snapshot.sessionQuota
        #expect(sessionQuota?.resetsAt != nil)
        #expect(sessionQuota?.resetDescription != nil)
    }

    @Test
    func `parses short reset time like 30m`() throws {
        // Given
        let output = Self.exhaustedQuotaOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then
        let sessionQuota = snapshot.sessionQuota
        #expect(sessionQuota?.resetsAt != nil)
        // Should be about 30 minutes from now
        if let timeUntil = sessionQuota?.timeUntilReset {
            #expect(timeUntil > 25 * 60) // > 25 minutes
            #expect(timeUntil < 35 * 60) // < 35 minutes
        }
    }

    // MARK: - Absolute Reset Time Parsing (resetsAt populated)

    @Test
    func `populates resetsAt for time only reset format`() throws {
        // Given — Pro header with "Resets 4:59pm (America/New_York)"
        let output = Self.proHeaderOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then — resetsAt must be a Date, not nil (enables pace tick)
        let sessionQuota = snapshot.sessionQuota
        #expect(sessionQuota?.resetsAt != nil, "resetsAt should be populated for 'Resets 4:59pm (TZ)' format")
        #expect(sessionQuota?.percentTimeElapsed != nil, "percentTimeElapsed should be computable")
    }

    @Test
    func `populates resetsAt for date at time reset format`() throws {
        // Given — real CLI output with "Resets Dec 25 at 4:59am (Asia/Shanghai)"
        let output = Self.realCliOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then — both session and weekly should have resetsAt populated
        #expect(snapshot.sessionQuota?.resetsAt != nil, "Session resetsAt should be populated for 'Resets 2:59pm (TZ)' format")
        #expect(snapshot.weeklyQuota?.resetsAt != nil, "Weekly resetsAt should be populated for 'Resets Dec 25 at 4:59am (TZ)' format")
    }

    @Test
    func `populates resetsAt for date comma time format`() throws {
        // Given — sample output with "Resets Jan 15, 3:30pm (America/Los_Angeles)"
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then — weekly and opus should have resetsAt populated (session uses relative "2h 15m" which already works)
        #expect(snapshot.weeklyQuota?.resetsAt != nil, "Weekly resetsAt should be populated for 'Resets Jan 15, 3:30pm (TZ)' format")
    }

    @Test
    func `populates resetsAt for Claude API quotas with absolute times`() throws {
        // Given — Claude API output with "Resets 9pm (Asia/Shanghai)" and "Resets Feb 12 at 4pm (Asia/Shanghai)"
        let output = Self.claudeApiWithQuotasOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then — all quotas should have resetsAt populated
        #expect(snapshot.sessionQuota?.resetsAt != nil, "Session resetsAt should be populated for 'Resets 9pm (TZ)' format")
        #expect(snapshot.weeklyQuota?.resetsAt != nil, "Weekly resetsAt should be populated for 'Resets Feb 12 at 4pm (TZ)' format")
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
    func `parses percentages when reset and percent share same line`() throws {
        // When
        let snapshot = try simulateParse(text: Self.resetOnSameLineOutput)

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 73) // 27% used = 73% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 60)  // 40% used = 60% remaining
        #expect(snapshot.quota(for: .modelSpecific("sonnet"))?.percentRemaining == 100) // 0% used
    }

    @Test
    func `parses resetsAt when reset and percent share same line`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parse(Self.resetOnSameLineOutput)

        // Then — all quotas should have resetsAt populated (enables pace triangle)
        #expect(snapshot.sessionQuota?.resetsAt != nil,
                "Session resetsAt should be populated for 'Resets 3pm (TZ) ... 27% used' format")
        #expect(snapshot.weeklyQuota?.resetsAt != nil,
                "Weekly resetsAt should be populated for 'Resets Apr 16 at 4:59pm (TZ) ... 40% used' format")
        #expect(snapshot.quota(for: .modelSpecific("sonnet"))?.resetsAt != nil,
                "Sonnet resetsAt should be populated for 'Resets Apr 17 at 11:59am (TZ) ... 0% used' format")
    }

    // MARK: - ANSI Code Handling

    static let ansiColoredOutput = """
    \u{1B}[32mCurrent session\u{1B}[0m
    ████████████████░░░░ \u{1B}[33m65% left\u{1B}[0m
    Resets in 2h 15m
    """

    @Test
    func `strips ansi color codes before parsing`() throws {
        // Given
        let output = Self.ansiColoredOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
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
    func `parses real CLI output with Settings header`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parse(Self.realCliOutput)

        // Then
        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.sessionQuota != nil)
        #expect(snapshot.sessionQuota?.percentRemaining == 99) // 1% used = 99% left
        #expect(snapshot.weeklyQuota != nil)
        #expect(snapshot.weeklyQuota?.percentRemaining == 84) // 16% used = 84% left
        #expect(snapshot.costUsage == nil) // Extra usage not enabled
    }

    @Test
    func `parses real CLI output with ANSI escape codes`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parse(Self.realCliOutputWithAnsi)

        // Then
        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.sessionQuota != nil)
        #expect(snapshot.sessionQuota?.percentRemaining == 99) // 1% used = 99% left
        #expect(snapshot.weeklyQuota != nil)
        #expect(snapshot.weeklyQuota?.percentRemaining == 84) // 16% used = 84% left
    }

    @Test
    func `detects Max account type from header`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When
        let accountType = probe.detectAccountType(Self.maxHeaderOutput)

        // Then
        #expect(accountType == .claudeMax)
    }

    @Test
    func `detects Pro account type from header`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When
        let accountType = probe.detectAccountType(Self.proHeaderOutput)

        // Then
        #expect(accountType == .claudePro)
    }

    @Test
    func `detects Max account type from percentage data when no header`() throws {
        // Given
        let probe = ClaudeUsageProbe()
        let output = "Current session\n75% left"

        // When
        let accountType = probe.detectAccountType(output)

        // Then
        #expect(accountType == .claudeMax)
    }

    @Test
    func `defaults to Max when no header but has quota data`() throws {
        // Given
        let probe = ClaudeUsageProbe()
        let output = """
        Current session
        75% left

        Extra usage
        $5.00 / $20.00 spent
        """

        // When
        let accountType = probe.detectAccountType(output)

        // Then - Both Max and Pro can have Extra usage, defaults to Max without header
        #expect(accountType == .claudeMax)
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
    func `parses Extra usage cost for Pro account`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When
        let costUsage = probe.extractExtraUsage(Self.proWithExtraUsageOutput)

        // Then
        #expect(costUsage != nil)
        #expect(costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(costUsage?.budget == Decimal(string: "20.00"))
        #expect(costUsage?.kind == .extraUsage)
    }

    @Test
    func `parses Extra usage cost line`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When
        let result = probe.parseExtraUsageCostLine("$5.41 / $20.00 spent · Resets Jan 1, 2026")

        // Then
        #expect(result != nil)
        #expect(result?.spent == Decimal(string: "5.41"))
        #expect(result?.budget == Decimal(string: "20.00"))
    }

    @Test
    func `parses Extra usage cost line without dollar signs`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When
        let result = probe.parseExtraUsageCostLine("5.41 / 20.00 spent")

        // Then
        #expect(result != nil)
        #expect(result?.spent == Decimal(string: "5.41"))
        #expect(result?.budget == Decimal(string: "20.00"))
    }

    @Test
    func `returns nil for Extra usage not enabled`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When
        let costUsage = probe.extractExtraUsage(Self.maxWithExtraUsageNotEnabled)

        // Then
        #expect(costUsage == nil)
    }

    @Test
    func `returns nil when no Extra usage section`() throws {
        // Given
        let probe = ClaudeUsageProbe()
        let output = """
        Current session
        65% left
        """

        // When
        let costUsage = probe.extractExtraUsage(output)

        // Then
        #expect(costUsage == nil)
    }

    @Test
    func `parse returns snapshot with Extra usage for Pro account`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parse(Self.proWithExtraUsageOutput)

        // Then
        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20.00"))
        #expect(snapshot.quotas.count >= 1)
    }

    @Test
    func `parses resetsAt from Extra usage cost line with mid-line Resets`() throws {
        // Given — "$5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)"
        // "Resets" appears mid-line, not at the start

        // When
        let snapshot = try ClaudeUsageProbe.parse(Self.proWithExtraUsageOutput)

        // Then — resetsAt should be populated even though "Resets" is mid-line
        #expect(snapshot.costUsage?.resetsAt != nil,
                "resetsAt should be populated when 'Resets' appears mid-line in cost line")
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
    func `treats API Usage Billing with quotas as subscription account`() throws {
        // Given — header has "API Usage Billing" but no subscription-only error,
        // and the output contains real quota bars (subscription with Extra Usage credits).
        let probe = ClaudeUsageProbe()
        let output = Self.apiUsageBillingWithQuotasOutput

        // When
        let accountType = probe.detectAccountType(output)

        // Then — must NOT be .claudeApi; quota fallback defaults to .claudeMax
        #expect(accountType != .claudeApi)
        #expect(accountType == .claudeMax)
    }

    @Test
    func `parses subscription account with API Usage Billing header and Extra Usage credits`() throws {
        // When
        let snapshot = try simulateParse(text: Self.apiUsageBillingWithQuotasOutput)

        // Then — quotas parsed; no fall-through to /cost
        #expect(snapshot.accountTier == .claudeMax)
        #expect(snapshot.sessionQuota?.percentRemaining == 95) // 5% used → 95% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 81)  // 19% used → 81% remaining
    }

    @Test
    func `extractUsageError returns subscriptionRequired for /usage subscription error`() throws {
        // Given
        let probe = ClaudeUsageProbe()
        let output = "/usage is only available for subscription plans."

        // When
        let error = probe.extractUsageError(output)

        // Then
        #expect(error == .subscriptionRequired)
    }

    @Test
    func `treats Claude API with quotas as subscription account`() throws {
        // Given
        let probe = ClaudeUsageProbe()
        let output = "Sonnet 4.5 · Claude API"

        // When
        let accountType = probe.detectAccountType(output)

        // Then - Should NOT be treated as .claudeApi (which is for pay-as-you-go)
        // Should default to .claudeMax since it has quota data
        #expect(accountType == .claudeMax)
    }

    @Test
    func `parses Claude API account with quotas successfully`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parse(Self.claudeApiWithQuotasOutput)

        // Then - Should parse quotas, not throw subscriptionRequired
        #expect(snapshot.accountTier == .claudeMax) // Defaults to Max for API accounts with quotas
        #expect(snapshot.sessionQuota != nil)
        #expect(snapshot.sessionQuota?.percentRemaining == 95) // 5% used = 95% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 81) // 19% used = 81% remaining
        #expect(snapshot.quota(for: .modelSpecific("sonnet"))?.percentRemaining == 93) // 7% used = 93% remaining
    }

    @Test
    func `detects subscription required error for API billing accounts`() throws {
        // Given
        let output = Self.apiUsageBillingOutput

        // When & Then
        #expect(throws: ProbeError.subscriptionRequired) {
            try simulateParse(text: output)
        }
    }

    // MARK: - /cost Command Parsing

    static let costCommandOutput = """
    Total cost:            $0.55
    Total duration (API):  6m 19.7s
    Total duration (wall): 6h 33m 10.2s
    Total code changes:    0 lines added, 0 lines removed
    """

    static let costCommandOutputLargeCost = """
    Total cost:            $1,234.56
    Total duration (API):  2h 30m 45.5s
    Total duration (wall): 48h 15m 30.2s
    Total code changes:    1500 lines added, 200 lines removed
    """

    @Test
    func `parses cost command output total cost`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parseCost(Self.costCommandOutput)

        // Then
        #expect(snapshot.accountTier == .claudeApi)
        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "0.55"))
        #expect(snapshot.costUsage?.budget == nil)
        #expect(snapshot.costUsage?.kind == .apiCost)
        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `parses cost command output API duration`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parseCost(Self.costCommandOutput)

        // Then
        // 6m 19.7s = 6*60 + 19.7 = 379.7 seconds
        #expect(snapshot.costUsage?.apiDuration ?? 0 > 379)
        #expect(snapshot.costUsage?.apiDuration ?? 0 < 380)
    }

    @Test
    func `parses cost command with large cost and commas`() throws {
        // When
        let snapshot = try ClaudeUsageProbe.parseCost(Self.costCommandOutputLargeCost)

        // Then
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "1234.56"))
    }

    @Test
    func `extracts cost value from total cost line`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When & Then
        #expect(probe.extractCostValue("Total cost:            $0.55") == Decimal(string: "0.55"))
        #expect(probe.extractCostValue("Total cost: $1,234.56") == Decimal(string: "1234.56"))
        #expect(probe.extractCostValue("Total cost:   0.00") == Decimal(string: "0.00"))
    }

    @Test
    func `extracts API duration from duration line`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When
        let duration = probe.extractApiDuration("Total duration (API):  6m 19.7s")

        // Then - 6*60 + 19.7 = 379.7
        #expect(duration > 379)
        #expect(duration < 380)
    }

    @Test
    func `parses duration string with hours minutes seconds`() throws {
        // Given
        let probe = ClaudeUsageProbe()

        // When & Then
        #expect(probe.parseDurationString("6m 19.7s") > 379) // 6*60 + 19.7
        let twoHours30Min: TimeInterval = 2 * 3600 + 30 * 60
        #expect(probe.parseDurationString("2h 30m") == twoHours30Min)
        #expect(probe.parseDurationString("1h") == 3600)
        #expect(probe.parseDurationString("45s") == 45)
        let expected: TimeInterval = 2 * 3600 + 30 * 60 + 45
        #expect(probe.parseDurationString("2h 30m 45.5s") > expected)
    }

     // MARK: - SwiftTerm Terminal Rendering Tests

    @Test
    func `TerminalRenderer properly handles cursor movements`() throws {
        // Given - text with cursor movement sequences
        let renderer = TerminalRenderer()
        let input = "Hello\u{1B}[5CWorld"  // "Hello" + move 5 columns right + "World"

        // When
        let rendered = renderer.render(input)

        // Then - should render with proper spacing
        #expect(rendered.contains("Hello") && rendered.contains("World"))
    }

    @Test
    func `TerminalRenderer handles ANSI color codes`() throws {
        // Given - text with ANSI color codes
        let renderer = TerminalRenderer()
        let input = "\u{1B}[32mGreen\u{1B}[0m Normal"  // Green colored text + reset + normal

        // When
        let rendered = renderer.render(input)

        // Then - colors are stripped, text is preserved
        #expect(rendered.contains("Green") && rendered.contains("Normal"))
    }

    @Test
    func `TerminalRenderer includes content scrolled into scrollback`() throws {
        // Given - more lines than the terminal is tall (50 rows), so early
        // lines scroll out of the visible screen into scrollback
        let renderer = TerminalRenderer()
        let input = (1...80).map { "line \($0)" }.joined(separator: "\n")

        // When
        let rendered = renderer.render(input)

        // Then - both the scrolled-off top and the visible bottom survive
        #expect(rendered.contains("line 1\n"))
        #expect(rendered.contains("line 80"))
    }

    @Test
    func `parses usage sections that scrolled off the visible screen`() throws {
        // Given - the CLI /usage screen grew past 50 rows (usage-contribution
        // report), pushing the quota sections above the visible screen
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

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 39)
        #expect(snapshot.weeklyQuota?.percentRemaining == 82)
        #expect(snapshot.quota(for: .modelSpecific("fable"))?.percentRemaining == 68)
    }

    @Test
    func `parses clean terminal output with proper structure`() throws {
        // Given - clean terminal output as rendered by SwiftTerm
        let output = """
        Opus 4.5 · Claude Max · user@example.com's Organization

        Current session
        ████████                                         20% used
        Resets 6pm (Asia/Shanghai)

        Current week (all models)
        ███████████▌                                     23% used
        Resets Jan 15, 4pm (Asia/Shanghai)
        """

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then
        #expect(snapshot.sessionQuota != nil)
        #expect(snapshot.sessionQuota?.percentRemaining == 80) // 20% used = 80% remaining
        #expect(snapshot.weeklyQuota?.percentRemaining == 77)  // 23% used = 77% remaining
    }

    // MARK: - Terminal Rendering Deduplication

    @Test
    func `handles duplicated reset text from terminal redraw artifact`() throws {
        // Given - terminal rendering artifact where cursor misalignment causes
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

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then — quotas should parse successfully with clean reset text
        let session = snapshot.sessionQuota
        #expect(session != nil)
        #expect(session?.resetsAt != nil, "resetsAt should be populated despite duplicated text")
        #expect(session?.resetText?.contains("Resets 4:59pm") == true)
        // Should NOT contain the duplication
        #expect(session?.resetText?.components(separatedBy: "Resets").count == 2,
                "resetText should contain 'Resets' exactly once (prefix + content)")

        let weekly = snapshot.weeklyQuota
        #expect(weekly != nil)
        #expect(weekly?.resetsAt != nil, "weekly resetsAt should be populated despite duplicated text")
    }

    @Test
    func `extractReset returns clean text when line has duplicate from terminal redraw`() throws {
        // Given
        let probe = ClaudeUsageProbe()
        let text = """
        Current session
        ████ 6% used
        Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)
        """

        // When
        let result = probe.extractReset(labelSubstring: "Current session", text: text)

        // Then — should return deduplicated text
        let unwrapped = try #require(result)
        let resetsCount = unwrapped.components(separatedBy: "Resets").count - 1
        #expect(resetsCount == 1, "Should contain 'Resets' exactly once, got \(resetsCount) in: \(unwrapped)")
    }

    // MARK: - Helper

    private func simulateParse(text: String) throws -> UsageSnapshot {
        try ClaudeUsageProbe.parse(text)
    }
}
