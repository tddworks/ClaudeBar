/// What makes `Date`'s local time the person's zone (#570): QuickJS asks the
/// OS for its local time (libc on the Mac; on Windows, today's offset for every
/// date), which would bypass the `TimeZone` port (#567). `QuickJSEngine` runs
/// this before any script, with the host's `__zoneOffset(milliseconds)`, the
/// zone's offset from UTC at that instant in seconds, and then removes that
/// name, so a script sees only plain `Date`.
///
/// It rebinds what reads or writes a local time and leaves the rest (UTC
/// fields, `Date.UTC`, `Date.now`, ISO text) native:
/// - `new Date(y, m, …)` and the setters, through `instant`: a clock time the
///   zone repeats is its first instant, one it skips moves forward by the
///   gap, as ECMAScript says;
/// - the local getters and `getTimezoneOffset`;
/// - `Date.parse` and `new Date(text)` of a date-time that names no zone;
/// - `toString`, `toDateString`, `toTimeString` and `toLocale*`, in
///   QuickJS's own formats.
///
/// `Vendor/` stays unedited; once quickjs-ng has a hook for the offset, this
/// shrinks to that one call.
enum LocalDateScript {
    /// The host function this script takes the zone's offsets from.
    static let offsetFunction = "__zoneOffset"

