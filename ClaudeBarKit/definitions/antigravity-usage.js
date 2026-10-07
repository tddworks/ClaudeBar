// Antigravity's quota, from the running app or from Google with its login.
// The quota summary states the shared pools by bucket; the older per-model
// answers state one quota per model. A 5-hour bucket is 5 hours, a weekly one
// a week; a model's quota is the 5-hour window.
function read(response) {
    const object = x => x && typeof x === 'object' && !Array.isArray(x);
    const date = v => {
        if (typeof v !== 'string' || !v) return null;
        const parsed = Date.parse(v);
        if (Number.isFinite(parsed)) return parsed / 1000;
        return Number.isFinite(Number(v)) ? Number(v) : null;
    };
    let data = response.json;
    if (!object(data)) return {error: {parseFailed: 'Invalid JSON: Antigravity answered no object'}};

    // From Google: every step's answer by name.
    let plan = null, email = null;
    const cloud = ['summaryDaily', 'summary', 'modelsDaily', 'models', 'planDaily', 'plan'].some(k => k in data);
    if (cloud) {
        for (const p of [data.planDaily, data.plan]) {
            if (!plan && object(p)) plan = (object(p.paidTier) && p.paidTier.name) || (object(p.currentTier) && p.currentTier.name) || null;
        }
        data = [data.summaryDaily, data.summary, data.modelsDaily, data.models].find(object) || {};
    }

    const quotas = [];
    // The quota summary: { "groups": [{ "buckets": [...] }] }, maybe inside "response".
    const groups = (object(data.response) && Array.isArray(data.response.groups)) ? data.response.groups : data.groups;
    if (Array.isArray(groups)) {
        const byId = {};
        for (const g of groups) for (const b of (object(g) && Array.isArray(g.buckets) ? g.buckets : [])) {
            if (object(b) && typeof b.bucketId === 'string' && !(b.bucketId in byId)) byId[b.bucketId] = b;
        }
        const specs = [['gemini-5h', {type: 'session', windowSeconds: 18000}], ['gemini-weekly', {type: 'weekly', windowSeconds: 604800}],
                       ['3p-5h', {type: 'model', name: 'Claude', windowSeconds: 18000}], ['3p-weekly', {type: 'model', name: 'Claude Weekly', windowSeconds: 604800}]];
        for (const [id, fields] of specs) {
            const b = byId[id];
            if (!b || typeof b.remainingFraction !== 'number' || !Number.isFinite(b.remainingFraction)) continue;
            const q = Object.assign({percentRemaining: b.remainingFraction * 100}, fields);
            const reset = date(b.resetTime); if (reset != null) q.resetsAt = reset;
            quotas.push(q);
        }
        if (quotas.length) return {quotas, plan: plan && plan.toUpperCase()};
    }

    // The per-model answers: the app's user status or model configs, or Google's models.
    const model = (label, info) => {
        if (!object(info)) return null;
        const q = {type: 'model', name: label, percentRemaining: (typeof info.remainingFraction === 'number' ? info.remainingFraction : 0) * 100, windowSeconds: 18000};
        const reset = date(info.resetTime); if (reset != null) q.resetsAt = reset;
        return q;
    };
    const status = object(data.userStatus) ? data.userStatus : null;
    const configs = status && object(status.cascadeModelConfigData) ? status.cascadeModelConfigData.clientModelConfigs : data.clientModelConfigs;
    if (Array.isArray(configs)) {
        for (const c of configs) if (object(c)) { const q = model(c.label, c.quotaInfo); if (q && c.label) quotas.push(q); }
        if (status) {
            email = typeof status.email === 'string' ? status.email : null;
            const name = object(status.planStatus) && object(status.planStatus.planInfo) ? status.planStatus.planInfo.planName : null;
            if (name) plan = name;
        }
    } else if (object(data.models)) {
        for (const key of Object.keys(data.models).sort()) {
            const m = data.models[key];
            if (!object(m) || m.isInternal === true) continue;
            const label = [m.displayName, m.label, key].map(v => typeof v === 'string' ? v.trim() : '').find(v => v) || key;
            const q = model(label, m.quotaInfo); if (q) quotas.push(q);
        }
    }
    if (!quotas.length) return {error: {parseFailed: 'No valid model quotas found'}};
    const result = {quotas};
    if (plan) result.plan = plan.toUpperCase();
    if (email) result.account = {email};
    return result;
}
