// The Admin API's costs for the last 30 days, a bucket per day: every
// result's `amount.value` added up exactly into one cost, a line per
// `line_item`, largest first. Amounts are read from the text so money never
// passes through a binary float.
function read(response) {
    var body;
    try { body = jsonDecimal(response.text || ''); } catch (e) { body = null; }
    if (!body || typeof body !== 'object' || !Array.isArray(body.data)) {
        return { error: { parseFailed: "Failed to parse OpenAI's costs" } };
    }
    var total = '0', items = {};
    body.data.forEach(function (bucket) {
        (bucket && Array.isArray(bucket.results) ? bucket.results : []).forEach(function (result) {
            var value = result && result.amount ? result.amount.value : null;
            if (value === null || value === undefined || !/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(String(value))) return;
            var label = typeof result.line_item === 'string' && result.line_item ? result.line_item : 'API';
            total = decimalAdd(total, String(value));
            items[label] = decimalAdd(items[label] || '0', String(value));
        });
    });
    var lines = Object.keys(items)
        .map(function (label) { return { label: label, used: items[label] }; })
        .sort(function (a, b) { return Number(b.used) - Number(a.used); });
    return { quotas: [], cost: { kind: 'apiCost', used: total, lines: lines, resetText: 'Last 30 days' } };
}
