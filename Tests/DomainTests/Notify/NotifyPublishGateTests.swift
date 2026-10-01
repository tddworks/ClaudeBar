import Testing
import Foundation
@testable import Domain

@Suite
struct NotifyPublishGateTests {
    /// Fixed on purpose: every rule below is exercised against an explicit
    /// elapsed time rather than against the machine's clock.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The shipping intervals, spelled out so a test reads as "thirty seconds
    /// is inside the minute" without a lookup elsewhere.
    private let gate = NotifyPublishGate(tileInterval: 60, gaugeInterval: 900, keepAliveInterval: 5400)

    /// A payload with either surface present. A nil argument means the user
    /// turned that surface off.
    private func payload(tile body: String?, gauge value: String?) -> NotifyPayload {
        NotifyPayload(
            tile: body.flatMap { NotifyTile(title: "ClaudeBar", body: $0, progress: 42) },
            gauge: value.flatMap { NotifyGauge(title: "ClaudeBar", value: $0, progress: 42) }
        )
    }

    /// The same, carrying the Home Screen tile as well. A real payload holds one
    /// tile value on both surfaces, so this builds them from one body too.
    private func payload(tile body: String?, gauge value: String?, screenTile screenBody: String?) -> NotifyPayload {
        NotifyPayload(
            tile: body.flatMap { NotifyTile(title: "ClaudeBar", body: $0, progress: 42) },
            gauge: value.flatMap { NotifyGauge(title: "ClaudeBar", value: $0, progress: 42) },
            screenTile: screenBody.flatMap { NotifyTile(title: "ClaudeBar", body: $0, progress: 42) }
        )
    }

    // MARK: - The first publish

    @Test
    func `a first publish writes both surfaces`() {
        let decision = gate.decide(payload: payload(tile: "42% left", gauge: "42"), since: nil, now: now)

        #expect(decision.publishesTile)
        #expect(decision.publishesGauge)
    }

    // MARK: - Nothing changed

    @Test
    func `an unchanged payload republishes nothing before the keep alive elapses`() {
        // Given the same payload as an hour ago
        let standing = payload(tile: "42% left", gauge: "42")
        let record = NotifyPublishRecord(payload: standing, tileAt: now, gaugeAt: now)

        // When
        let decision = gate.decide(payload: standing, since: record, now: now.addingTimeInterval(3600))

        // Then no request is worth making
        #expect(decision.publishesNothing)
    }

    // MARK: - The tile

    @Test
    func `a changed tile waits for the tile interval`() {
        let record = NotifyPublishRecord(payload: payload(tile: "42% left", gauge: "42"), tileAt: now, gaugeAt: now)

        let decision = gate.decide(
            payload: payload(tile: "41% left", gauge: "42"),
            since: record,
            now: now.addingTimeInterval(30)
        )

        #expect(!decision.publishesTile)
    }

    @Test
    func `a changed tile publishes once the tile interval has passed`() {
        let record = NotifyPublishRecord(payload: payload(tile: "42% left", gauge: "42"), tileAt: now, gaugeAt: now)

        let decision = gate.decide(
            payload: payload(tile: "41% left", gauge: "42"),
            since: record,
            now: now.addingTimeInterval(60)
        )

        #expect(decision.publishesTile)
    }

    @Test
    func `an unchanged tile publishes again once the keep alive interval has passed`() {
        // The gateway ends a progress-only Live Activity that has gone two
        // hours without an update, so a frozen percentage has to be refreshed
        // even when it has not moved.
        let standing = payload(tile: "42% left", gauge: "42")
        let record = NotifyPublishRecord(payload: standing, tileAt: now, gaugeAt: now)

        let decision = gate.decide(payload: standing, since: record, now: now.addingTimeInterval(5400))

        #expect(decision.publishesTile)
    }

    // MARK: - The gauge

    @Test
    func `a changed gauge waits for the gauge interval`() {
        let record = NotifyPublishRecord(payload: payload(tile: "42% left", gauge: "42"), tileAt: now, gaugeAt: now)

        let decision = gate.decide(
            payload: payload(tile: "42% left", gauge: "41"),
            since: record,
            now: now.addingTimeInterval(300)
        )

        #expect(!decision.publishesGauge)
    }

    @Test
    func `a changed gauge publishes once the gauge interval has passed`() {
        let record = NotifyPublishRecord(payload: payload(tile: "42% left", gauge: "42"), tileAt: now, gaugeAt: now)

        let decision = gate.decide(
            payload: payload(tile: "42% left", gauge: "41"),
            since: record,
            now: now.addingTimeInterval(900)
        )

        #expect(decision.publishesGauge)
    }

