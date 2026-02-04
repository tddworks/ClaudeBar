import Foundation

extension URLSession: NetworkClient {
    public func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
