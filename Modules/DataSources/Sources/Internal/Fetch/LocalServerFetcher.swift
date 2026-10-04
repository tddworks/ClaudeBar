import Diagnostics
import Quotas
import Foundation

/// `localServer` — an app's own server on this Mac. Its process is found by
/// name and command line, the values it started with are read from that
/// command line, and the declared paths are asked on its listening ports,
/// on 127.0.0.1 only.
struct LocalServerFetcher: Fetching {
    let call: LocalServerCall
    /// Runs `pgrep` and `lsof`.
    let commands: any CLIExecutor
    /// The loopback client: self-signed TLS accepted on 127.0.0.1 only.
    let network: any NetworkClient
    /// The executable paths of the processes running now — read without
    /// starting a process, so readiness stays cheap.
    let processPaths: @Sendable () -> [String]

    /// Running, as far as its executable's path can tell.
    func isReady() -> Bool {
        processPaths().contains { Self.isApp($0, call.process) }
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let query = Self.processQuery(call.process)
        // An empty pgrep result surfaces as a runner timeout, not "not found".
        let listing = (try? await commands.execute(binary: query[0], args: Array(query.dropFirst()), input: nil,
                                                     timeout: call.timeout, workingDirectory: nil, autoResponses: [:]).output) ?? ""
        guard let line = listing.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { Self.isApp($0, call.process) }),
              let pid = line.split(separator: " ", maxSplits: 1).first.flatMap({ Int($0) }) else {
            AppLog.probes.info("\(call.app) isn't running")
            throw CLIMissingError(cli: call.app)
        }

        var values = credential ?? Credential([:])
        for (name, pattern) in call.values {
            if let value = Self.firstGroup(pattern, in: line), values[name] == nil { values[name] = value }
        }
        for name in call.required where values[name] == nil {
            // Never the value; only that it is missing.
            AppLog.probes.error("\(call.app) is running without its \(name)")
            throw UsageError.authenticationRequired
        }

        let lsof = (try? await commands.execute(binary: "/usr/sbin/lsof", args: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)],
                                                input: nil, timeout: call.timeout, workingDirectory: nil, autoResponses: [:]).output) ?? ""
        var tries = Self.listeningPorts(in: lsof).map { ("https", $0) }
        if let name = call.plainHTTPPort, let port = values[name].flatMap(Int.init) { tries.append(("http", port)) }
        guard !tries.isEmpty else { throw UsageError.executionFailed("\(call.app) isn't listening on any port") }

        for (scheme, port) in tries {
            for path in call.paths {
                if let response = await ask("\(scheme)://127.0.0.1:\(port)\(path)", with: values) { return response }
            }
        }
        throw UsageError.executionFailed("Could not connect to \(call.app)")
    }

    /// One request; `nil` unless it answered 200.
    private func ask(_ address: String, with values: Credential) async -> Response? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = call.method
        request.timeoutInterval = call.timeout
        for (name, template) in call.headers {
            guard let value = Template.fill(template, with: values) else { return nil }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body = call.body {
            guard let filled = Template.fill(body, with: values) else { return nil }
            request.httpBody = Data(filled.utf8)
        }
        guard let (data, response) = try? await network.request(request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
        return Response(status: 200, headers: headers, body: data)
    }

    /// `pgrep -lf name|name…` — every process whose command line names one.
    static func processQuery(_ process: LocalServerCall.Process) -> [String] {
        ["/usr/bin/pgrep", "-lf", process.names.joined(separator: "|")]
    }

    static func isApp(_ commandLine: String, _ process: LocalServerCall.Process) -> Bool {
        let lower = commandLine.lowercased()
        guard process.names.contains(where: { lower.contains($0.lowercased()) }) else { return false }
        return process.match.isEmpty || process.match.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// `… TCP 127.0.0.1:53421 (LISTEN)` → 53421, each once, in order.
    static func listeningPorts(in lsof: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        var ports = Set<Int>()
        regex.enumerateMatches(in: lsof, range: NSRange(lsof.startIndex..., in: lsof)) { match, _, _ in
            if let match, let range = Range(match.range(at: 1), in: lsof), let port = Int(lsof[range]) { ports.insert(port) }
        }
        return ports.sorted()
    }
}
