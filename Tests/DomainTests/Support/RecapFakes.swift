import Foundation
@testable import Domain

/// A recap destination that keeps what it was told, so a test asserts state.
final class RecordingRecapDestination: RecapDestination, @unchecked Sendable {
    private(set) var recaps: [RecapAlert] = []

    func announce(_ recap: RecapAlert) async { recaps.append(recap) }
}

/// `alerts.recapSentAt`, kept in memory.
final class InMemoryRecapSentRepository: RecapSentRepository, @unchecked Sendable {
    var sentAt: Date?
    init(_ sentAt: Date? = nil) { self.sentAt = sentAt }
    func lastSent() -> Date? { sentAt }
    func setLastSent(_ date: Date) { sentAt = date }
}
