// Server percentages are used, not remaining. Missing windows are allowed.
function read(response, context) {
    const root = response.json;
    if (!root || !root.usage || typeof root.usage !== "object")
        return {error:{parseFailed:"Missing 'usage' in response"}};
    const quotas = [];
    for (const window of [["rolling","session",null,18000],["weekly","weekly",null,604800],["monthly","time","Monthly",null]]) {
        const entry = root.usage[window[0]];
        if (!entry || !["number","string"].includes(typeof entry.percent) || (typeof entry.percent === "string" && !entry.percent.trim())) continue;
        const used = Number(entry.percent);
        if (!Number.isFinite(used)) continue;
        const timestamp = typeof entry.resetsAt === "string" ? Date.parse(entry.resetsAt) : NaN;
        quotas.push({type:window[1],name:window[2],percentRemaining:entry.status === "rate-limited" ? 0 : Math.max(0,Math.min(100,100-used)),
            resetsAt:Number.isFinite(timestamp) ? timestamp/1000 : null,windowSeconds:window[3]});
    }
    return quotas.length ? {quotas:quotas} : {error:{parseFailed:"No usage windows in response"}};
}
