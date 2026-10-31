// The plan Windsurf, now Devin Desktop, caches in its own database. Devin
// Desktop saves it under `windsurf.reactSettings.cachedPlanInfoData:<user id>`
// with the quota at the top level; Windsurf saved it under
// `windsurf.settings.cachedPlanInfo` with the quota in `quotaUsage`. The new
// key is read first and, of two signed-in accounts, the plan that runs longest.
// Daily and weekly quota left when the plan has them (unless it hides one),
// otherwise its message and flow-action allowances; Devin Desktop's free
// plan's message pool (`totalMessages`, -1 on a paid plan) shows beside them.
// The plan's period ends at `endTimestamp`, in milliseconds; 0 is no period.
function read(response, context) {
    var rows = Array.isArray(response.json) ? response.json : [];
    var text = function (row) { return row && typeof row.value === 'string' ? row.value.trim() : ''; };
    var parse = function (row) {
        var value;
        try { value = JSON.parse(text(row)); } catch (e) { value = null; }
        return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
    };
    var saved = rows.filter(function (row) { return typeof row.key === 'string' && row.key.indexOf('windsurf.reactSettings.cachedPlanInfoData') === 0 && text(row); });
    // A plan whose period has ended ranks below any that hasn't (0, no
    // period, included); then the one that runs longest.
    var ended = function (p) { var end = number(p.endTimestamp); return end !== null && end > 0 && end / 1000 < context.now; };
    var devin = saved.map(parse).filter(function (p) { return p; })
        .sort(function (a, b) { return (ended(a) - ended(b)) || ((number(b.endTimestamp) || 0) - (number(a.endTimestamp) || 0)); });
    var legacy = rows.filter(function (row) { return row.key === 'windsurf.settings.cachedPlanInfo' && text(row); })[0];
    if (!saved.length && !legacy) {
        return { error: { sessionExpired: 'Open Windsurf and sign in, so it saves your plan on this Mac.' } };
    }
    var plan = devin[0] || parse(legacy);
    if (!plan) {
        return { error: { parseFailed: "Failed to parse Windsurf's saved plan" } };
    }

    // Windsurf only updates its saved plan while it runs; a period that has
    // ended means the numbers are old, not that nothing was used.
    var ends = number(plan.endTimestamp);
    if (ends !== null && ends <= 0) ends = null;
    if (ends !== null && ends / 1000 < context.now) {
        return { error: { executionFailed: "Windsurf's saved plan is out of date. Open Windsurf to update it." } };
    }

    var quotas = [];
    var usage = plan.quotaUsage || plan;
    var hidden = function (flag) { return usage[flag] === true || plan[flag] === true; };
    var daily = hidden('hideDailyQuota') ? null : number(usage.dailyRemainingPercent);
    var weekly = hidden('hideWeeklyQuota') ? null : number(usage.weeklyRemainingPercent);
    if (daily !== null) quotas.push(left('time', 'Daily', daily, number(usage.dailyResetAtUnix), 86400));
    if (weekly !== null) quotas.push(left('weekly', null, weekly, number(usage.weeklyResetAtUnix), 604800));

    // Devin Desktop's message pool has no period, so no reset.
    var pool = number(plan.totalMessages), poolLeft = number(plan.remainingMessages);
    if (pool !== null && pool > 0 && poolLeft !== null && poolLeft >= 0) {
        quotas.push({ type: 'model', name: 'Messages', percentRemaining: Math.max(0, Math.min(100, poolLeft / pool * 100)),
                      resetText: (pool - poolLeft) + '/' + pool + ' used' });
    }

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
