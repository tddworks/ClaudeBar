// OpenCode Go's plan, added up from opencode's own database by one read-only
// query (see opencode-go.json): $12 per 5 hours, $30 per week, $60 per month.
// A database answers each column as text, so every column reads as a number.
function read(response, context) {
    const rows = response.json;
    const row = Array.isArray(rows) ? rows[0] : null;
    const num = value => {
        const n = typeof value === "number" ? value : parseFloat(value);
        return Number.isFinite(n) ? n : null;
    };
    if (!row || num(row.five_hour_cost) == null || num(row.weekly_cost) == null
        || num(row.monthly_cost) == null || num(row.now_ms) == null)
        return {error: {parseFailed: "No usage rows from opencode's database"}};
    // Money of a ceiling (the Left law): what is left of each cap, to the cent.
    const left = (spent, cap) => ({money: Math.max(0, cap - spent).toFixed(2), of: String(cap), currency: "USD"});
    const oldest = num(row.five_hour_oldest_ms);
    const quotas = [
        {type: "session", left: left(num(row.five_hour_cost), 12), windowSeconds: 18000,
         resetsAt: (oldest != null ? oldest : num(row.now_ms)) / 1000 + 18000},
        {type: "weekly", left: left(num(row.weekly_cost), 30), windowSeconds: 604800, resetsAt: num(row.week_end_ms) / 1000}
    ];
    // Before a first message there is no billing month yet: no window to state.
    const start = num(row.month_start_ms), end = num(row.month_end_ms);
    const anchored = start != null && end != null;
    quotas.push({type: "time", name: "Monthly", left: left(num(row.monthly_cost), 60),
        resetsAt: anchored ? end / 1000 : null,
        windowSeconds: anchored ? (end - start) / 1000 : null});
    return {quotas: quotas};
}
