import Diagnostics
import Quotas
import Foundation

/// `http.steps` — the requests in order, each filled with the credential and
/// the values earlier steps kept. A kept value never replaces a credential
/// value. The response is every answer, by step name.
struct HTTPStepsFetcher: Fetching {
    let steps: HTTPSteps
    let network: any NetworkClient
    let now: @Sendable () -> Date

    func isReady() -> Bool { true }

    func fetch(with credential: Credential?) async throws -> Response {
        var values = credential ?? Credential([:])
        var answers: [String: Any] = [:]
        var last: Response?
        for step in steps.steps {
            if let known = step.unless, values[known] != nil {
                AppLog.probes.debug("http step \(step.name): skipped, \(known) is known")
                continue
            }
            do {
                let response = try await send(step, with: values)
                for (name, value) in Self.kept(step.keep, from: response) where values[name] == nil {
                    values[name] = value
                }
                answers[step.name] = (try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed])) ?? response.text
                last = response
            } catch {
                // A refused key or a rate limit is the whole data source's
                // business: refresh-and-retry, or the remembered wait.
                guard step.optional, !Self.concernsEveryStep(error) else { throw error }
                AppLog.probes.info("http step \(step.name): failed, going on without it")
            }
        }
        guard let last else { throw UsageError.noData }
        return Response(status: last.status, headers: last.headers,
                        body: try JSONSerialization.data(withJSONObject: answers, options: [.sortedKeys]))
    }

    /// One step, tried again on a network failure or a 5xx.
    private func send(_ step: HTTPStep, with values: Credential) async throws -> Response {
        var filled = values
        for name in step.dropEmpty where filled[name] == nil { filled[name] = "" }
        let request = Self.droppingEmpty(step.dropEmpty, from: step.request, values: values)
        let fetcher = HTTPFetcher(request: request, network: network, now: now)
        var attempt = 1
        while true {
            do {
                return try await fetcher.fetch(with: filled)
            } catch let error as HTTPStatusError where (500..<600).contains(error.status) && attempt < step.attempts {
                attempt += 1
            } catch let error as UsageError where error.tag == "executionFailed" && attempt < step.attempts {
                attempt += 1
            }
        }
    }

    private static func concernsEveryStep(_ error: Error) -> Bool {
        guard let refused = error as? HTTPStatusError else { return false }
        switch refused.reason {
        case .authenticationRequired, .rateLimited: return true
        default: return false
        }
    }

    /// The request with what came out empty left out: a JSON body key, a URL
    /// query item, or a header, filled with one of `names` that has no value.
    static func droppingEmpty(_ names: [String], from request: HTTPRequest, values: Credential) -> HTTPRequest {
        let missing = Set(names.filter { values[$0] == nil })
        guard !missing.isEmpty else { return request }
        func isMissing(_ template: String?) -> Bool {
            guard let template, template.hasPrefix("{{"), template.hasSuffix("}}") else { return false }
            return missing.contains(String(template.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces))
        }
        var url = request.url
        if var components = URLComponents(string: request.url), let items = components.queryItems {
            components.queryItems = items.filter { !isMissing($0.value) }
            url = components.string ?? request.url
        }
        var body = request.body
        if let text = request.body, var object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
            for (key, value) in object where isMissing(value as? String) { object.removeValue(forKey: key) }
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                body = String(decoding: data, as: UTF8.self)
            }
        }
        let headers = request.headers.filter { !isMissing($0.value) }
        return HTTPRequest(url: url, method: request.method, headers: headers, body: body,
                           timeout: request.timeout, acceptedStatuses: request.acceptedStatuses)
    }

    /// The values a step keeps from its response; one that is absent is left out.
    static func kept(_ keep: [String: HTTPStep.Keep], from response: Response) -> [String: String] {
        let json = try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed])
        var values: [String: String] = [:]
        for (name, rule) in keep {
            switch rule {
            case .paths(let paths):
                if let value = paths.lazy.compactMap({ JSONPath.string(JSONPath.walk(json, JSONPath.components($0))) })
                    .first(where: { !$0.isEmpty }) {
                    values[name] = value
                }
            case .pattern(let pattern):
                let text = response.text
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                    values[name] = String(text[range])
                }
            }
        }
        return values
    }
}
