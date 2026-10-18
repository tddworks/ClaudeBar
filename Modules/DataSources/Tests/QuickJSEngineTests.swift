import Foundation
import Testing
@testable import DataSources

/// The one script engine, QuickJS, on every platform (#570): what
/// `ScriptEngine` promises a mapping, run for real.
@Suite
struct QuickJSEngineTests {
    private let engine = QuickJSEngine()

    private func run(_ expression: String, after scripts: [String] = [], strings: [String: String] = [:],
                     functions: [String: ScriptFunction] = [:], in zone: String = "Asia/Seoul") throws -> String? {
        try engine.evaluate(expression, after: scripts, strings: strings, functions: functions,
                            localTime: TimeZone(identifier: zone)!)
    }

    @Test func `should run the expression after the scripts, with the texts and functions it is given`() throws {
        let value = try run("greet(name) + ' ' + twice('21')",
                            after: ["function greet(name) { return 'hi ' + name; }"],
                            strings: ["name": "Ada"],
                            functions: ["twice": { Double($0).map { $0 * 2 } }])
        #expect(value == "hi Ada 42")
    }

    @Test func `should keep a text's every character, whatever its script`() throws {
        #expect(try run("text.length + ':' + text", strings: ["text": "한국 ✓"]) == "4:한국 ✓")
    }

    @Test func `should hand a script null when a function has no answer`() throws {
        #expect(try run("String(nothing('x') === null)", functions: ["nothing": { _ in nil }]) == "true")
    }

    @Test func `should answer nothing when the expression is undefined`() throws {
        #expect(try run("undefined") == nil)
    }

