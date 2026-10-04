// Command Code credit plans and window quotas, including wrapped deployments.
function read(response, context) {
    // Each step's answer must be a JSON object, as the old probe required.
    const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);
    if (!isObject(response.json) || !isObject(response.json.whoami) || !isObject(response.json.credits))
        return {error: {parseFailed: "Failed to parse Command Code response as JSON"}};
    const unwrap = root => root.data && typeof root.data === "object" ? root.data : root;
    const creditsBody = unwrap(response.json.credits);
    const identity = unwrap(response.json.whoami);
    const number = value => typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : NaN;
    const text = value => ["string","number"].includes(typeof value) && String(value).trim() ? String(value).trim() : null;
    const quotas = [];
    for (const rule of [["fiveHour","session",18000],["weekly","weekly",604800]]) {
        const value = (creditsBody.windowLimits || {})[rule[0]];
        if (!value || !(number(value.cap) > 0)) continue;
        const used = Number.isFinite(number(value.used)) ? number(value.used) : 0;
        let reset = null;
        if (typeof value.resetAt === "number") reset = value.resetAt > 1e12 ? value.resetAt/1000 : value.resetAt;
        else if (typeof value.resetAt === "string" && Number.isFinite(Date.parse(value.resetAt))) reset = Date.parse(value.resetAt)/1000;
        quotas.push({type:rule[1],percentRemaining:(number(value.cap)-used)/number(value.cap)*100,resetsAt:reset,windowSeconds:rule[2]});
    }
    const credits = creditsBody.credits;
    if (credits && typeof credits === "object") {
        const amount = value => Math.max(0,Number.isFinite(number(value)) ? number(value) : 0);
        const monthly = amount(credits.monthlyCredits), purchased = amount(credits.purchasedCredits), free = amount(credits.freeCredits);
        const remaining = monthly+purchased+free;
        const plans = {"individual-go":10,"individual-goat":70,"individual-pro":30,"individual-pro-v1":80,"individual-provider":15,"individual-max":150,"individual-ultra":300,"teams-pro":40};
        const normalized = (typeof credits.planId === "string" ? credits.planId : "").toLowerCase().replace(/_/g,"-");
        const key = Object.keys(plans).sort((a,b)=>b.length-a.length).find(key => normalized.startsWith(key));
        if (key) {
            const total = Math.max(plans[key],monthly)+purchased+free;
            if (total > 0) quotas.push({type:"time",name:"Credits",left:{money:String(remaining),of:String(total),currency:"USD"}});
        } else if (!quotas.length && remaining > 0) {
            quotas.push({type:"time",name:"Credits",left:{money:String(remaining),currency:"USD"}});
        }
    }
    const user = identity.user || {};
    return {quotas:quotas,account:{email:text(user.userName) || text(user.name)}};
}
