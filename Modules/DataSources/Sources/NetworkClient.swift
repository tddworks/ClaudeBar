import Foundation
import Mockable

@Mockable
public protocol NetworkClient: Sendable {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse)
}
