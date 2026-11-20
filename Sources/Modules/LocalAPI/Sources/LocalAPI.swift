import Foundation
import Monitoring

/// The factory: the local API, handed out as its port.
public enum LocalAPI {
    /// The port the local API asks for first.
    public static let defaultPort = LocalAPIServer.defaultPort

    /// The port the local API listens on now, from its port file; `nil` while it is off.
    public static func port() -> Int? {
        PortFile.localAPI.read()
    }

    public static func makeServer() -> any LocalAPIServing {
        RoutedLocalAPI(server: LocalAPIServer())
    }
}

/// The server, answering through the router over the read it was given.
struct RoutedLocalAPI: LocalAPIServing {
    let server: LocalAPIServer

    func start(answering read: @escaping @MainActor @Sendable () -> Overview) async throws {
        let router = LocalAPIRouter(read: read)
        try await server.start { result in await router.answer(result) }
    }

    func stop() { server.stop() }
}