    @Test
    func `the keep alive does not force a gauge publish`() {
        // The keep alive exists for the Live Activity reaper. A widget iOS
        // already redraws on its own schedule gains nothing from it.
        let standing = payload(tile: "42% left", gauge: "42")
        let record = NotifyPublishRecord(payload: standing, tileAt: now, gaugeAt: now)

        let decision = gate.decide(payload: standing, since: record, now: now.addingTimeInterval(5400))

        #expect(!decision.publishesGauge)
    }

    // MARK: - The Home Screen tile

    @Test
    func `a payload with no screen tile never publishes one`() {
        let decision = gate.decide(
            payload: payload(tile: "42% left", gauge: "42", screenTile: nil),
            since: nil,
            now: now
        )

        #expect(!decision.publishesScreenTile)
        #expect(decision.publishesTile)
    }

    @Test
    func `a changed screen tile waits for its own interval`() {
        let standing = payload(tile: "42% left", gauge: "42", screenTile: "42% left")
        let record = NotifyPublishRecord(payload: standing, tileAt: now, gaugeAt: now, screenTileAt: now)

        let decision = gate.decide(
            payload: payload(tile: "41% left", gauge: "42", screenTile: "41% left"),
            since: record,
            now: now.addingTimeInterval(300)
        )

        // Nothing is pushed to a screen widget. The phone polls its list when
        // iOS redraws the tile, roughly every quarter hour, so a write five
        // minutes in is a request nobody reads.
        #expect(!decision.publishesScreenTile)
    }

    @Test
    func `a changed screen tile publishes once its own interval has passed`() {
        let standing = payload(tile: "42% left", gauge: "42", screenTile: "42% left")
        let record = NotifyPublishRecord(payload: standing, tileAt: now, gaugeAt: now, screenTileAt: now)

        let decision = gate.decide(
            payload: payload(tile: "41% left", gauge: "42", screenTile: "41% left"),
            since: record,
            now: now.addingTimeInterval(900)
        )

        #expect(decision.publishesScreenTile)
    }

    @Test
    func `an unchanged screen tile publishes again once the keep alive interval has passed`() {
        // The screen tile carries a freshness deadline the Lock Screen widget
        // does not: two hours after the last write its staleAt passes, and the
        // phone then dims the tile and says how long ago it was current rather
        // than presenting the old number as live. So a quota that simply is not
        // moving still has to be rewritten, or a correct reading goes grey.
        let standing = payload(tile: "42% left", gauge: "42", screenTile: "42% left")
        let record = NotifyPublishRecord(payload: standing, tileAt: now, gaugeAt: now, screenTileAt: now)

        let decision = gate.decide(payload: standing, since: record, now: now.addingTimeInterval(5400))

        #expect(decision.publishesScreenTile)
    }

    @Test
    func `a screen tile only publish leaves the other two surfaces showing what they are showing`() {
        // Given all three surfaces last written at the same moment
        let first = payload(tile: "42% left", gauge: "42", screenTile: "42% left")
        let second = payload(tile: "41% left", gauge: "41", screenTile: "41% left")
        let record = NotifyPublishRecord(payload: first, tileAt: now, gaugeAt: now, screenTileAt: now)

        // When only the Home Screen tile goes out, a quarter of an hour later
        let updated = record.updated(
            with: second,
            decision: NotifyPublishDecision(
                publishesTile: false,
                publishesGauge: false,
                publishesScreenTile: true
            ),
            at: now.addingTimeInterval(900)
        )

        // Then the tile and the gauge keep both their timestamps and their
        // content, because that is what the phone is still showing on them.
        // Recording the whole payload would file their unsent changes as
        // delivered and the gate would see nothing to send when their own
        // intervals came round.
        #expect(updated.payload.screenTile == second.screenTile)
        #expect(updated.screenTileAt == now.addingTimeInterval(900))
        #expect(updated.payload.tile == first.tile)
        #expect(updated.payload.gauge == first.gauge)
        #expect(updated.tileAt == now)
        #expect(updated.gaugeAt == now)
    }

