import SwiftUI
import Testing
import Domain
@testable import ClaudeBar

/// Platformer's runner: how it moves for each status, and that no other
/// theme has one.
@MainActor
@Suite
struct GroundRunnerTests {
    @Test func `should stroll when healthy, walk on a warning, run when low and fall when empty`() throws {
        let runner = try #require(PlatformerTheme().runner)
        #expect(runner.pace(for: .healthy) == .stroll)
        #expect(runner.pace(for: .warning) == .walk)
        #expect(runner.pace(for: .critical) == .run)
        #expect(runner.pace(for: .depleted) == .fall)
    }

    @Test func `should sweat only while running`() {
        #expect(RunnerPace.run.sweats)
        #expect(!RunnerPace.walk.sweats)
        #expect(!RunnerPace.stroll.sweats)
    }

    @Test func `should run faster than it walks and walk faster than it strolls`() {
        #expect(RunnerPace.run.pointsPerSecond > RunnerPace.walk.pointsPerSecond)
        #expect(RunnerPace.walk.pointsPerSecond > RunnerPace.stroll.pointsPerSecond)
        #expect(RunnerPace.fall.pointsPerSecond == 0)
    }

    @Test func `should give the runner a lane above Platformer's floor`() throws {
        #expect(try #require(PlatformerTheme().runner).laneHeight == 48)
    }

    @Test func `should keep the runner when the person picks their own status colours`() {
        let theme = ThemeRegistry.shared.resolveTheme(
            for: "platformer",
            systemColorScheme: .light,
            statusColors: StatusColorPolicy(overrides: StatusColorOverrides(healthy: RGBColorValue(red: 0, green: 0, blue: 1)), highContrastEnabled: false)
        )
        #expect(theme.runner?.pace(for: .critical) == .run)
    }

    @Test(arguments: ["light", "dark", "system", "cli", "christmas", "pop"])
    func `should give no other theme a runner`(id: String) throws {
        #expect(try #require(ThemeRegistry.shared.theme(for: id)).runner == nil)
    }

    @Test func `should take the runner off the floor when the person turns it off`() {
        let theme = ThemeRegistry.shared.resolveTheme(for: "platformer", systemColorScheme: .light, showsRunner: false)
        #expect(theme.runner == nil)
        // The rest of the level stays.
        #expect(theme.headerStyle == .scoreLine)
        #expect(theme.groundHeight == 36)
    }

    @Test func `should keep the runner off with Classic text and the person's own status colours`() {
        let theme = ThemeRegistry.shared.resolveTheme(
            for: "platformer",
            systemColorScheme: .light,
            statusColors: StatusColorPolicy(overrides: StatusColorOverrides(healthy: RGBColorValue(red: 0, green: 0, blue: 1)), highContrastEnabled: false),
            textStyle: .classic,
            showsRunner: false
        )
        #expect(theme.runner == nil)
        #expect(theme.customFontName == nil)
    }

    @Test func `should keep the runner with Classic text while it is on`() {
        let theme = ThemeRegistry.shared.resolveTheme(for: "platformer", systemColorScheme: .light, textStyle: .classic)
        #expect(theme.runner != nil)
    }

    @Test func `should bring the runner back when the person turns it on again`() {
        #expect(PlatformerTheme().walking(false).walking(true).runner != nil)
    }

}

/// Where the runner is and what it is doing, moment to moment.
@Suite
struct RunnerLevelTests {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let width: CGFloat = 300

    private func level(at x: CGFloat = 50) -> RunnerLevel {
        let level = RunnerLevel(spriteWidth: 24, x: x)
        level.advance(to: start, pace: .walk, width: width)
        return level
    }

    @Test func `should move along the floor at its pace`() {
        let level = level()
        level.advance(to: start + 0.05, pace: .walk, width: width)
        #expect(abs(level.x - (50 + RunnerPace.walk.pointsPerSecond * 0.05)) < 0.001)
        #expect(level.facing == .right)
    }

    @Test func `should turn around at the right end of the lane`() {
        let level = level(at: width - 24 - 7)
        level.advance(to: start + 0.1, pace: .run, width: width)
        #expect(level.facing == .left)
        #expect(level.x <= width - 24 - RunnerLevel.margin)
    }

    @Test func `should turn around at the left end of the lane`() {
        let level = level(at: 300 - 24 - 6)
        level.advance(to: start + 0.1, pace: .run, width: width)   // turns left
        for step in 1...200 {
            level.advance(to: start + 0.1 + Double(step) * 0.1, pace: .run, width: width)
        }
        #expect(level.x >= RunnerLevel.margin)
    }

    @Test func `should not leap across the lane after the popover was closed for a while`() {
        let level = level()
        level.advance(to: start + 600, pace: .run, width: width)
        #expect(level.x <= 50 + RunnerPace.run.pointsPerSecond * RunnerLevel.longestStep)
    }

    @Test func `should stand still with Reduce motion`() {
        let level = level()
        level.advance(to: start + 0.05, pace: .run, width: width, reduceMotion: true)
        #expect(level.x == 50)
    }

    @Test func `should jump when a refresh finishes and land again`() {
        let level = level()
        level.celebrate(at: start)
        level.advance(to: start + 0.2, pace: .walk, width: width)
        #expect(level.lift > 0)
        level.advance(to: start + 1, pace: .walk, width: width)
        #expect(level.lift == 0)
    }

    @Test func `should pop a coin over its head after a refresh, then let it go`() {
        let level = level()
        level.celebrate(at: start)
        #expect(level.coinRise(at: start + 0.1) != nil)
        #expect(level.coinRise(at: start + 2) == nil)
    }

    @Test func `should show the coin without a jump with Reduce motion`() {
        let level = level()
        level.celebrate(at: start, reduceMotion: true)
        level.advance(to: start + 0.2, pace: .walk, width: width, reduceMotion: true)
        #expect(level.lift == 0)
        #expect(level.coinRise(at: start + 0.2) == 0)
    }

    @Test func `should fall into a pit and say GAME OVER when the quota is empty`() {
        let level = level()
        level.advance(to: start + 0.1, pace: .fall, width: width)    // it stops
        level.advance(to: start + 0.6, pace: .fall, width: width)    // the pit opens
        #expect(level.pit != nil)
        #expect(!level.isGameOver)
        level.advance(to: start + 3, pace: .fall, width: width)
        #expect(level.isGameOver)
    }

    @Test func `should skip the fall to GAME OVER with Reduce motion`() {
        let level = level()
        level.advance(to: start + 0.1, pace: .fall, width: width, reduceMotion: true)
        #expect(level.isGameOver)
    }

    @Test func `should not jump once the game is over`() {
        let level = level()
        level.advance(to: start + 0.1, pace: .fall, width: width, reduceMotion: true)
        level.celebrate(at: start + 0.2)
        #expect(level.coinRise(at: start + 0.3) == nil)
    }

    @Test func `should send a new runner in from the left after a reset`() {
        let level = level()
        level.advance(to: start + 0.1, pace: .fall, width: width, reduceMotion: true)
        level.advance(to: start + 0.2, pace: .stroll, width: width)
        #expect(!level.isGameOver)
        #expect(level.pit == nil)
        #expect(level.x < 0)
        #expect(level.facing == .right)
    }
}
