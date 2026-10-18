import Diagnostics
import Quotas
import Foundation

/// `script` — reads a response with a JavaScript file, run on the one
/// `ScriptEngine`, QuickJS.
///
/// The script defines `read(response, context)`:
///
/// - `response` — `{ status, headers, text, json }` (`json` is the parsed body, or `null`)
/// - `context` — `{ now, timeZone, credential, values, ...files }`: epoch
///   seconds, the person's zone's identifier, the credential values the
///   definition lets it see, the settings it hands over (`values`), and each
///   declared context file's fields
///
/// and returns `{ quotas, notes, plan, cost, account }` or `{ error }` — a cost
/// may carry `lines`, its parts, and a quota its `group`, with `notes` for a
/// group that has nothing to measure. It may call
/// `humanDate(text)` for an epoch-seconds reset time, or `null`;
/// `jsonDecimal(text)` to parse JSON keeping every number as its exact text;
/// `decimalCents(amount)` to round such an amount to cents without a
/// binary float — money stays exact (CANONICAL §5, `Money`). Its `Date` is
/// on the person's clock: the engine's local time is `zone` (`ScriptEngine`).
///
/// The context has no file, network or process access: the script turns text
/// into numbers and nothing else.
struct ScriptMapper: Reading {
    let file: String
    let source: String?
    var values: [String: String] = [:]
    let engine: any ScriptEngine
    /// The person's zone: the script's `context.timeZone`, its `Date`'s
    /// local time, and where `humanDate` reads a text that names none.
    let zone: any TimeZoneSource
    let now: @Sendable () -> Date

    func read(_ response: Response, facts: MappingFacts, providerId: String) throws -> UsageSnapshot {
        guard let source else {
            throw UsageError.parseFailed("Mapping script '\(file)' is missing")
        }
        let clock = now
        let timeZone = zone.current()
        let output: String?
        do {
            output = try engine.evaluate(
                "JSON.stringify(read(JSON.parse(__input).response, JSON.parse(__input).context))",
                after: [DecimalScript.source, source],
                strings: ["__input": try Self.inputJSON(response, facts: facts, values: values, timeZone: timeZone, now: now())],
                functions: [
                    "humanDate": { HumanDate.parse($0, now: clock(), timeZone: timeZone).map { $0.timeIntervalSince1970 } },
                ],
                localTime: timeZone
            )
        } catch ScriptEngineError.load(let exception) {
            throw UsageError.parseFailed("Mapping script '\(file)' failed to load: \(exception)")
        } catch ScriptEngineError.run(let exception) {
            AppLog.probes.error("\(providerId) mapping script '\(file)' threw: \(exception)")
            throw UsageError.parseFailed(exception)
        }
        guard let text = output, let data = text.data(using: .utf8) else {
            throw UsageError.parseFailed("Mapping script '\(file)' returned nothing")
        }

        let result: ScriptOutput
        do {
            result = try JSONDecoder().decode(ScriptOutput.self, from: data)
        } catch {
            throw UsageError.parseFailed("Mapping script '\(file)' returned an unexpected shape: \(error.localizedDescription)")
        }
        return try result.snapshot(providerId: providerId, capturedAt: now())
    }

    private static func inputJSON(_ response: Response, facts: MappingFacts, values: [String: String],
                                  timeZone: TimeZone, now: Date) throws -> String {
        var context: [String: Any] = [
            "now": now.timeIntervalSince1970,
            "timeZone": timeZone.identifier,
            "credential": facts.credential,
            // A blank setting never filled its template.
            "values": values.filter { !$0.value.contains("{{") },
        ]
        for (name, fields) in facts.context {
            context[name] = fields
        }
        let input: [String: Any] = [
            "response": [
                "status": response.status.map { $0 as Any } ?? NSNull(),
                "headers": response.headers,
                "text": response.text,
                "json": (try? JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed])) ?? NSNull(),
            ],
            "context": context,
        ]
        let data = try JSONSerialization.data(withJSONObject: input)
        return String(decoding: data, as: UTF8.self)
    }
}
