/// Helpers every mapping script gets, so money never passes through a binary
/// float: `jsonDecimal(text)` parses JSON with each number kept as its exact
/// text, `decimalCents(amount)` rounds such a text to cents, half up, and
/// `decimalAdd(a, b)` / `decimalMultiply(a, b)` work on such texts exactly.
enum DecimalScript {
    static let source = #"""
function jsonDecimal(text) {
    return JSON.parse(text.replace(/"(?:\\.|[^"\\])*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/g,
        token => token.charAt(0) === '"' ? token : JSON.stringify(token)));
}
function decimalParts(value) {
    const match = String(value).match(/^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/);
    if (!match || !(match[2] || match[3])) throw new Error('Not a decimal amount');
    const exponent = Number(match[4] || 0);
    if (!Number.isInteger(exponent) || Math.abs(exponent) > 1000) throw new Error('Amount exponent out of range');
    const fraction = match[3] || '';
    let digits = BigInt((match[2] || '0') + fraction), scale = fraction.length - exponent;
    if (scale < 0) { digits *= 10n ** BigInt(-scale); scale = 0; }
    return { digits: match[1] === '-' ? -digits : digits, scale };
}
function decimalText(parts) {
    let { digits, scale } = parts;
    while (scale > 0 && digits % 10n === 0n) { digits /= 10n; scale -= 1; }
    const negative = digits < 0n, text = (negative ? -digits : digits).toString().padStart(scale + 1, '0');
    const whole = scale ? text.slice(0, -scale) + '.' + text.slice(-scale) : text;
    return (negative ? '-' : '') + whole;
}
function decimalMultiply(a, b) {
    const x = decimalParts(a), y = decimalParts(b);
    return decimalText({ digits: x.digits * y.digits, scale: x.scale + y.scale });
}
function decimalAdd(a, b) {
    const x = decimalParts(a), y = decimalParts(b), scale = Math.max(x.scale, y.scale);
    return decimalText({ digits: x.digits * 10n ** BigInt(scale - x.scale) + y.digits * 10n ** BigInt(scale - y.scale), scale });
}
function decimalCents(value) {
    const match = String(value).match(/^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/);
    if (!match || !(match[2] || match[3])) throw new Error('Not a decimal amount');
    const negative = match[1] === '-', exponent = Number(match[4] || 0);
    if (!Number.isInteger(exponent) || Math.abs(exponent) > 1000) throw new Error('Amount exponent out of range');
    let digits = (match[2] || '') + (match[3] || ''), point = (match[2] || '').length + exponent;
    if (point < 0) { digits = '0'.repeat(-point) + digits; point = 0; }
    if (point > digits.length) digits += '0'.repeat(point - digits.length);
    let cents = (digits.slice(0, point) || '0') + (digits.slice(point) + '00').slice(0, 2);
    cents = cents.replace(/^0+(?=\d)/, '');
    if (Number(digits.charAt(point + 2) || '0') >= 5) {
        let carry = 1, out = '';
        for (let i = cents.length - 1; i >= 0; i--) {
            const n = Number(cents[i]) + carry;
            out = String(n % 10) + out;
            carry = n >= 10 ? 1 : 0;
        }
        cents = (carry ? '1' : '') + out;
    }
    cents = cents.padStart(3, '0');
    return (negative && /[1-9]/.test(cents) ? '-' : '') + cents.slice(0, -2) + '.' + cents.slice(-2);
}
"""#
}
