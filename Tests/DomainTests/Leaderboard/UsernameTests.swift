import Foundation
import Testing
@testable import Domain

@Suite
struct UsernameTests {
    @Test func `every name the shared rule allows is a username`() throws {
        for text in try LeaderboardVectors.load().usernames.valid {
            #expect(Username(text)?.value == text, "\(text)")
        }
    }

    @Test func `every name the shared rule refuses is not`() throws {
        for text in try LeaderboardVectors.load().usernames.invalid {
            #expect(Username(text) == nil, "\(text)")
        }
    }

    @Test func `a username reads with its at sign`() {
        #expect(Username("tokenwhale")?.description == "@tokenwhale")
    }
}
