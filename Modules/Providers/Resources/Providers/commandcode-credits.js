// Command Code credit plans and window quotas, including wrapped deployments.
function read(response, context) {
    // Each required step's answer must be a JSON object, as the old probe required.
    const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);
    if (!isObject(response.json) || !isObject(response.json.whoami) || !isObject(response.json.credits))
        return {error: {parseFailed: "Failed to parse Command Code response as JSON"}};
    const unwrap = root => isObject(root.data) ? root.data : root;
    const creditsBody = unwrap(response.json.credits);
    const identity = unwrap(response.json.whoami);
    const sub = isObject(response.json.subscriptions) ? unwrap(response.json.subscriptions) : null;
    const summary = isObject(response.json.summary) ? unwrap(response.json.summary) : null;
    const number = value => typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : NaN;
    const text = value => ["string","number"].includes(typeof value) && String(value).trim() ? String(value).trim() : null;
    const timestamp = value => {
        if (typeof value === "number" && Number.isFinite(value)) return value > 1e12 ? value / 1000 : value;
        if (typeof value === "string" && value.trim() && Number.isFinite(Date.parse(value))) return Date.parse(value) / 1000;
        return null;
    };
    const roundMoney = value => Number(value.toFixed(6));
    const quotas = [];
    for (const rule of [["fiveHour","session",18000],["weekly","weekly",604800]]) {
        const value = (creditsBody.windowLimits || {})[rule[0]];
        if (!value || !(number(value.cap) > 0)) continue;
        const used = Number.isFinite(number(value.used)) ? number(value.used) : 0;
        quotas.push({type:rule[1],percentRemaining:(number(value.cap)-used)/number(value.cap)*100,resetsAt:timestamp(value.resetAt),windowSeconds:rule[2]});
    }
    const credits = creditsBody.credits;
    if (isObject(credits)) {
        const amount = value => Math.max(0,Number.isFinite(number(value)) ? number(value) : 0);
        const monthly = amount(credits.monthlyCredits), purchased = amount(credits.purchasedCredits), free = amount(credits.freeCredits);
        const remaining = roundMoney(monthly+purchased+free);
        const plans = {"individual-go":10,"individual-go-v1":10,"individual-goat":70,"individual-pro":30,"individual-pro-v1":80,"individual-provider":15,"individual-max":150,"individual-ultra":300,"teams-pro":40};
        const subStatus = text(sub && sub.status);
        const subActive = subStatus ? subStatus.toLowerCase() === "active" : true;
        const rawPlan = subActive ? (text(sub && sub.planId) || text(credits.planId) || "") : "";
        const normalized = rawPlan.toLowerCase().replace(/_/g,"-");
        const key = normalized ? Object.keys(plans).sort((a,b)=>b.length-a.length).find(key => normalized.startsWith(key)) : null;
        const periodStart = subActive && sub ? timestamp(sub.currentPeriodStart) : null;
        const periodEnd = subActive && sub ? timestamp(sub.currentPeriodEnd) : null;
        const periodWindow = periodStart !== null && periodEnd !== null && periodEnd > periodStart ? periodEnd - periodStart : null;
        const spent = summary ? number(summary.totalCost) : NaN;
        let total = null;
        if (key) {
            total = roundMoney(Math.max(plans[key],monthly)+purchased+free);
        } else if (subStatus && subActive && Number.isFinite(spent) && spent > 0) {
            total = roundMoney(spent + remaining);
        }
        if (total !== null && total > 0) {
            const quota = {type:"time",name:"Credits",left:{money:String(remaining),of:String(total),currency:"USD"}};
            if (periodEnd !== null) quota.resetsAt = periodEnd;
            if (periodWindow !== null) quota.windowSeconds = periodWindow;
            quotas.push(quota);
        } else if (!quotas.length && remaining > 0) {
            quotas.push({type:"time",name:"Credits",left:{money:String(remaining),currency:"USD"}});
        }
    }
    const user = isObject(identity.user) ? identity.user : {};
    return {quotas:quotas,account:{email:text(user.userName) || text(user.name)}};
}
