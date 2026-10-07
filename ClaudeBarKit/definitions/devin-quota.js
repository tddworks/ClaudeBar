// Devin's quota answer comes in two shapes: flat `daily_percentage` /
// `weekly_percentage` (a value below 1 is a fraction), or nested
// `quota_usage.{daily,weekly}_quota` with used/limit or remaining_percent.
function read(response) {
    var body = response.json;
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
        return { error: { parseFailed: "Failed to parse Devin's quota" } };
    }
    var nested = body.quota_usage || {};
    var quotas = [];

    if (body.hide_daily_quota !== true) {
        var daily = window(body.daily_percentage, body.daily_reset_at, nested.daily_quota);
        if (daily) quotas.push(quota('time', 'Daily', daily, 86400));
    }
    var weekly = window(body.weekly_percentage, body.weekly_reset_at, nested.weekly_quota);
    if (weekly) quotas.push(quota('weekly', null, weekly, 604800));
    if (!quotas.length) {
        return { error: { parseFailed: 'Devin sent no daily or weekly quota' } };
    }

    var overage = number(body.overage_balance);
    if (overage === null && number(body.overage_balance_cents) !== null) overage = number(body.overage_balance_cents) / 100;
    if (overage !== null) {
        quotas.push({ type: 'model', name: 'Extra usage', left: { money: String(overage), currency: 'USD' } });
    }

    var result = { quotas: quotas };
    var plan = body.plan_name || body.planName || body.plan || body.tier || body.subscription_tier;
    if (typeof plan === 'string' && plan.trim()) {
        result.plan = plan.trim().charAt(0).toUpperCase() + plan.trim().slice(1);
    }
    return result;
}

// The used percentage and reset of one window, from the flat or nested shape.
function window(percentage, resetAt, nested) {
    var used = number(percentage);
    if (used !== null) {
        return { used: used < 1 ? used * 100 : used, resetsAt: date(resetAt) };
    }
    if (!nested || typeof nested !== 'object') return null;
    var reset = date(nested.reset_at !== undefined ? nested.reset_at : nested.next_reset_at);
    var percent = number(nested.used_percent !== undefined ? nested.used_percent : nested.percentUsed);
    if (percent !== null) return { used: percent < 1 ? percent * 100 : percent, resetsAt: reset };
    var remaining = number(nested.remaining_percent);
    if (remaining !== null) return { used: 100 - (remaining <= 1 ? remaining * 100 : remaining), resetsAt: reset };
    var limit = number(nested.limit);
    if (limit !== null && limit > 0) {
        var count = number(nested.used);
        if (count === null && number(nested.remaining) !== null) count = limit - number(nested.remaining);
        if (count !== null) return { used: count / limit * 100, resetsAt: reset };
    }
    return null;
}

function quota(type, name, window, seconds) {
    var q = { type: type, percentRemaining: Math.max(0, 100 - window.used), windowSeconds: seconds };
    if (name) q.name = name;
    if (window.resetsAt !== null) q.resetsAt = window.resetsAt;
    return q;
}

function number(value) {
    if (typeof value === 'number' && isFinite(value)) return value;
    if (typeof value === 'string' && value.trim() !== '' && isFinite(Number(value))) return Number(value);
    return null;
}

// ISO 8601 text, or epoch seconds or milliseconds; epoch seconds out.
function date(value) {
    if (typeof value === 'number' && isFinite(value)) return value > 1e12 ? value / 1000 : value;
    if (typeof value !== 'string') return null;
    var parsed = Date.parse(value);
    return isNaN(parsed) ? null : parsed / 1000;
}
