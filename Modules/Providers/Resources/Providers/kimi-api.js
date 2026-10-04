function read(response) {
    const failure = message => ({error: {parseFailed: message}});
    const object = x => x && typeof x === 'object' && !Array.isArray(x);
    const detail = x => object(x) && typeof x.limit === 'string' && (x.resetTime == null || typeof x.resetTime === 'string')
        && (x.used == null || typeof x.used === 'string') && (x.remaining == null || typeof x.remaining === 'string');
    let data;
    try { data = JSON.parse(response.text); } catch (e) { return failure('Failed to decode Kimi response: ' + e.message); }
    if (!object(data) || !Array.isArray(data.usages)) return failure('Failed to decode Kimi response: no usages');
    const coding = data.usages.find(u => object(u) && u.scope === 'FEATURE_CODING');
    if (!coding) return failure('Missing FEATURE_CODING scope in response');
    if (!detail(coding.detail) || (coding.limits != null && !Array.isArray(coding.limits))) return failure('Failed to decode Kimi response: invalid usage');

    const integer = s => typeof s === 'string' && /^[+-]?\d+$/.test(s) && Number.isSafeInteger(Number(s)) ? Number(s) : null;
    const unitSeconds = {TIME_UNIT_SECOND: 1, TIME_UNIT_MINUTE: 60, TIME_UNIT_HOUR: 3600, TIME_UNIT_DAY: 86400};
    // A limit of 0 reports nothing left of nothing: no quota, never a made-up 100%.
    const quota = (d, fields) => {
        const limit = integer(d.limit);
        if (!limit || limit <= 0) return null;
        let used = integer(d.used), remaining = integer(d.remaining);
        if (used == null && remaining == null) return null;
        if (used == null) used = Math.max(0, limit - remaining);
        if (remaining == null) remaining = Math.max(0, limit - used);
        const q = Object.assign({percentRemaining: Math.max(0, Math.min(100, remaining / limit * 100))}, fields);
        q.resetText = used + '/' + limit + ' requests' + (fields.type === 'session' ? ' (5h)' : '');
        const date = Date.parse(d.resetTime || '');
        if (Number.isFinite(date)) q.resetsAt = date / 1000;
        return q;
    };

    // The plan isn't in the response; it is known by its quota's limit.
    // Those three plans are Kimi's weekly ones. Any other plan's quota states
    // no period, so it is "Plan" with no window rather than a guessed week.
    const tier = {1024: 'Andante', 2048: 'Moderato', 7168: 'Allegretto'}[integer(coding.detail.limit)];
    const quotas = [quota(coding.detail, tier ? {type: 'weekly', windowSeconds: 604800} : {type: 'time', name: 'Plan'})];

    // The rate limit states its own window: the 5-hour one, else the first.
    const limits = (coding.limits || []).filter(l => object(l) && object(l.window) && detail(l.detail));
    const seconds = l => Number.isInteger(l.window.duration) && unitSeconds[l.window.timeUnit] ? l.window.duration * unitSeconds[l.window.timeUnit] : null;
    const rate = limits.find(l => seconds(l) === 18000) || limits[0];
    if (rate) {
        const length = seconds(rate);
        quotas.push(quota(rate.detail, length === 18000 ? {type: 'session', windowSeconds: 18000}
            : {type: 'time', name: length ? (length % 3600 === 0 ? length / 3600 + 'h' : length / 60 + 'm') + ' limit' : 'Rate limit', windowSeconds: length}));
    }
    const result = {quotas: quotas.filter(Boolean)};
    if (tier) result.plan = tier;
    return result;
}