    @Test func `should say a script failed to load, with what it threw`() {
        #expect(throws: ScriptEngineError.load("Error: broken")) {
            try run("1", after: ["throw new Error('broken')"])
        }
    }

    @Test func `should say the expression failed, with what it threw`() {
        #expect(throws: ScriptEngineError.run("TypeError: no shape")) {
            try run("read()", after: ["function read() { throw new TypeError('no shape'); }"])
        }
    }

    @Test func `should start each run from a fresh context`() throws {
        _ = try run("leak = 1")
        #expect(try run("typeof leak") == "undefined")
    }

    @Test func `should fail a runaway recursion instead of the process`() {
        #expect {
            try run("deeper()", after: ["function deeper() { return deeper() + 1; }"])
        } throws: { error in
            guard case ScriptEngineError.run = error else { return false }
            return true
        }
    }

    /// The forms the built-in scripts parse, as JavaScriptCore read them:
    /// fractions past milliseconds are cut, an offset may lose its colon, and
    /// a bare date is UTC midnight.
    @Test(arguments: [
        ("2026-03-01T10:00:00Z", 1_772_359_200_000.0),
        ("2026-03-01T10:00:00.123Z", 1_772_359_200_123),
        ("2026-03-01T10:00:00.123456Z", 1_772_359_200_123),
        ("2026-03-01T10:00:00+09:00", 1_772_326_800_000),
        ("2026-03-01T10:00:00+0900", 1_772_326_800_000),
        ("2026-03-01T10:00:00.5+09:00", 1_772_326_800_500),
        ("2026-03-01", 1_772_323_200_000),
    ])
    func `should read the ISO 8601 times the scripts read`(_ text: String, _ milliseconds: Double) throws {
        #expect(try run("String(Date.parse(text))", strings: ["text": text]) == String(Int(milliseconds)))
    }

    // MARK: - Local time is the zone it is given

    /// Both ways, in zones whose clocks change by an hour (Los Angeles,
    /// Berlin), half an hour (Lord Howe), at midnight (Santiago) or never
    /// (Seoul): every quarter hour of the three days around each of 2026's
    /// changes, and noon of every day, as clock times and as instants. A
    /// script's `Date` reads the clock Foundation's calendar does in that
    /// zone, whatever zone the OS has.
    @Test(arguments: [("America/Los_Angeles", 2), ("Europe/Berlin", 2), ("Australia/Lord_Howe", 2),
                      ("America/Santiago", 2), ("Asia/Seoul", 0)])
    func `should keep Date's local time in the zone it is given, as Foundation's calendar does`(_ identifier: String, _ changes: Int) throws {
        let zone = TimeZone(identifier: identifier)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = Date(timeIntervalSince1970: 1_767_225_600), end = Date(timeIntervalSince1970: 1_798_761_600) // 2026, UTC
        let transitions = sequence(first: start) { zone.nextDaylightSavingTimeTransition(after: $0) }.dropFirst()
            .prefix { $0 < end }.map(\.timeIntervalSince1970)
        #expect(transitions.count == changes)
        let around = transitions.flatMap { stride(from: ($0 / 900).rounded(.down) * 900 - 129_600, to: $0 + 129_600, by: 900) }
        let noons = stride(from: start.timeIntervalSince1970 + 43_200, to: end.timeIntervalSince1970, by: 86_400)
        let times = Array(Set(around + noons)).sorted()
        let list = times.map { String(Int($0) * 1000) }.joined(separator: ",")

        // A clock time, as the parts `new Date(y, m, d, h, mi)` takes.
        let built = try #require(try run("""
            list.split(',').map((t) => { const w = new Date(Number(t));
              return new Date(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate(), w.getUTCHours(), w.getUTCMinutes()).getTime() / 1000;
            }).join(',')
            """, strings: ["list": list], in: identifier)).split(separator: ",").map { Double($0)! }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let expectedBuilt = times.map { wall in
            var parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: wall))
            parts.timeZone = nil
            return calendar.date(from: parts)!.timeIntervalSince1970
        }
        #expect(built == expectedBuilt)

        // An instant, as the local getters read it.
        let read = try #require(try run("""
            list.split(',').map((t) => { const d = new Date(Number(t));
              return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes(), d.getDay() + 1, -d.getTimezoneOffset() * 60].join(' ');
            }).join(',')
            """, strings: ["list": list], in: identifier)).split(separator: ",").map(String.init)
        let expectedRead = times.map { seconds in
            let instant = Date(timeIntervalSince1970: seconds)
            let p = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: instant)
            return [p.year!, p.month!, p.day!, p.hour!, p.minute!, p.weekday!, zone.secondsFromGMT(for: instant)]
                .map(String.init).joined(separator: " ")
        }
        #expect(read == expectedRead)
    }

    /// A clock time Los Angeles skips (02:30 on 2026-03-08) moves forward to
    /// 03:30 PDT; one it repeats (01:30 on 2026-11-01) is the first, PDT.
    @Test(arguments: [("2026, 2, 8, 2, 30", 1_772_965_800_000.0), ("2026, 10, 1, 1, 30", 1_793_521_800_000)])
    func `should move a clock time the zone skips forward and read a repeated one as its first`(_ parts: String, _ milliseconds: Double) throws {
        #expect(try run("String(new Date(\(parts)).getTime())", in: "America/Los_Angeles") == String(Int(milliseconds)))
    }

    /// A date-time that names no zone is on the person's clock (Seoul: 10:00
    /// is 01:00 UTC), as JavaScriptCore read it on the Mac; one that names a
    /// zone, and an ISO bare date, keep the meaning they spell.
    @Test(arguments: [
        ("2026-03-01T10:00:00", 1_772_326_800_000.0),
        ("2026-03-01T10:00", 1_772_326_800_000),
        ("Mar 1, 2026 10:00:00", 1_772_326_800_000),
        ("03/01/2026 10:00", 1_772_326_800_000),
        ("Sun Mar 01 2026 10:00:00 GMT+0100", 1_772_355_600_000),
        ("Mar 1, 2026 10:00 UTC", 1_772_359_200_000),
        ("Mar 1, 2026 10:00 PST", 1_772_388_000_000),
        ("2026-03-01T10:00:00Z", 1_772_359_200_000),
        ("2026-03-01", 1_772_323_200_000),
    ])
    func `should read a date-time with no zone on the person's clock`(_ text: String, _ milliseconds: Double) throws {
        let expected = String(Int(milliseconds))
        #expect(try run("Date.parse(text) + ' ' + new Date(text).getTime()", strings: ["text": text]) == "\(expected) \(expected)")
    }

    @Test func `should set a date's fields on the person's clock`() throws {
        let times = try run("""
            (() => { const d = new Date(2026, 2, 7, 12), out = [d.getTime()];
              out.push(d.setDate(8));          // 12:00 PDT, a day of 23 hours later
              out.push(d.setHours(2, 30));     // skipped: 03:30 PDT
              out.push(d.setMonth(10, 1));     // 03:30 PST
              out.push(d.setHours(1, 30));     // repeated: the first, PDT
              out.push(new Date(NaN).setFullYear(2026));
              return out.join(' '); })()
            """, in: "America/Los_Angeles")
        #expect(times == "1772913600000 1772996400000 1772965800000 1793532600000 1793521800000 1767254400000")
    }

    /// A setter given nothing sets its field to `undefined`, so the date
    /// becomes invalid, as every engine does.
    @Test(arguments: ["setFullYear", "setMonth", "setDate", "setHours", "setMinutes", "setSeconds", "setMilliseconds", "setYear"])
    func `should make a date invalid when a setter is given nothing`(_ setter: String) throws {
        #expect(try run("(() => { const d = new Date(0); const r = d.\(setter)(); return r + ' ' + d.getTime(); })()",
                        in: "America/Los_Angeles") == "NaN NaN")
    }

    @Test(arguments: ["NaN, 0", "2026, NaN", "2026, 0, NaN", "2026, 0, 1, NaN", "2026, 0, 1, 0, 0, 0, Infinity"])
    func `should make a date invalid when a part it is built from is not a number`(_ parts: String) throws {
        #expect(try run("String(new Date(\(parts)).getTime())", in: "America/Los_Angeles") == "NaN")
    }

    @Test func `should write a date on the person's clock`() throws {
        let text = try run("""
            (() => { const d = new Date(1772965800000);
              return [d.toString(), String(d), d.toDateString(), d.toTimeString(), d.toLocaleString(),
                      d.toLocaleDateString(), d.toLocaleTimeString(), new Date(NaN).toString()].join('|'); })()
            """, in: "America/Los_Angeles")
        #expect(text == "Sun Mar 08 2026 03:30:00 GMT-0700|Sun Mar 08 2026 03:30:00 GMT-0700|Sun Mar 08 2026|03:30:00 GMT-0700"
                + "|03/08/2026, 03:30:00 AM|03/08/2026|03:30:00 AM|Invalid Date")
    }

    /// What the scripts lean on most: UTC fields, `Date.UTC`, ISO text and the
    /// clock, none of which has a zone.
    @Test func `should leave UTC time, the clock and what a date is as they were`() throws {
        let value = try run("""
            (() => { const d = new Date(Date.UTC(2026, 2, 8, 2, 30));
              return [d.getTime(), d.getUTCHours(), d.toISOString(), JSON.stringify(d), d instanceof Date,
                      Object.prototype.toString.call(d), Date.length, typeof Date(), Math.abs(Date.now() - Number(now)) < 60000].join('|'); })()
            """, strings: ["now": String(Int(Date().timeIntervalSince1970 * 1000))], in: "America/Los_Angeles")
        #expect(value == "1772937000000|2|2026-03-08T02:30:00.000Z|\"2026-03-08T02:30:00.000Z\"|true|[object Date]|7|string|true")
    }
}
