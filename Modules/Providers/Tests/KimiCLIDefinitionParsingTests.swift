import Testing
import Providers
import DataSources
import Foundation
import Quotas

@Suite("Kimi CLI /usage")
struct KimiCLIDefinitionParsingTests {

    // MARK: - Sample Output

    private static let fullOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
    │  5h limit      ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 4h 22m)      │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    private static let partialUsageOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit  ━━━━━━━━━━━━━━░░░░░░  75% left  (resets in 5d 12h 30m)   │
    │  5h limit      ━━━━━━━░░░░░░░░░░░░░  30% left  (resets in 2h 10m)       │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    private static let weeklyOnlyOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    /// Real CLI output has no progress bar characters — just whitespace
    private static let noProgressBarOutput = """
    ╭─────────────────────────────── API Usage ───────────────────────────────╮
    │  Weekly limit                        100% left  (resets in 6d 22h 55m)  │
    │  5h limit                            100% left  (resets in 3h 55m)      │
    ╰─────────────────────────────────────────────────────────────────────────╯
    """

    /// kimi CLI >= 0.36 reports "% used" without parentheses around the reset text
    private static let usedFormatOutput = """
      ╭ Usage ───────────────────────────────────────────────────────────╮
      │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
      │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
      ╰──────────────────────────────────────────────────────────────────╯
    """

    /// The TUI redraws the usage panel, emitting each quota line more than once
    private static let redrawnOutput = """
    │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
    │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
    │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
    │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
    """

    /// kimi CLI 2.x restructured the panel: Session usage / Context window sections,
    /// and the plan quota is "Monthly limit" (new plans dropped the weekly window).
    /// Captured from kimi CLI 2.1.1.
    private static let cli2xOutput = """
      ╭ Usage ────────────────────────────────────────────────────────────────╮
      │ Session usage                                                         │
      │   No token usage recorded yet.                                        │
      │                                                                       │
      │ Context window                                                        │
      │   ░░░░░░░░░░░░░░░░░░░░      0%  (0 / 1M)                              │
      │                                                                       │
      │ Plan usage                                                            │
      │   5h limit       ░░░░░░░░░░░░░░░░░░░░  0% used  resets in 2h 41m      │
      │   Monthly limit  ░░░░░░░░░░░░░░░░░░░░  2% used  resets in 24d 16h 42m │
      │                  kimi 2% · code 0%                                    │
      ╰───────────────────────────────────────────────────────────────────────╯
    """

    // MARK: - Full Output Parsing

    @Test
    func `should show two quotas when the CLI prints a weekly and a 5-hour limit`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.fullOutput)

        #expect(snapshot.providerId == "kimi")
        #expect(snapshot.quotas.count == 2)
    }

    @Test
    func `should show the weekly quota full when the CLI prints 100% left`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.fullOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly != nil)
        #expect(weekly?.percentRemaining == 100.0)
    }

    @Test
    func `should show the session full when the CLI prints 100% left on the 5-hour limit`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.fullOutput)
        let session = snapshot.quota(for: .session)

        #expect(session != nil)
        #expect(session?.percentRemaining == 100.0)
    }

    // MARK: - Partial Usage Parsing

    @Test
    func `should show 75% of the weekly quota left when the CLI prints 75% left`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.partialUsageOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly != nil)
        #expect(weekly?.percentRemaining == 75.0)
    }

    @Test
    func `should show 30% of the session left when the CLI prints 30% left`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.partialUsageOutput)
        let session = snapshot.quota(for: .session)

        #expect(session != nil)
        #expect(session?.percentRemaining == 30.0)
    }

    // MARK: - Weekly Only

    @Test
    func `should show only the weekly quota when the CLI prints no 5-hour limit`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.weeklyOnlyOutput)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quota(for: .weekly) != nil)
        #expect(snapshot.quota(for: .session) == nil)
    }

    // MARK: - No Progress Bar (Real CLI Output)

    @Test
    func `should show both quotas when the CLI prints no progress bars`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.noProgressBarOutput)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 100.0)
        #expect(snapshot.quota(for: .session)?.percentRemaining == 100.0)
    }

    // MARK: - Used Format (kimi CLI >= 0.36)

    @Test
    func `should show what is left when the CLI prints the percent used`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.usedFormatOutput)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 10.0)
        #expect(snapshot.quota(for: .session)?.percentRemaining == 88.0)
    }

    @Test
    func `should show when each quota resets when the CLI prints the reset without parentheses`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.usedFormatOutput)

        #expect(snapshot.quota(for: .weekly)?.resetText == "Resets in 35m")
        #expect(snapshot.quota(for: .session)?.resetText == "Resets in 3h 35m")
    }

    @Test
    func `should reset the session in 3h 35m when the CLI prints the percent used and resets in 3h 35m`() throws {
        let now = Date()
        let snapshot = try KimiDefinitionFixtures.cli(Self.usedFormatOutput)
        let session = snapshot.quota(for: .session)

        #expect(session?.resetsAt != nil)
        if let resetsAt = session?.resetsAt {
            let diff = resetsAt.timeIntervalSince(now)
            // 3h 35m = 12900s — allow 60s tolerance
            #expect(diff > 12840)
            #expect(diff < 12960)
        }
    }

    @Test
    func `should show nothing left when the CLI prints 100% used`() throws {
        let depleted = """
        │   Weekly limit  ████████████████████  100% used  resets in 35m    │
        """
        let snapshot = try KimiDefinitionFixtures.cli(depleted)

        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 0.0)
    }

    // MARK: - Redrawn Panels

    @Test
    func `should show each quota once when the CLI redraws the usage panel`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.redrawnOutput)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 10.0)
        #expect(snapshot.quota(for: .session)?.percentRemaining == 88.0)
    }

    // MARK: - CLI 2.x Layout (Monthly plan quota)

    @Test
    func `should show the session and the monthly quota when CLI 2.x prints its plan usage`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.cli2xOutput)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quota(for: .session)?.percentRemaining == 100.0)
        #expect(snapshot.quota(for: .timeLimit("Monthly"))?.percentRemaining == 98.0)
    }

    @Test
    func `should show no quota for the context window or the per-model split when CLI 2.x prints them`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.cli2xOutput)

        // "Context window … 0%  (0 / 1M)" and "kimi 2% · code 0%" must not become quotas
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas.contains { $0.quotaType == .weekly } == false)
    }

    @Test
    func `should show when the session and the monthly quota reset when CLI 2.x prints them`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.cli2xOutput)

        #expect(snapshot.quota(for: .session)?.resetText == "Resets in 2h 41m")
        #expect(snapshot.quota(for: .timeLimit("Monthly"))?.resetText == "Resets in 24d 16h 42m")
    }

    @Test
    func `should treat the monthly quota as a 30-day window when CLI 2.x prints a monthly limit`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.cli2xOutput)
        let monthly = snapshot.quota(for: .timeLimit("Monthly"))

        #expect(monthly?.quotaType.conventionalWindow == .days(30))
    }

    @Test
    func `should measure the monthly window as the month before its reset on the person's clock`() throws {
        let calendar = Zones.losAngelesCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 12)))
        let monthly = try #require(try KimiDefinitionFixtures.cli(Self.cli2xOutput, in: Zones.losAngeles, now: now)
            .quota(for: .timeLimit("Monthly")))
        let reset = try #require(monthly.resetsAt)
        let monthBefore = try #require(calendar.date(byAdding: .month, value: -1, to: reset))
        // Los Angeles moves its clocks on 2026-03-08, inside that month.
        #expect(monthly.windowDuration == reset.timeIntervalSince(monthBefore))
        #expect(monthly.windowDuration == TimeInterval(28 * 86400 - 3600))
    }

    @Test
    func `should start the monthly window at the hour the clocks skip, moved forward as the Mac did`() throws {
        // Resets 2026-04-08 02:30 PDT; a month before, 02:30 on 03-08 never
        // happened in Los Angeles, so the window starts at 03:30 PDT.
        let now = Date(timeIntervalSince1970: 1_773_506_880)
        let monthly = try #require(try KimiDefinitionFixtures.cli(Self.cli2xOutput, in: Zones.losAngeles, now: now)
            .quota(for: .timeLimit("Monthly")))
        #expect(monthly.resetsAt == Date(timeIntervalSince1970: 1_775_640_600))
        #expect(monthly.windowDuration == TimeInterval(31 * 86400 - 3600))
    }

    // MARK: - Reset Time Parsing

    @Test
    func `should reset the weekly quota in 6d 23h 22m when the CLI says so`() throws {
        let now = Date()
        let snapshot = try KimiDefinitionFixtures.cli(Self.fullOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly?.resetsAt != nil)
        if let resetsAt = weekly?.resetsAt {
            let diff = resetsAt.timeIntervalSince(now)
            // 6d 23h 22m = 6*86400 + 23*3600 + 22*60 = 602520s — allow 60s tolerance
            #expect(diff > 602460)
            #expect(diff < 602580)
        }
    }

    @Test
    func `should reset the session in 4h 22m when the CLI says so`() throws {
        let now = Date()
        let snapshot = try KimiDefinitionFixtures.cli(Self.fullOutput)
        let session = snapshot.quota(for: .session)

        #expect(session?.resetsAt != nil)
        if let resetsAt = session?.resetsAt {
            let diff = resetsAt.timeIntervalSince(now)
            // 4h 22m ≈ 15720s — allow 60s tolerance
            #expect(diff > 15660)
            #expect(diff < 15780)
        }
    }

    @Test
    func `should show the weekly reset as the CLI prints it`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.fullOutput)
        let weekly = snapshot.quota(for: .weekly)

        #expect(weekly?.resetText == "Resets in 6d 23h 22m")
    }

    // MARK: - Reset Duration Helper

    @Test
    func `should reset in days, hours and minutes when the CLI gives all three`() {
        let now = Date()
        let date = KimiDefinitionFixtures.reset("6d 23h 22m")

        #expect(date != nil)
        if let date {
            let diff = date.timeIntervalSince(now)
            let expected = 6.0 * 86400 + 23.0 * 3600 + 22.0 * 60
            #expect(abs(diff - expected) < 2)
        }
    }

    @Test
    func `should reset in hours and minutes when the CLI gives no days`() {
        let now = Date()
        let date = KimiDefinitionFixtures.reset("4h 22m")

        #expect(date != nil)
        if let date {
            let diff = date.timeIntervalSince(now)
            let expected = 4.0 * 3600 + 22.0 * 60
            #expect(abs(diff - expected) < 2)
        }
    }

    @Test
    func `should reset in minutes when the CLI gives only minutes`() {
        let now = Date()
        let date = KimiDefinitionFixtures.reset("30m")

        #expect(date != nil)
        if let date {
            let diff = date.timeIntervalSince(now)
            #expect(abs(diff - 1800) < 2)
        }
    }

    @Test
    func `should reset in seconds when the CLI gives only seconds`() {
        let now = Date()
        let date = KimiDefinitionFixtures.reset("45s")

        #expect(date != nil)
        if let date {
            let diff = date.timeIntervalSince(now)
            #expect(abs(diff - 45) < 2)
        }
    }

    @Test
    func `should show a reset time when the session resets within seconds`() throws {
        let secondsReset = """
        │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 45s │
        """
        let snapshot = try KimiDefinitionFixtures.cli(secondsReset)
        let session = snapshot.quota(for: .session)

        #expect(session?.percentRemaining == 88.0)
        #expect(session?.resetText == "Resets in 45s")
        #expect(session?.resetsAt != nil)
    }

    @Test
    func `should have no reset time when the CLI gives no reset`() {
        let date = KimiDefinitionFixtures.reset("")
        #expect(date == nil)
    }

    // MARK: - Error Cases

    @Test
    func `should fail to read usage when the CLI prints nothing`() {
        #expect(throws: UsageError.self) {
            try KimiDefinitionFixtures.cli("")
        }
    }

    @Test
    func `should fail to read usage when the CLI prints no usage panel`() {
        #expect(throws: UsageError.self) {
            try KimiDefinitionFixtures.cli("This is not a valid usage output")
        }
    }

    @Test
    func `should fail to read usage when the CLI prints a limit with no percentage`() {
        let noPercent = """
        ╭──── API Usage ────╮
        │  Weekly limit  ━━━━━━━━━━━  no data  │
        ╰──────────────────╯
        """

        #expect(throws: UsageError.self) {
            try KimiDefinitionFixtures.cli(noPercent)
        }
    }

    // MARK: - Provider ID

    @Test
    func `should report the usage as Kimi's`() throws {
        let snapshot = try KimiDefinitionFixtures.cli(Self.fullOutput)
        #expect(snapshot.providerId == "kimi")
    }
}

/// What `kimi` prints for /usage when it isn't signed in (captured live).
@Suite
struct KimiCLISignedOutTests {
    @Test func `should ask the person to sign in, not show "no quota data", when the CLI is signed out`() {
        let screen = """
        hanrenwei@Probe💫 /usage
        Authorization failed. Please check your API key.
        """
        #expect(throws: UsageError.sessionExpired(hint: "Run `kimi` and sign in with /login.")) {
            try KimiDefinitionFixtures.cli(screen)
        }
    }
}
