import Foundation
import Mockable

/// A JavaScript engine, for a `script` mapping (MODULAR_DESIGN §6). Each run
/// gets a fresh context with no file, network or process access: a mapping
/// script turns text into numbers and nothing else. There is one, QuickJS, on
/// every platform (#570); the port is here so a test can hand a mapping its answer.
@Mockable
protocol ScriptEngine: Sendable {
    /// Loads `scripts` in order into a fresh context that holds `strings` as
    /// global text and `functions` as global functions from text to a number
    /// or `null`, then evaluates `expression`. Answers its value as text, or
    /// `nil` when it is `undefined`.
    ///
    /// `Date`'s local time is `localTime`, the person's zone from the
    /// `TimeZone` port (#567), never the engine's own: `new Date(y, m, d)`,
    /// `getHours()`, the setters, a date-time text with no zone and
    /// `toString()` read the person's clock on every platform, so a script
    /// is plain JavaScript and never learns which one it runs on. A clock
    /// time the zone skips moves forward by the gap; one it repeats is its
    /// first instant.
    ///
    /// Throws `ScriptEngineError.load` when a script throws while loading,
    /// and `.run` when `expression` throws. A run that doesn't finish in
    /// time, or outgrows its memory, throws the same way: the mapping fails
    /// and the process is unaffected (#573).
    func evaluate(_ expression: String, after scripts: [String], strings: [String: String],
                  functions: [String: ScriptFunction], localTime: TimeZone) throws -> String?
}

/// A host function a script may call: text in, a number or `null` out.
typealias ScriptFunction = @Sendable (String) -> Double?

/// What a script threw, as the engine reports it.
enum ScriptEngineError: Error, Equatable {
    case load(String)
    case run(String)
}
