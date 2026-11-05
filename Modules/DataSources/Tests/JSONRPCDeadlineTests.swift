import Foundation
import Testing
@testable import DataSources

/// When a JSON-RPC exchange runs out of time (#517, #685), worked out at
/// given instants rather than waited for: the fetch's own tests time a run
/// in a suite that runs every test at once, so they can only bound it loosely.
/// The seconds are ones a `Double` holds exactly, so the instants compare equal.
@Suite
struct JSONRPCDeadlineTests {

    private let started = ContinuousClock.now

    @Test
    func `should end at the timeout plus the time to start while the CLI hasn't answered`() {
        let deadline = RPCDeadline(timeout: 0.25, startAllowance: 120, startedAt: started)

        #expect(deadline.end == started + .milliseconds(120_250))
    }

    @Test
    func `should end at the timeout once the CLI first answers, however long it may take to start`() {
        let deadline = RPCDeadline(timeout: 0.25, startAllowance: 120, startedAt: started)

        deadline.answered(at: started + .seconds(5))

        #expect(deadline.end == started + .milliseconds(5_250))
    }

    @Test
    func `should count the timeout from the first answer, not a later one`() {
        let deadline = RPCDeadline(timeout: 0.25, startAllowance: 120, startedAt: started)

        deadline.answered(at: started + .seconds(5))
        deadline.answered(at: started + .seconds(5.125))

        #expect(deadline.end == started + .milliseconds(5_250))
    }

    @Test
    func `should never end past the timeout plus the time to start, however late the first answer`() {
        let deadline = RPCDeadline(timeout: 0.25, startAllowance: 120, startedAt: started)

        deadline.answered(at: started + .seconds(120.125))

        #expect(deadline.end == started + .milliseconds(120_250))
    }

    @Test
    func `should end at the timeout when the host allows no time to start, or a negative one`() {
        #expect(RPCDeadline(timeout: 15, startAllowance: 0, startedAt: started).end == started + .seconds(15))
        #expect(RPCDeadline(timeout: 15, startAllowance: -5, startedAt: started).end == started + .seconds(15))
    }
}
