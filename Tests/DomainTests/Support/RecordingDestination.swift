import Foundation
@testable import Domain

/// A destination that keeps what it was told, so a test asserts state.
final class RecordingDestination: AlertDestination, @unchecked Sendable {
    private(set) var alerts: [Alert] = []

    func announce(_ alert: Alert) async { alerts.append(alert) }

    /// The quota alerts it heard, in order.
    var quotaAlerts: [QuotaAlert] {
        alerts.compactMap { if case .quota(let alert) = $0 { alert } else { nil } }
    }

    /// The status alerts it heard, in order.
    var statusAlerts: [StatusAlert] {
        alerts.compactMap { if case .status(let alert) = $0 { alert } else { nil } }
    }

    /// The signed-out alerts it heard, in order.
    var signedOutAlerts: [SignedOutAlert] {
        alerts.compactMap { if case .signedOut(let alert) = $0 { alert } else { nil } }
    }
}
