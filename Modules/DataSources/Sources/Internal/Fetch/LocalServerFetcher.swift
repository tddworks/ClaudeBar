import Diagnostics
import Quotas
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `localServer`: an app's own server on this machine. Its process is found by
/// name and command line, the values it started with are read from that
/// command line, and the declared paths are asked on its listening ports, on
/// 127.0.0.1 only. The same steps on every platform; the OS only answers
/// what runs, its command lines and its ports (`LocalServers`).
struct LocalServerFetcher: Fetching {
    let call: LocalServerCall
    let servers: LocalServers

    /// Running, as far as its executable's path can tell: read without
    /// starting a program, so readiness stays cheap.
    func isReady() -> Bool {
        servers.running.paths().contains { Self.isApp($0, call.process) }
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let running = await servers.commandLines.commandLines(naming: call.process.names)
            .filter { Self.isApp($0.text, call.process) }
            .sorted { $0.pid < $1.pid }
            .map { (pid: $0.pid, values: values(in: $0.text, with: credential)) }
        guard let first = running.first else {
            AppLog.probes.info("\(call.app) isn't running")
            throw CLIMissingError(cli: call.app)
        }

        // The first one, by PID, started with every required value: a CLI of
        // the same name can run beside the app without them.
        guard let (pid, values) = running.first(where: { process in call.required.allSatisfy { process.values[$0] != nil } }) else {
            if let name = call.required.first(where: { first.values[$0] == nil }) {
                // Never the value; only that it is missing.
                AppLog.probes.error("\(call.app) is running without its \(name)")
            }
            throw UsageError.authenticationRequired
        }

        var tries = await servers.ports.ports(of: pid).map { ("https", $0) }
        if let name = call.plainHTTPPort, let port = values[name].flatMap(Int.init) { tries.append(("http", port)) }
        guard !tries.isEmpty else { throw UsageError.executionFailed("\(call.app) isn't listening on any port") }

        for (scheme, port) in tries {
            for path in call.paths {
                if let response = await ask("\(scheme)://127.0.0.1:\(port)\(path)", with: values) { return response }
            }
        }
        throw UsageError.executionFailed("Could not connect to \(call.app)")
    }

    /// What a process was started with, read from its command line; the
    /// credential's own values come first.
    private func values(in commandLine: String, with credential: Credential?) -> Credential {
        var values = credential ?? Credential([:])
        for (name, pattern) in call.values {
            if let value = Self.firstGroup(pattern, in: commandLine), values[name] == nil { values[name] = value }
        }
        return values
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
        guard let (data, response) = try? await servers.network.request(request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
        return Response(status: 200, headers: headers, body: data)
    }

    /// A path's separators read as `/`, so a definition's path pattern
    /// (`/antigravity/`) matches Windows' `\` paths too.
    static func isApp(_ commandLine: String, _ process: LocalServerCall.Process) -> Bool {
        let lower = commandLine.lowercased().replacingOccurrences(of: "\\", with: "/")
        guard process.names.contains(where: { lower.contains($0.lowercased()) }) else { return false }
        return process.match.isEmpty || process.match.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