    @Test
    func `a decision that writes only the screen tile does not report publishing nothing`() {
        #expect(
            !NotifyPublishDecision(
                publishesTile: false,
                publishesGauge: false,
                publishesScreenTile: true
            ).publishesNothing
        )
        #expect(!NotifyPublishDecision.nothing.publishesScreenTile)
    }

    // MARK: - Surfaces the user turned off

    @Test
    func `a payload with no tile never publishes a tile`() {
        let decision = gate.decide(payload: payload(tile: nil, gauge: "42"), since: nil, now: now)

        #expect(!decision.publishesTile)
        #expect(decision.publishesGauge)
    }

    @Test
    func `a payload with no gauge never publishes a gauge`() {
        let decision = gate.decide(payload: payload(tile: "42% left", gauge: nil), since: nil, now: now)

        #expect(!decision.publishesGauge)
        #expect(decision.publishesTile)
    }

    // MARK: - The record

    @Test
    func `a publish record carries forward the timestamp of the surface it did not write`() {
        // Given both surfaces last written at the same moment
        let record = NotifyPublishRecord(payload: payload(tile: "42% left", gauge: "42"), tileAt: now, gaugeAt: now)
        let next = payload(tile: "41% left", gauge: "41")

        // When only the tile goes out, two minutes later
        let updated = record.updated(
            with: next,
            decision: NotifyPublishDecision(publishesTile: true, publishesGauge: false),
            at: now.addingTimeInterval(120)
        )

        // Then the gauge keeps its old timestamp, so its own interval still
        // applies, and its old content, because that is what the phone is still
        // showing. Recording the unsent gauge as delivered would lose the change.
        #expect(updated.payload.tile == next.tile)
        #expect(updated.payload.gauge == record.payload.gauge)
        #expect(updated.tileAt == now.addingTimeInterval(120))
        #expect(updated.gaugeAt == now)
    }

    // MARK: - The decision

    @Test
    func `a decision that writes nothing reports publishing nothing`() {
        #expect(NotifyPublishDecision.nothing.publishesNothing)
        #expect(!NotifyPublishDecision.nothing.publishesTile)
        #expect(!NotifyPublishDecision.nothing.publishesGauge)
        #expect(NotifyPublishDecision(publishesTile: false, publishesGauge: false) == .nothing)
    }

    @Test
    func `a decision that writes one surface does not report publishing nothing`() {
        #expect(!NotifyPublishDecision(publishesTile: true, publishesGauge: false).publishesNothing)
        #expect(!NotifyPublishDecision(publishesTile: false, publishesGauge: true).publishesNothing)
    }

    // MARK: - What each surface is actually showing

    @Test
    func `a gauge held back by its interval is still sent once the interval passes`() {
        // The sequence a real publish takes: the tile moves first, on its own
        // shorter interval, while the gauge waits for its quarter hour.
        let gate = NotifyPublishGate(tileInterval: 60, gaugeInterval: 900, keepAliveInterval: 5400)
        let first = payload(tileTrailing: "2:14", gaugeValue: "42")
        let second = payload(tileTrailing: "2:13", gaugeValue: "41")

        // Given both surfaces published together
        var record = NotifyPublishRecord(payload: .empty)
            .updated(with: first, decision: NotifyPublishDecision(publishesTile: true, publishesGauge: true), at: now)

        // When a minute later both have changed, but only the tile is due
        let atOneMinute = now.addingTimeInterval(60)
        let tileOnly = gate.decide(payload: second, since: record, now: atOneMinute)
        #expect(tileOnly.publishesTile)
        #expect(tileOnly.publishesGauge == false)
        record = record.updated(with: second, decision: tileOnly, at: atOneMinute)

        // Then once the gauge's own interval has passed, its change is still
        // there to be sent. Recording the whole payload on a tile-only publish
        // would have filed the new gauge as already delivered, and the phone
        // would sit on the old value until something else happened to move it.
        let atFifteenMinutes = now.addingTimeInterval(900)
        let later = gate.decide(payload: second, since: record, now: atFifteenMinutes)

        #expect(later.publishesGauge)
    }

    @Test
    func `a surface that was not published keeps the content it is showing`() {
        let first = payload(tileTrailing: "2:14", gaugeValue: "42")
        let second = payload(tileTrailing: "2:13", gaugeValue: "41")

        let record = NotifyPublishRecord(payload: first, tileAt: now, gaugeAt: now)
            .updated(
                with: second,
                decision: NotifyPublishDecision(publishesTile: true, publishesGauge: false),
                at: now.addingTimeInterval(60)
            )

        // The record is what the phone shows, which is not the last payload built
        #expect(record.payload.tile == second.tile)
        #expect(record.payload.gauge == first.gauge)
    }

    // MARK: - Helpers

    private func payload(tileTrailing: String, gaugeValue: String) -> NotifyPayload {
        NotifyPayload(
            tile: NotifyTile(title: "ClaudeBar", progress: 42, trailing: tileTrailing),
            gauge: NotifyGauge(title: "ClaudeBar", value: gaugeValue, unit: "%", progress: 42)
        )
    }

}
