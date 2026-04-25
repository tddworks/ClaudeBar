import Foundation

public protocol Clock: Sendable {
    func sleep(for duration: TimeInterval) async throws
}
