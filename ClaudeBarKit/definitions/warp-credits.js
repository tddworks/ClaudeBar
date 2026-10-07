// Warp's GraphQL answer: the monthly credits, and the add-on credits granted
// to the person and to each of their workspaces. Warp sends some numbers and
// booleans as text, and reports a refused key as `errors` with a 200.
function read(response) {
    var body = response.json;
    if (!body || typeof body !== 'object') {
        return { error: { parseFailed: "Failed to parse Warp's credits" } };
    }
    if (Array.isArray(body.errors) && body.errors.length) {
        var messages = body.errors.map(function (e) { return e && e.message; }).filter(Boolean).slice(0, 3);
        if (messages.some(function (m) { return /unauthori[sz]ed|unauthenticated|invalid api key/i.test(m); })) {
            return { error: { sessionExpired: 'Create a new API key in Warp: Settings → Platform → API Keys.' } };
        }
        return { error: { executionFailed: 'Warp: ' + (messages.join('; ') || 'unknown error') } };
    }
    var user = body.data && body.data.user && body.data.user.user;
    var info = user && user.requestLimitInfo;
    if (!info) {
        return { error: { parseFailed: 'Warp sent no request limit' } };
    }

    var quotas = [];
    if (flag(info.isUnlimited)) {
        quotas.push({ type: 'time', name: 'Monthly', percentRemaining: 100, resetText: 'Unlimited' });
    } else {
        var limit = number(info.requestLimit), used = number(info.requestsUsedSinceLastRefresh);
        if (limit === null || used === null) {
            return { error: { parseFailed: 'Warp sent no request limit' } };
        }
        var monthly = {
            type: 'time', name: 'Monthly',
            percentRemaining: limit > 0 ? Math.max(0, (limit - used) / limit * 100) : 0,
            resetText: used + '/' + limit + ' credits'
        };
        var refresh = date(info.nextRefreshTime);
        if (refresh !== null) monthly.resetsAt = refresh;
        quotas.push(monthly);
    }

    var grants = (Array.isArray(user.bonusGrants) ? user.bonusGrants : []);
    (Array.isArray(user.workspaces) ? user.workspaces : []).forEach(function (workspace) {
        var more = workspace && workspace.bonusGrantsInfo && workspace.bonusGrantsInfo.grants;
        if (Array.isArray(more)) grants = grants.concat(more);
    });
    var granted = 0, remaining = 0, soonest = null;
    grants.forEach(function (grant) {
        var g = number(grant && grant.requestCreditsGranted), r = number(grant && grant.requestCreditsRemaining);
        if (g === null || r === null) return;
        granted += g;
        remaining += r;
        var expires = date(grant.expiration);
        if (r > 0 && expires !== null && (soonest === null || expires < soonest)) soonest = expires;
    });
    if (granted > 0) {
        var addOn = {
            type: 'model', name: 'Add-on',
            percentRemaining: Math.max(0, remaining / granted * 100),
            resetText: remaining + '/' + granted + ' credits left'
        };
        if (soonest !== null) addOn.resetsAt = soonest;
        quotas.push(addOn);
    }
    return { quotas: quotas };
}

function number(value) {
    if (typeof value === 'number' && isFinite(value)) return value;
    if (typeof value === 'string' && value.trim() !== '' && isFinite(Number(value))) return Number(value);
    return null;
}

function flag(value) {
    return value === true || value === 'true' || value === '1' || value === 1;
}

// Epoch seconds, fractional seconds kept; JavaScriptCore reads at most milliseconds.
function date(text) {
    if (typeof text !== 'string') return null;
    var match = /^(.*?\.\d{3})\d*(Z|[+-]\d\d:\d\d)$/.exec(text);
    var parsed = Date.parse(match ? match[1] + match[2] : text);
    return isNaN(parsed) ? null : parsed / 1000;
}
