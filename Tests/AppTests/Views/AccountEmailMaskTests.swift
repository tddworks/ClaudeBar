import Testing
@testable import ClaudeBar

/// *Hide account email* (#375): an email shows as its first letters with
/// the rest masked, so a screen share or screenshot doesn't give it away;
/// a name the person gave a login is theirs and shows as it is.
@Suite
struct AccountEmailMaskTests {
    @Test func `an email keeps its first letters and its ending`() {
        #expect(AccountEmailMask.masked("slamhan1987@gmail.com") == "s•••@g•••.com")
        #expect(AccountEmailMask.masked("work@corp.example.co.uk") == "w•••@c•••.uk")
    }

    @Test func `a name that isn't an email shows as it is`() {
        #expect(AccountEmailMask.masked("Work") == "Work")
        #expect(AccountEmailMask.masked("Claude") == "Claude")
    }

    @Test func `an email inside a sentence is masked where it stands`() {
        #expect(AccountEmailMask.masked("a@b.io is at 18%") == "a•••@b•••.io is at 18%")
    }

    @Test func `the menu bar's short name of a masked email stays short`() {
        let names = MenuBarAccountName.names(["claude": AccountEmailMask.masked("slamhan1987@gmail.com"),
                                              "claude.work": AccountEmailMask.masked("work@corp.com")])
        #expect(names["claude"] == "s•••")
        #expect(names["claude.work"] == "w•••")
    }
}
