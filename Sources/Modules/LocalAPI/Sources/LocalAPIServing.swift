import Foundation
import Monitoring

/// The local API and its MCP: read-only answers on 127.0.0.1, every one a
/// read of the *All* page's `Overview`. Off means no listener exists at all.
public protocol LocalAPIServing: Sendable {
    /// Starts listening and returns when the socket is ready; the real port
    /// goes to the port file.
    func start(answering read: @escaping @MainActor @Sendable () -> Overview) async throws
    /// Stops listening and removes the port file.
    func stop()
}
