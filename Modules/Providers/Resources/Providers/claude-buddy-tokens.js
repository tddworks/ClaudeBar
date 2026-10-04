// Claude Desktop's daily token counter, `~/Library/Application Support/Claude/
// buddy-tokens.json`: `{"tokens-today": {"date": "2026-05-28", "tokens": 74422}}`
// (issue #198). Best-effort by design — the file is an implementation detail
// of Claude Desktop with no stability guarantee, and it carries only today's
// total token count, no session/weekly windows or caps. So the counter becomes
// a note ("Tokens Today"), not a quota: a percentage with no cap would be a
// lie, and an empty `quotas` keeps the percentage-based menu bar honest.
//
// Defensive on purpose: any shape this doesn't recognise is an error with a
// structural reason (never the file's contents — the file log has no
// redaction), and a counter whose date is not the user's local day is no data,
// so yesterday's total never renders as today's usage.
function read(response, context) {
    const payload = response.json;
    if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
        return {error: {parseFailed: 'buddy-tokens.json is not valid JSON'}};
    }

    const today = payload['tokens-today'];
    if (today == null || typeof today !== 'object' || Array.isArray(today)) {
        return {error: {parseFailed: "buddy-tokens.json schema changed: missing 'tokens-today'"}};
    }

    if (!('tokens' in today)) {
        return {error: {parseFailed: "buddy-tokens.json schema changed: missing 'tokens-today.tokens'"}};
    }
    const tokens = today.tokens;
    if (typeof tokens !== 'number' || !isFinite(tokens) || tokens < 0) {
        return {error: {parseFailed: "buddy-tokens.json schema changed: invalid 'tokens' value"}};
    }

    const recorded = today.date;
    if (typeof recorded !== 'string') {
        return {error: {parseFailed: "buddy-tokens.json schema changed: missing 'tokens-today.date'"}};
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(recorded) || !isRealDay(recorded)) {
        return {error: {parseFailed: "buddy-tokens.json schema changed: invalid 'date' value"}};
    }

    // Only the counter for the user's local day is current. Anything else —
    // yesterday after midnight, or a clock-skewed future stamp — is stale
    // data that must not render as today's usage.
    if (recorded !== dayInZone(context.now * 1000, context.timeZone)) {
        return {error: 'noData'};
    }

    return {notes: [{group: 'Claude Desktop', label: 'Tokens Today', text: grouped(tokens)}]};
}

// "74422" → "74,422", grouped by thousands.
function grouped(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

// "yyyy-MM-dd" in the zone ClaudeBar runs in — the same local day the file's
// date names. `2026-02-30` and friends are rejected by the round trip.
function isRealDay(text) {
    const year = Number(text.slice(0, 4)), month = Number(text.slice(5, 7)), day = Number(text.slice(8, 10));
    const date = new Date(Date.UTC(year, month - 1, day));
    return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function dayInZone(millis, zone) {
    const parts = new Intl.DateTimeFormat('en-US', {timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit'})
        .formatToParts(new Date(millis));
    const value = (type) => parts.find((part) => part.type === type).value;
    return value('year') + '-' + value('month') + '-' + value('day');
}