    static let source = #"""
(function (offsetOf) {
  'use strict';
  const NativeDate = Date, proto = NativeDate.prototype;
  const call = Function.prototype.call.bind(Function.prototype.call);
  const getTime = proto.getTime, setTime = proto.setTime, nativeParse = NativeDate.parse, now = NativeDate.now;
  const timeOf = (date) => call(getTime, date);
  const UTC_FIELDS = ['getUTCFullYear', 'getUTCMonth', 'getUTCDate', 'getUTCHours', 'getUTCMinutes',
                      'getUTCSeconds', 'getUTCMilliseconds'].map((name) => proto[name]);
  const getUTCDay = proto.getUTCDay, setUTCFullYear = proto.setUTCFullYear, setUTCHours = proto.setUTCHours;
  const offset = (t) => offsetOf(t) * 1000;
  const clip = (t) => (Math.abs(t) <= 8.64e15 ? Math.trunc(t) + 0 : NaN);

  // The instant the person's clock reads `wall`, a local time written as UTC.
  function instant(wall) {
    if (!isFinite(wall)) return NaN;
    const before = wall - offset(wall - 864e5), after = wall - offset(wall + 864e5);
    const reads = (t) => t + offset(t) === wall;
    if (reads(before) && reads(after)) return clip(Math.min(before, after));
    return clip(reads(after) ? after : before);
  }
  // `t` on the person's clock: a date whose UTC fields read it.
  const wall = (t) => new NativeDate(isNaN(t) ? NaN : t + offset(t));
  const fields = (date) => UTC_FIELDS.map((get) => call(get, date));
  // MakeDate of the fields, as UTC, with no 0-99 year mapping. A field that
  // isn't finite makes the date invalid: QuickJS's `setUTCHours` would
  // rebuild an invalid date from 0 and lose it.
  function fromFields(f) {
    if (!f.every(isFinite)) return NaN;
    const date = new NativeDate(0);
    call(setUTCFullYear, date, f[0], f[1], f[2]);
    return call(setUTCHours, date, f[3], f[4], f[5], f[6]);
  }
  function define(target, name, value) {
    Object.defineProperty(value, 'name', { value: name, configurable: true });
    Object.defineProperty(target, name, { value, writable: true, configurable: true, enumerable: false });
  }
  function toPrimitive(value) {
    const exotic = value[Symbol.toPrimitive];
    const tries = exotic != null ? [() => call(exotic, value, 'default')]
                                 : ['valueOf', 'toString'].map((name) => () => typeof value[name] === 'function' ? call(value[name], value) : value);
    for (const attempt of tries) {
      const result = attempt();
      if (result === null || (typeof result !== 'object' && typeof result !== 'function')) return result;
    }
    throw new TypeError('cannot convert the object to a primitive value');
  }

  const ISO = /^(?:[+-]\d{6}|\d{4})(?:-\d\d(?:-\d\d)?)?(T\d\d:\d\d(?::\d\d(?:[.,]\d+)?)?)?(Z|[+-]\d\d(?::\d\d)?|[+-]\d{4})?$/;
  function parse(text) {
    const s = String(text), iso = ISO.exec(s);
    // An ISO date-time that names no zone is local; a bare date is UTC.
    if (iso) return iso[1] && !iso[2] ? instant(nativeParse(s + 'Z')) : nativeParse(s);
    // Another form: QuickJS takes the last zone it reads, so one put first
    // changes the answer only when the text names none.
    const utc = nativeParse('UTC ' + s);
    return utc === utc && utc !== nativeParse('EST ' + s) ? instant(utc) : nativeParse(s);
  }

  const DAYS = 'SunMonTueWedThuFriSat', MONTHS = 'JanFebMarAprMayJunJulAugSepOctNovDec';
  const two = (n) => String(n).padStart(2, '0');
  function text(date, part, locale) {
    const t = timeOf(date);
    if (isNaN(t)) return 'Invalid Date';
    const w = wall(t), [y, mo, d, h, mi, s] = fields(w);
    const year = (y < 0 ? '-' : '') + String(Math.abs(y)).padStart(4, '0');
    let out = '';
    if (locale) {
      if (part & 1) out += two(mo + 1) + '/' + two(d) + '/' + year + (part === 3 ? ', ' : '');
      if (part & 2) out += two((h + 11) % 12 + 1) + ':' + two(mi) + ':' + two(s) + (h < 12 ? ' AM' : ' PM');
    } else {
      if (part & 1) out += DAYS.substr(call(getUTCDay, w) * 3, 3) + ' ' + MONTHS.substr(mo * 3, 3) + ' ' + two(d) + ' ' + year + (part === 3 ? ' ' : '');
      if (part & 2) {
        const east = Math.trunc(offsetOf(t) / 60), abs = Math.abs(east);
        out += two(h) + ':' + two(mi) + ':' + two(s) + ' GMT' + (east < 0 ? '-' : '+') + two(Math.trunc(abs / 60)) + two(abs % 60);
      }
    }
    return out;
  }

  // Named for what it replaces; inside, `Date` is this function.
  const LocalDate = function Date(...parts) {
    if (new.target === undefined) return text(new NativeDate(now()), 3, false);
    let t;
    if (parts.length === 0) {
      t = now();
    } else if (parts.length === 1) {
      let value = parts[0];
      if (value instanceof NativeDate) {
        t = timeOf(value);
      } else {
        if (value !== null && (typeof value === 'object' || typeof value === 'function')) value = toPrimitive(value);
        t = typeof value === 'string' ? parse(value) : clip(Number(value));
      }
    } else {
      const n = parts.slice(0, 7).map(Number), year = Math.trunc(n[0]), f = [0, 0, 1, 0, 0, 0, 0];
      if (year >= 0 && year <= 99) n[0] = 1900 + year;
      n.forEach((value, index) => { f[index] = value; });
      t = instant(fromFields(f));
    }
    return Reflect.construct(NativeDate, [t], new.target);
  };
  Object.defineProperty(LocalDate, 'length', { value: 7 });
  LocalDate.prototype = proto;
  define(proto, 'constructor', LocalDate);
  define(LocalDate, 'now', now);
  define(LocalDate, 'UTC', NativeDate.UTC);
  define(LocalDate, 'parse', parse);

  ['getFullYear', 'getMonth', 'getDate', 'getHours', 'getMinutes', 'getSeconds'].forEach((name, index) => {
    define(proto, name, function () { return call(UTC_FIELDS[index], wall(timeOf(this))); });
  });
  define(proto, 'getDay', function () { return call(getUTCDay, wall(timeOf(this))); });
  define(proto, 'getTimezoneOffset', function () {
    const t = timeOf(this);
    return isNaN(t) ? NaN : -offsetOf(t) / 60;
  });
  if (proto.getYear) define(proto, 'getYear', function () { return proto.getFullYear.call(this) - 1900; });

  // Each setter replaces up to `most` fields from `first`, read on the
  // person's clock. Its first field is always set: given nothing, it is
  // `undefined`, so the date becomes invalid.
  [['setFullYear', 0, 3], ['setMonth', 1, 2], ['setDate', 2, 1], ['setHours', 3, 4],
   ['setMinutes', 4, 3], ['setSeconds', 5, 2], ['setMilliseconds', 6, 1]].forEach(([name, first, most]) => {
    define(proto, name, function (...values) {
      const t = timeOf(this);
      const given = (values.length ? values.slice(0, most) : [undefined]).map(Number);
      if (isNaN(t) && first !== 0) return NaN;
      const f = fields(isNaN(t) ? new NativeDate(0) : wall(t));
      given.forEach((value, index) => { f[first + index] = value; });
      return call(setTime, this, instant(fromFields(f)));
    });
  });
  if (proto.setYear) define(proto, 'setYear', function (value) {
    timeOf(this);
    let year = Number(value);
    if (isNaN(year)) return call(setTime, this, NaN);
    const whole = Math.trunc(year);
    if (whole >= 0 && whole <= 99) year = 1900 + whole;
    return proto.setFullYear.call(this, year);
  });

  [['toString', 3, false], ['toDateString', 1, false], ['toTimeString', 2, false],
   ['toLocaleString', 3, true], ['toLocaleDateString', 1, true], ['toLocaleTimeString', 2, true]]
    .forEach(([name, part, locale]) => define(proto, name, function () { return text(this, part, locale); }));

  globalThis.Date = LocalDate;
})(__zoneOffset);
delete globalThis.__zoneOffset;
"""#
}
