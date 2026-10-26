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
    /// A run's time, from the start of `evaluate`: far above the slowest real
    /// mapping (one `omp` read takes about 3 ms in a release build), so only a
    /// script that never ends reaches it (#573).
    static let deadline: TimeInterval = 5
    /// A run's memory: far above a mapping's parsed answer, so only a script
    /// that grows without end reaches it, and fails instead of the process.
    static let memoryLimit = 256 << 20
    /// How long past the deadline the caller waits for the run to stop itself.
    /// QuickJS asks for the deadline once every 10,000 steps, so a loop whose
    /// every step is slow (a large `JSON.parse`, a big `BigInt`) stops long
    /// after it; the caller has its answer here instead, and the run ends on
    /// its own thread at its next check.
    static let grace: TimeInterval = 1

    func evaluate(_ expression: String, after scripts: [String], strings: [String: String],
                  functions: [String: ScriptFunction], localTime: TimeZone) throws -> String? {
        let end = DispatchTime.now().uptimeNanoseconds + UInt64(Self.deadline * 1_000_000_000)
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            outcome.result = Result {
                try Self.run(expression, after: scripts, strings: strings, functions: functions, localTime: localTime,
                             until: end, whenLoaded: { outcome.loaded = true })
            }
            done.signal()
        }
        thread.stackSize = Self.threadStack
        thread.start()
        guard done.wait(timeout: DispatchTime(uptimeNanoseconds: end) + Self.grace) == .success else {
            let interrupted = "InternalError: interrupted"
            throw outcome.loaded ? ScriptEngineError.run(interrupted) : ScriptEngineError.load(interrupted)
        }
        return try outcome.result!.get()
    }

    private static func run(_ expression: String, after scripts: [String], strings: [String: String],
                            functions: [String: ScriptFunction], localTime: TimeZone, until end: UInt64,
                            whenLoaded: () -> Void) throws -> String? {
        let deadline = Unmanaged.passRetained(Deadline(end: end))
        defer { deadline.release() }
        guard let runtime = JS_NewRuntime() else { throw UsageError.executionFailed("QuickJS is unavailable") }
        defer { JS_FreeRuntime(runtime) }
        JS_SetMaxStackSize(runtime, stackLimit)
        JS_SetMemoryLimit(runtime, memoryLimit)
        // Asked now and then while a script runs; past the deadline, QuickJS
        // throws an `InternalError: interrupted` no script can catch.
        JS_SetInterruptHandler(runtime, { _, opaque in
            guard let opaque else { return 0 }
            return DispatchTime.now().uptimeNanoseconds >= Unmanaged<Deadline>.fromOpaque(opaque).takeUnretainedValue().end ? 1 : 0
        }, deadline.toOpaque())
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
                var argument = ""
                if count > 0, let arguments {
                    // An argument that can't become text threw while it was
                    // read (interrupted, out of memory): that stays the call's
                    // answer, so a run's deadline is never lost in a host call.
                    guard let text = QuickJSEngine.text(context, arguments[0]) else { return cqjs_exception() }
                    argument = text
                }
                guard let number = host.functions[Int(index)](argument) else { return cqjs_null() }
                return JS_NewFloat64(context, number)
            }, 1, Int32(index), 0, nil)
            JS_SetPropertyStr(context, global, function.key, call)
        }

        for script in [LocalDateScript.source] + scripts {
            let loaded = JS_Eval(context, script, script.utf8.count, "<script>", Int32(JS_EVAL_TYPE_GLOBAL))
            defer { JS_FreeValue(context, loaded) }
            if JS_IsException(loaded) { throw ScriptEngineError.load(exception(context)) }
        }
        whenLoaded()
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

    /// When a run must stop, on the uptime clock, for the interrupt handler.
    private final class Deadline {
        let end: UInt64
        init(end: UInt64) { self.end = end }
    }

    /// A run's answer, handed from its thread back to the caller; read only
    /// once the run signalled, so a run the caller stopped waiting for writes
    /// it for no one. Whether its scripts had loaded is read without waiting,
    /// so it is locked.
    private final class Outcome: @unchecked Sendable {
        var result: Result<String?, any Error>?
        private let lock = NSLock()
        private var scriptsLoaded = false
        var loaded: Bool {
            get { lock.withLock { scriptsLoaded } }
            set { lock.withLock { scriptsLoaded = newValue } }
        }
    }
}
