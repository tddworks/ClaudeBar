// OpenCode Go's plan, added up from opencode's own database by one read-only
// query (see opencode-go.json): $12 per 5 hours, $30 per week, $60 per month.
function read(response, context) {
    const rows = response.json;
    const row = Array.isArray(rows) ? rows[0] : null;
    if (!row || typeof row.five_hour_cost !== "number" || typeof row.weekly_cost !== "number"
        || typeof row.monthly_cost !== "number" || typeof row.now_ms !== "number")
        return {error: {parseFailed: "No usage rows from opencode db"}};
    // Money of a ceiling (the Left law): what is left of each cap, to the cent.
    const left = (spent, cap) => ({money: Math.max(0, cap - spent).toFixed(2), of: String(cap), currency: "USD"});
    const quotas = [
        {type: "session", left: left(row.five_hour_cost, 12), windowSeconds: 18000,
         resetsAt: (row.five_hour_oldest_ms != null ? row.five_hour_oldest_ms : row.now_ms) / 1000 + 18000},
        {type: "weekly", left: left(row.weekly_cost, 30), windowSeconds: 604800, resetsAt: row.week_end_ms / 1000}
    ];
    // Before a first message there is no billing month yet: no window to state.
    const anchored = row.month_start_ms != null && row.month_end_ms != null;
    quotas.push({type: "time", name: "Monthly", left: left(row.monthly_cost, 60),
        resetsAt: anchored ? row.month_end_ms / 1000 : null,
        windowSeconds: anchored ? (row.month_end_ms - row.month_start_ms) / 1000 : null});
    return {quotas: quotas};
}
