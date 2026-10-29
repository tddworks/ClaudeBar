import Quotas
import DataSources
import Providers
import Foundation

public protocol Clock: Sendable {
    func sleep(for duration: Duration) async throws
    func sleep(nanoseconds: UInt64) async throws
}
