import CQuickJS
import Foundation
import Quotas

/// QuickJS (quickjs-ng, pinned in `Vendor/CQuickJS`): the one script engine,
/// the same on every platform (MODULAR_DESIGN §10, #570). Each run gets a
/// fresh runtime and context, built without QuickJS's libc, so a script
/// reaches no file, network or process: it turns text into numbers. Its
/// `Date`'s local time is the zone it is given, not the OS's (`LocalDateScript`).
struct QuickJSEngine: ScriptEngine {
    /// Each run has a thread of its own with this much stack. QuickJS's
    /// interpreter frames are large in an unoptimised build: a mapping ran
    /// out at Windows' 256 KB default.
    static let threadStack = 8 << 20
    /// Below the thread's stack, so a runaway recursion fails the mapping
    /// (a `RangeError`) instead of the process.
    static let stackLimit = 6 << 20

    func evaluate(_ expression: String, after scripts: [String], strings: [String: String],
                  functions: [String: ScriptFunction], localTime: TimeZone) throws -> String? {
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            outcome.result = Result {
                try Self.run(expression, after: scripts, strings: strings, functions: functions, localTime: localTime)
            }
            done.signal()
        }
        thread.stackSize = Self.threadStack
        thread.start()
        done.wait()
        return try outcome.result!.get()
    }

    private static func run(_ expression: String, after scripts: [String], strings: [String: String],
                            functions: [String: ScriptFunction], localTime: TimeZone) throws -> String? {
        guard let runtime = JS_NewRuntime() else { throw UsageError.executionFailed("QuickJS is unavailable") }
        defer { JS_FreeRuntime(runtime) }
        JS_SetMaxStackSize(runtime, stackLimit)
        guard let context = JS_NewContext(runtime) else { throw UsageError.executionFailed("QuickJS is unavailable") }
        defer { JS_FreeContext(context) }

        var functions = functions
        functions[LocalDateScript.offsetFunction] = { milliseconds in
            Double(milliseconds).flatMap { $0.isFinite ? $0 : nil }.map {
                Double(localTime.secondsFromGMT(for: Date(timeIntervalSince1970: $0 / 1000)))
            }
        }
        let named = functions.sorted { $0.key < $1.key }
        let host = Unmanaged.passRetained(Host(functions: named.map(\.value)))
        defer { host.release() }
        JS_SetContextOpaque(context, host.toOpaque())

        let global = JS_GetGlobalObject(context)
        defer { JS_FreeValue(context, global) }
        for (name, text) in strings {
            JS_SetPropertyStr(context, global, name, JS_NewStringLen(context, text, text.utf8.count))
        }
        for (index, function) in named.enumerated() {
            // A host function's call: its index is QuickJS's `magic`, the run's
            // functions hang off the context. Text in; a number, or `null` for none.
            let call = JS_NewCFunctionData(context, { context, _, count, arguments, index, _ in
                guard let context, let opaque = JS_GetContextOpaque(context) else { return cqjs_undefined() }
                let host = Unmanaged<Host>.fromOpaque(opaque).takeUnretainedValue()
                let argument = count > 0 ? arguments.flatMap { QuickJSEngine.text(context, $0[0]) } : nil
                guard let number = host.functions[Int(index)](argument ?? "") else { return cqjs_null() }
                return JS_NewFloat64(context, number)
            }, 1, Int32(index), 0, nil)
            JS_SetPropertyStr(context, global, function.key, call)
        }

        for script in [LocalDateScript.source] + scripts {
            let loaded = JS_Eval(context, script, script.utf8.count, "<script>", Int32(JS_EVAL_TYPE_GLOBAL))
            defer { JS_FreeValue(context, loaded) }
            if JS_IsException(loaded) { throw ScriptEngineError.load(exception(context)) }
        }
        let value = JS_Eval(context, expression, expression.utf8.count, "<expression>", Int32(JS_EVAL_TYPE_GLOBAL))
        defer { JS_FreeValue(context, value) }
        if JS_IsException(value) { throw ScriptEngineError.run(exception(context)) }
        if JS_IsUndefined(value) { return nil }
        return text(context, value)
    }

    /// What the script threw, as its `toString()` reads.
    private static func exception(_ context: OpaquePointer) -> String {
        let thrown = JS_GetException(context)
        defer { JS_FreeValue(context, thrown) }
        return text(context, thrown) ?? "an exception with no text"
    }

    private static func text(_ context: OpaquePointer, _ value: JSValue) -> String? {
        var length = 0
        guard let characters = JS_ToCStringLen(context, &length, value) else { return nil }
        defer { JS_FreeCString(context, characters) }
        return String(decoding: UnsafeRawBufferPointer(start: characters, count: length), as: UTF8.self)
    }

    private final class Host {
        let functions: [ScriptFunction]
        init(functions: [ScriptFunction]) { self.functions = functions }
    }

    /// A run's answer, handed from its thread back to the caller.
    private final class Outcome: @unchecked Sendable {
        var result: Result<String?, any Error>?
    }
}
