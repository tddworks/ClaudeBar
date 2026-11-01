// Kiro usage, from either data source, with dates in the Mac's own time zone:
// `rpc` is the v3 engine's `_kiro/account/getUsage` answer over `kiro-cli acp`,
// `cli` the plain /usage screen of a kiro-cli with no v3 engine.
function read(response, context) {
    const now = new Date(context.now * 1000);
    const data = response.json && response.json.result && response.json.result.data;
    const quotas = data ? fromAccount(data, context, now) : fromScreen(response.text || "", context, now);
    return quotas.length ? {quotas: quotas} : {error: {parseFailed: "No quota data found in Kiro CLI output"}};
}

// `{billingCycleReset: "2026-12-01", usageBreakdowns: [...], bonusCredits: [...]}`.
// One grant is "Bonus credits"; more get their own names, so each has its own
// card and can be hidden alone.
function fromAccount(data, context, now) {
    const quotas = [];
    const grants = (Array.isArray(data.bonusCredits) ? data.bonusCredits : [])
        .map(b => ({name: String(b.name || "").trim(),
            quota: bonusQuota(b.used, b.total, typeof b.daysUntilExpiry === "number" ? b.daysUntilExpiry : null, context)}))
        .filter(g => g.quota);
    const names = grants.map(g => g.name);
    grants.forEach((g, i) => {
        if (grants.length > 1) {
            const unique = g.name && names.indexOf(g.name) === names.lastIndexOf(g.name);
            g.quota.name = unique ? "Bonus credits: " + g.name : "Bonus credits " + (i + 1);
        }
        quotas.push(g.quota);
    });
    const reset = /^(\d{4})-(\d{2})-(\d{2})/.exec(data.billingCycleReset || "");
    for (const b of Array.isArray(data.usageBreakdowns) ? data.usageBreakdowns : []) {
        if (!b.hasLimit) continue;
        const quota = monthlyQuota(b.used, b.limit, reset, now);
        if (!quota) continue;
        if (!/^credits?$/i.test(String(b.displayName || "").trim())) quota.name = String(b.displayName);
        quotas.push(quota);
    }
    return quotas;
}

function fromScreen(screen, context, now) {
    const text = screen.replace(/\u001B\[[0-9;]*[a-zA-Z]/g, "");
    const quotas = [];
    const bonus = text.match(/Bonus credits:\s*([\d.]+)\/([\d.]+)/);
    if (bonus) {
        const expiry = text.match(/expires in (\d+) days/);
        const quota = bonusQuota(bonus[1], bonus[2], expiry ? Number(expiry[1]) : null, context);
        if (quota) quotas.push(quota);
    }
    const credits = text.match(/Credits \(([\d.]+) of ([\d.]+)/);
    if (credits) {
        // `resets on 2026-11-01` from kiro-cli 2.x, `resets on 11/01` before it.
        const reset = text.match(/resets on (\d{4})-(\d{2})-(\d{2})/) || text.match(/resets on (\d{2})\/(\d{2})/);
        const quota = monthlyQuota(credits[1], credits[2], reset, now);
        if (quota) quotas.push(quota);
    }
    return quotas;
}

// A grant that expires, not a window that refills: no window length.
function bonusQuota(used, total, days, context) {
    if (!(Number(total) > 0)) return null;
    return {type: "time", name: "Bonus credits",
        percentRemaining: Math.max(0, (Number(total) - Number(used)) / Number(total) * 100),
        resetsAt: days === null ? null : context.now + days * 86400,
        resetText: days === null ? null : "Expires in " + days + " days"};
}

// `reset` is a match of [year, month, day] or of [month, day]; without a
// year, a date already past this year is next year's.
function monthlyQuota(used, limit, reset, now) {
    if (!(Number(limit) > 0)) return null;
    let date = null, windowSeconds = null, resetText = null;
    if (reset) {
        const full = reset.length > 3;
        const year = full ? Number(reset[1]) : now.getFullYear();
        const month = Number(reset[full ? 2 : 1]) - 1;
        const day = Number(reset[full ? 3 : 2]);
        let candidate = new Date(year, month, day);
        if (!full && candidate < now) candidate = new Date(year + 1, month, day);
        const targetYear = full ? year : candidate.getFullYear();
        if (candidate.getFullYear() === targetYear && candidate.getMonth() === month && candidate.getDate() === day) {
            date = candidate;
            // The month that ends on the reset date — its real length. A
            // reset on the 31st starts on the last day of a shorter month.
            const lastOfPrevious = new Date(date.getFullYear(), date.getMonth(), 0).getDate();
            const start = new Date(date.getFullYear(), date.getMonth() - 1, Math.min(date.getDate(), lastOfPrevious));
            windowSeconds = (date.getTime() - start.getTime()) / 1000;
            const pad = n => (n < 10 ? "0" : "") + n;
            resetText = "Resets on " + pad(month + 1) + "/" + pad(day);
        }
    }
    return {type: "time", name: "Monthly",
        percentRemaining: Math.max(0, (Number(limit) - Number(used)) / Number(limit) * 100),
        resetsAt: date ? date.getTime() / 1000 : null,
        resetText: resetText, windowSeconds: windowSeconds};
}
