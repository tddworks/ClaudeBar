// Today's Bedrock spend: each model's tokens, across regions, at its list
// price — one cost with a line per model, largest first. The person's daily
// budget judges it; it is never a quota.
function read(response, context) {
    const data = response.json;
    if (!data || !Array.isArray(data.rows)) return {error: {parseFailed: 'No CloudWatch rows in response'}};
    const prices = data.prices || {};
    const models = {};
    for (const row of data.rows) {
        if (!row || typeof row.id !== 'string') continue;
        const m = models[row.id] || (models[row.id] = {input: 0, output: 0, calls: 0});
        m.input += Number(row.InputTokenCount) || 0;
        m.output += Number(row.OutputTokenCount) || 0;
        m.calls += Number(row.Invocations) || 0;
    }
    const tokens = n => n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : n >= 1e3 ? (n / 1e3).toFixed(1) + 'K' : String(n);
    const lines = [];
    let total = '0';
    for (const id of Object.keys(models)) {
        const m = models[id];
        if (!m.input && !m.output && !m.calls) continue;
        const price = prices[id] || {};
        // Prices are per a power of ten tokens ("1000000"): tokens × price ÷ per, exactly.
        const per = /^10*$/.test(price.per || '') ? price.per : '1000000';
        const share = (count, unitPrice) => unitPrice ? decimalMultiply(decimalMultiply(String(Math.round(count)), unitPrice), '1e-' + (per.length - 1)) : '0';
        const cost = decimalAdd(share(m.input, price.input), share(m.output, price.output));
        total = decimalAdd(total, cost);
        lines.push({label: price.name || id, used: cost,
                    detail: tokens(m.input + m.output) + ' tokens · ' + m.calls + ' calls' + (price.input ? '' : ' · no price known')});
    }
    lines.sort((a, b) => Number(b.used) - Number(a.used) || (a.label < b.label ? -1 : 1));
    const midnight = new Date((data.periodStart || context.now) * 1000);
    midnight.setDate(midnight.getDate() + 1);
    const cost = {kind: 'apiCost', used: total, lines, resetsAt: midnight.getTime() / 1000, resetText: 'Today'};
    if (context.values.dailyBudget) cost.limit = context.values.dailyBudget;
    return {quotas: [], cost};
}
