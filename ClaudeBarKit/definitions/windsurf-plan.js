// The plan Windsurf caches in its own database (`windsurf.settings.cachedPlanInfo`):
// daily and weekly quota left when the plan has them, otherwise its message
// and flow-action allowances. The plan's period ends at `endTimestamp`, in
// milliseconds.
function read(response, context) {
    var rows = Array.isArray(response.json) ? response.json : [];
    var text = rows.length && typeof rows[0].value === 'string' ? rows[0].value.trim() : '';
    if (!text) {
        return { error: { sessionExpired: 'Open Windsurf and sign in, so it saves your plan on this Mac.' } };
    }
    var plan;
    try { plan = JSON.parse(text); } catch (e) { plan = null; }
    if (!plan || typeof plan !== 'object' || Array.isArray(plan)) {
        return { error: { parseFailed: "Failed to parse Windsurf's saved plan" } };
    }

    // Windsurf only updates its saved plan while it runs; a period that has
    // ended means the numbers are old, not that nothing was used.
    var ends = number(plan.endTimestamp);
    if (ends !== null && ends / 1000 < context.now) {
        return { error: { executionFailed: "Windsurf's saved plan is out of date. Open Windsurf to update it." } };
    }

    var quotas = [];
    var usage = plan.quotaUsage || {};
    var daily = number(usage.dailyRemainingPercent), weekly = number(usage.weeklyRemainingPercent);
    if (daily !== null) quotas.push(left('time', 'Daily', daily, number(usage.dailyResetAtUnix), 86400));
    if (weekly !== null) quotas.push(left('weekly', null, weekly, number(usage.weeklyResetAtUnix), 604800));

    if (!quotas.length) {
        var allowance = plan.usage || {};
        [['Messages', 'messages', 'usedMessages', 'remainingMessages'],
         ['Flow actions', 'flowActions', 'usedFlowActions', 'remainingFlowActions']].forEach(function (k) {
            var total = number(allowance[k[1]]);
            if (total === null || total <= 0) return;
            var used = number(allowance[k[2]]);
            if (used === null && number(allowance[k[3]]) !== null) used = total - number(allowance[k[3]]);
            if (used === null) return;
            var q = { type: 'model', name: k[0], percentRemaining: Math.max(0, (total - used) / total * 100),
                      resetText: used + '/' + total + ' used' };
            if (ends !== null) q.resetsAt = ends / 1000;
            quotas.push(q);
        });
    }

    if (!quotas.length) return { error: 'noData' };
    var result = { quotas: quotas };
    if (typeof plan.planName === 'string' && plan.planName.trim()) result.plan = plan.planName.trim();
    return result;
}

function left(type, name, percent, resetsAt, seconds) {
    var q = { type: type, percentRemaining: Math.max(0, Math.min(100, percent)), windowSeconds: seconds };
    if (name) q.name = name;
    if (resetsAt !== null) q.resetsAt = resetsAt;
    return q;
}

function number(value) {
    if (typeof value === 'number' && isFinite(value)) return value;
    if (typeof value === 'string' && value.trim() !== '' && isFinite(Number(value))) return Number(value);
    return null;
}
