import Testing
import Foundation
@testable import Domain

/// What the Notify! pane says when a Live Activity can't be published, and
/// whether waiting will help.
@Suite
struct NotifyPublishErrorTests {
    @Test(arguments: [
        (NotifyPublishError.notLinked, "Add your Notify! device ID and token before publishing."),
        (.rejectedCredentials, "Notify! rejected these credentials. Copy the device ID and token again from the Notify! app."),
        (.liveActivityUnavailable(""), "This device cannot show a Live Activity yet. Open the Notify! app once on the device."),
        (.liveActivityUnavailable("Live Activities are off"), "Live Activities are off"),
        (.tileGone, "The Live Activity was dismissed on the device. ClaudeBar will start a new one."),
        (.invalidPayload(""), "Notify! rejected the content of this update."),
        (.invalidPayload("title too long"), "title too long"),
        (.deliveryUnconfirmed(activityId: nil), "Notify! could not confirm the Live Activity started. ClaudeBar will check again on the next update."),
        (.transportFailed("offline"), "Could not reach Notify!: offline"),
        (.surfaceSwitchedOff(""), "Notify! has this widget switched off at the moment. ClaudeBar will try again later."),
        (.surfaceSwitchedOff("Paused by you"), "Paused by you"),
        (.unexpectedStatus(503), "Notify! answered with HTTP 503."),
        (.malformedResponse, "Notify! sent a response ClaudeBar could not read."),
    ])
    func `should tell the person what went wrong in words they can act on`(error: NotifyPublishError, message: String) {
        #expect(error.errorDescription == message)
    }

    @Test(arguments: [
        (30.0, "a minute"),
        (60.0, "a minute"),
        (300.0, "5 minutes"),
        (3540.0, "59 minutes"),
        (3599.0, "an hour"),
        (3600.0, "an hour"),
        (7200.0, "2 hours"),
    ])
    func `should say how long Notify! is waiting in minutes or hours`(seconds: TimeInterval, wait: String) {
        let error = NotifyPublishError.backoff(retryAfter: seconds, openingTheAppMayHelp: false)
        #expect(error.errorDescription == "Notify! is waiting \(wait) before another Live Activity.")
    }

    @Test
    func `should suggest opening the Notify! app when that may end the wait sooner`() {
        let error = NotifyPublishError.backoff(retryAfter: 600, openingTheAppMayHelp: true)
        #expect(error.errorDescription == "Notify! is waiting 10 minutes before another Live Activity. Opening the Notify! app on the device may clear it sooner.")
    }

    @Test
    func `should know how long to wait only when Notify! asked to wait`() {
        #expect(NotifyPublishError.backoff(retryAfter: 90, openingTheAppMayHelp: false).retryAfter == 90)
        #expect(NotifyPublishError.transportFailed("offline").retryAfter == nil)
        #expect(NotifyPublishError.notLinked.retryAfter == nil)
    }
}
