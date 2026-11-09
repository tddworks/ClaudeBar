import Foundation
import Testing
@testable import DataSources

/// When a JSON-RPC exchange runs out of time (#517, #685, #698), worked out at
/// given instants rather than waited for: the fetch's own tests time a run
/// in a suite that runs every test at once, so they can only bound it loosely.
/// The seconds are ones a `Double` holds exactly, so the instants compare equal.
@Suite
struct JSONRPCDeadlineTests {

    private let started = ContinuousClock.now

    @Test
    func `should end at the timeout plus the time to start while the CLI hasn't answered`() {
        let deadline = asked(RPCDeadline(timeout: 0.25, startAllowance: 120))

        #expect(deadline.end == started + .milliseconds(120_250))
    }

    @Test
    func `should end at the timeout once the CLI first answers, however long it may take to start`() {
        let deadline = asked(RPCDeadline(timeout: 0.25, startAllowance: 120))

        deadline.answered(at: started + .seconds(5))

        #expect(deadline.end == started + .milliseconds(5_250))
    }

    @Test
    func `should count the timeout from the first answer, not a later one`() {
        let deadline = asked(RPCDeadline(timeout: 0.25, startAllowance: 120))

        deadline.answered(at: started + .seconds(5))
        deadline.answered(at: started + .seconds(5.125))

        #expect(deadline.end == started + .milliseconds(5_250))
    }

    @Test
    func `should never end past the timeout plus the time to start, however late the first answer`() {
        let deadline = asked(RPCDeadline(timeout: 0.25, startAllowance: 120))

        deadline.answered(at: started + .seconds(120.125))

        #expect(deadline.end == started + .milliseconds(120_250))
    }

    @Test
    func `should end at the timeout when the host allows no time to start, or a negative one`() {
        #expect(asked(RPCDeadline(timeout: 15, startAllowance: 0)).end == started + .seconds(15))
        #expect(asked(RPCDeadline(timeout: 15, startAllowance: -5)).end == started + .seconds(15))
    }

    @Test
    func `should not end before the CLI is asked anything, however long the app takes to ask it`() {
        let deadline = RPCDeadline(timeout: 0.25, startAllowance: 0)

        #expect(deadline.end == nil)
    }

    @Test
    func `should count from the first time the CLI is asked, not a later request`() {
        let deadline = asked(RPCDeadline(timeout: 0.25, startAllowance: 120))

        deadline.asked(at: started + .seconds(5))

        #expect(deadline.end == started + .milliseconds(120_250))
    }

    /// The deadline, its CLI first asked at `started`.
    private func asked(_ deadline: RPCDeadline) -> RPCDeadline {
        deadline.asked(at: started)
        return deadline
    }
}
