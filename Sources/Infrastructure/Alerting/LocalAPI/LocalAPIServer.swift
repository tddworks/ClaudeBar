import Foundation
import Network
import Domain

/// THE ONLY SOCKET — an NWListener bound to 127.0.0.1, speaking exactly one
/// request per connection: read the request whole (or refuse it by the caps),
/// hand it to the router's answer, write the bytes back, close. No
/// keep-alive, no TLS, no non-loopback peer. All mutable state lives on one
/// serial queue — the listener's and the connections' callbacks run on it,
/// and external callers hand work to it, so nothing locks.
public final class LocalAPIServer: @unchecked Sendable {
    private var listener: NWListener?
    private let preferredPort: UInt16

    /// The router's answer, installed at start. The server never knows the
    /// routes; it moves bytes.
    private var answer: (@Sendable (LocalAPIRequestResult) async -> LocalAPIResponse)?

    /// Serial queue for all mutable state; NW callbacks run on it too.
    private let queue = DispatchQueue(label: "com.tddworks.claudebar.localapi")

    /// The port actually listening — the default, or the free port taken
    /// when the default was busy.
    public private(set) var actualPort: UInt16 = 0

    /// The port the local API listens on, on 127.0.0.1 only — beside the hook
    /// server's 19847, one number apart. If another process holds it, the
    /// server takes a free port and writes the real number to its
    /// `PortFile.localAPI`; a launcher that needs the real port reads the file.
    public static let defaultPort: UInt16 = 19848

    public init(port: UInt16 = LocalAPIServer.defaultPort) {
        self.preferredPort = port
    }

    /// Starts listening and returns when the socket is ready. The default
    /// port first; busy, a free one — the real number goes to the port file
    /// either way. The task's cancellation is honoured: the switch going off
    /// while the socket is still coming up leaves nothing listening.
    public func start(answer: @escaping @Sendable (LocalAPIRequestResult) async -> LocalAPIResponse) async throws {
        // Reset on the queue, where the listener's state lives.
        queue.async { [self] in
            stopListener()
            self.answer = answer
        }

        do {
            try await listen(on: NWEndpoint.Port(rawValue: preferredPort) ?? .any)
        } catch is CancellationError {
            return
        } catch {
            try Task.checkCancellation()
            AppLog.network.info("Local API: port \(self.preferredPort) is taken; taking a free port")
            try await listen(on: .any)
        }
        if Task.isCancelled { stop() }
    }

    /// Stops listening and removes the port file. Off means no door: no
    /// listener exists, and nothing says one does.
    public func stop() {
        queue.async { [self] in
            stopListener()
            answer = nil
            PortFile.localAPI.remove()
            AppLog.network.info("Local API stopped")
        }
    }

    // MARK: - The listener

    private func stopListener() {
        listener?.cancel()
        listener = nil
        actualPort = 0
    }

    /// Binds one listener and waits until it is ready or has failed. A busy
    /// port surfaces here as a throw, so `start` can take a free one instead.
    private func listen(on port: NWEndpoint.Port) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)
        let listener = try NWListener(using: parameters)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let actual = listener.port?.rawValue ?? self.preferredPort
                    self.queue.async {
                        self.actualPort = actual
                        self.listener = listener
                    }
                    do {
                        try PortFile.localAPI.write(Int(actual))
                        AppLog.network.info("Local API listening on 127.0.0.1:\(actual)")
                    } catch {
                        AppLog.network.error("Local API could not write its port file: \(error.localizedDescription)")
                    }
                    once.run { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    listener.cancel()
                    once.run { continuation.resume(throwing: error) }
                case .cancelled:
                    once.run { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: self.queue)
        }
    }

    // MARK: - One connection, one request

    /// Refuses any peer that is not this Mac, then reads the request whole.
    private func handle(_ connection: NWConnection) {
        guard isLoopback(connection) else {
            AppLog.network.notice("Local API refused a non-loopback peer")
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    /// The peer must be 127.0.0.1 or ::1 — the bind already keeps the door on
    /// the loopback interface; this is the second look at who knocked.
    private func isLoopback(_ connection: NWConnection) -> Bool {
        let remote = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        guard case let .hostPort(host: host, port: _) = remote else { return false }
        switch host {
        case .ipv4(let address): return address == .loopback
        case .ipv6(let address): return address == .loopback
        default: return false
        }
    }

    /// Accumulates bytes until `LocalAPIRequestFrame` says the request is
    /// whole, refused or abandoned; the rules are the frame's, the socket
    /// only carries bytes.
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let error {
                AppLog.network.debug("Local API connection error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            switch LocalAPIRequestFrame.read(buffer, peerDone: isComplete) {
            case .whole(let result): self.finish(connection, with: result)
            case .abandoned: connection.cancel()
            case .needMore: self.receive(connection, accumulated: buffer)
            }
        }
    }

    /// One answer, then the connection is gone: send, close.
    private func finish(_ connection: NWConnection, with result: LocalAPIRequestResult) {
        guard let answer else {
            connection.cancel()
            return
        }
        Task {
            let wire = LocalAPIResponseSerializer.serialize(await answer(result))
            connection.send(
                content: wire,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }
    }
}

/// Runs its body at most once — the guard behind a continuation that two
/// listener states could otherwise resume.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
