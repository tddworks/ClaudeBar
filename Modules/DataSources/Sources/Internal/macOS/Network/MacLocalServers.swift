#if os(macOS)
import Foundation

/// What the Mac answers about an app's own server: the programs running from
/// the kernel's process table, command lines through `pgrep`, listening ports
/// through `lsof`, and one request through `URLSession` that accepts any
/// certificate on this machine and follows no redirect.
struct MacLocalServers: RunningPrograms, ProgramCommandLines, ListeningPorts, LoopbackRequests {
    /// Runs `pgrep` and `lsof`.
    private let runner: any CLIExecutor
    private let session: URLSession

    init(runner: any CLIExecutor = Processes(MacProcesses()).pipes(ProcessEnvironment())) {
        self.runner = runner
        session = URLSession(configuration: .ephemeral, delegate: LoopbackSessionDelegate(), delegateQueue: nil)
    }

    func paths() -> [String] {
        RunningProcesses.system()
    }

    func commandLines(naming names: [String]) async -> [ProgramLine] {
        let argv = Self.pgrep(names)
        // pgrep finding nothing exits 1; a runner may report that as a failure.
        let listing = (try? await runner.execute(binary: argv[0], args: Array(argv.dropFirst()), input: nil, timeout: 10,
                                                  workingDirectory: nil, autoResponses: [:]).output) ?? ""
        return listing.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
            return ProgramLine(pid: pid, text: String(parts[1]))
        }
    }

    /// `pgrep -a -lf name|name…`: every process whose command line names one,
    /// this app's ancestors included (pgrep leaves them out by default).
    func command(naming names: [String]) -> [String]? { Self.pgrep(names) }

    private static func pgrep(_ names: [String]) -> [String] {
        ["/usr/bin/pgrep", "-a", "-lf", names.joined(separator: "|")]
    }

    func ports(of pid: Int) async -> [Int] {
        let argv = Self.lsof(pid: String(pid))
        let lsof = (try? await runner.execute(binary: argv[0], args: Array(argv.dropFirst()), input: nil, timeout: 10,
                                              workingDirectory: nil, autoResponses: [:]).output) ?? ""
        // `… TCP 127.0.0.1:53421 (LISTEN)` → 53421.
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        var ports = Set<Int>()
        regex.enumerateMatches(in: lsof, range: NSRange(lsof.startIndex..., in: lsof)) { match, _, _ in
            if let match, let range = Range(match.range(at: 1), in: lsof), let port = Int(lsof[range]) { ports.insert(port) }
        }
        return ports.sorted()
    }

    func command(pid: String) -> [String]? { Self.lsof(pid: pid) }

    private static func lsof(pid: String) -> [String] {
        ["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", pid]
    }

    /// Only this machine: a host off it is refused before anything is sent.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, LoopbackClient.isLoopback(url) else { throw URLError(.unsupportedURL) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Accepts the certificate a server on this machine presents, and hands a
/// redirect back as the response.
private final class LoopbackSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard LoopbackClient.isLoopback(host: challenge.protectionSpace.host),
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#endif
