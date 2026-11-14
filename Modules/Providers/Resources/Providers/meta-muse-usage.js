// Muse's versioned allowance envelope: percentages used and epoch-ms resets.
// Schema validation and reason/hint failures are not JSON mapping rules.
function read(response, context) {
    const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
    const text = value => typeof value === 'string' && value.trim() ? value.trim() : null;
    const failure = message => ({error: {parseFailed: message}});
    let payload;
    try { payload = JSON.parse(response.text); }
    catch (_) { return failure('Muse usage is not JSON'); }
    if (!object(payload) || payload.schemaVersion !== 1) {
        return failure('Unsupported Muse usage schema; expected schemaVersion 1');
    }

    const reason = text(payload.reason), hint = text(payload.hint);
    if (payload.allowance == null && (reason || hint)) {
        const message = [reason, hint].filter(Boolean).join('. ');
        const signIn = reason && /^(not[_ -](?:logged[_ -]in|authenticated)|(?:authentication|login)[_ -]required|session[_ -]expired)$/i.test(reason);
        return signIn ? {error: {sessionExpired: message}}
                      : {error: {executionFailed: 'Muse usage: ' + message}};
    }
    if (!object(payload.allowance)) return failure('Muse reported no allowance');

    const allowance = payload.allowance, quotas = [];
    for (const [key, type] of [['window', 'session'], ['weekly', 'weekly']]) {
        const window = allowance[key];
        if (window == null) continue;
        if (!object(window) || typeof window.usedPercent !== 'number'
                || !Number.isFinite(window.usedPercent) || window.usedPercent < 0 || window.usedPercent > 100) {
            return failure('Invalid Muse ' + key + ' allowance');
        }
        const quota = {type, percentRemaining: 100 - window.usedPercent};
        if (window.resetsAtMs != null) {
            if (typeof window.resetsAtMs !== 'number' || !Number.isFinite(window.resetsAtMs) || window.resetsAtMs < 0) {
                return failure('Invalid Muse ' + key + ' reset time');
            }
            quota.resetsAt = window.resetsAtMs / 1000;
        }
        // The payload names a week but gives no length for the session.
        if (key === 'weekly') quota.windowSeconds = 604800;
        else {
            quota.compactTitle = 'Session';
            quota.menuBarTitle = 'Session';
        }
        quotas.push(quota);
    }
    if (!quotas.length) return failure('Muse reported no quota windows');
    const result = {quotas};
    const tier = text(allowance.tier);
    if (tier) result.plan = tier;
    return result;
}
