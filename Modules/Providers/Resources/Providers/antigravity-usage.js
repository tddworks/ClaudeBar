// Antigravity's quota, from the running app or from Google with its login.
// The quota summary states the shared pools by bucket; the older per-model
// answers state one quota per model. A 5-hour bucket is 5 hours, a weekly one
// a week; a model's quota is the 5-hour window. By 2026-10-31 Google's summary
// states the Claude and GPT pool alone for some accounts, with the Gemini pool
// left to the model list: the summary is read first, then the model list fills
// in the pools it left out.
function read(response) {
    const object = x => x && typeof x === 'object' && !Array.isArray(x);
    const date = v => {
        if (typeof v !== 'string' || !v) return null;
        const parsed = Date.parse(v);
        if (Number.isFinite(parsed)) return parsed / 1000;
        return Number.isFinite(Number(v)) ? Number(v) : null;
    };
    // One model's quota: the 5-hour window the model list states.
    const model = (label, info) => {
        if (!object(info)) return null;
        const q = {type: 'model', name: label, percentRemaining: (typeof info.remainingFraction === 'number' ? info.remainingFraction : 0) * 100, windowSeconds: 18000};
        const reset = date(info.resetTime); if (reset != null) q.resetsAt = reset;
        return q;
    };
    // The first model in the list whose key or name matches, its quota.
    const modelQuota = (models, pattern, label, excludePattern) => {
        for (const key of Object.keys(models).sort()) {
            const m = models[key];
            if (!object(m) || m.isInternal === true || !object(m.quotaInfo)) continue;
            const name = typeof m.displayName === 'string' ? m.displayName : key;
            if (excludePattern && (excludePattern.test(key) || excludePattern.test(name))) continue;
            if (!pattern.test(key) && !pattern.test(name)) continue;
            if (typeof m.quotaInfo.remainingFraction !== 'number' || !Number.isFinite(m.quotaInfo.remainingFraction)) continue;
            return model(label, m.quotaInfo);
        }
        return null;
    };
    let data = response.json;
    if (!object(data)) return {error: {parseFailed: 'Invalid JSON: Antigravity answered no object'}};

    // From Google: every step's answer by name. The summary is the pools; the
    // model list is the per-model quotas, and the second states what the first
    // leaves out.
    let plan = null, email = null, models = null;
    const cloud = ['summaryDaily', 'summary', 'modelsDaily', 'models', 'planDaily', 'plan'].some(k => k in data);
    if (cloud) {
        for (const p of [data.planDaily, data.plan]) {
            if (!plan && object(p)) plan = (object(p.paidTier) && p.paidTier.name) || (object(p.currentTier) && p.currentTier.name) || null;
        }
        models = [data.modelsDaily, data.models].find(object) || null;
        data = [data.summaryDaily, data.summary].find(object) || {};
    }

    const quotas = [];
    const stated = {};
    // The quota summary: { "groups": [{ "buckets": [...] }] }, maybe inside "response".
    const groups = (object(data.response) && Array.isArray(data.response.groups)) ? data.response.groups : data.groups;
    if (Array.isArray(groups)) {
        const byId = {};
        let fallbackArgon = null;
        for (const g of groups) for (const b of (object(g) && Array.isArray(g.buckets) ? g.buckets : [])) {
            if (!object(b)) continue;
            const id = typeof b.bucketId === 'string' ? b.bucketId : typeof b.id === 'string' ? b.id : null;
            if (id && !(id in byId)) byId[id] = b;
            if (id && id.includes('argon') && !fallbackArgon) fallbackArgon = b;
        }
        if (!('gemini-argon-wtu-weekly' in byId) && fallbackArgon) {
            byId['gemini-argon-wtu-weekly'] = fallbackArgon;
        }
        const specs = [['gemini-5h', {type: 'session', windowSeconds: 18000}], ['gemini-weekly', {type: 'weekly', windowSeconds: 604800}],
                       ['3p-5h', {type: 'model', name: 'Claude 5h', windowSeconds: 18000}], ['3p-weekly', {type: 'model', name: 'Claude 7d', windowSeconds: 604800}],
                       ['gemini-argon-wtu-weekly', {type: 'model', name: 'Argon Weekly', windowSeconds: 604800}]];
        for (const [id, fields] of specs) {
            const b = byId[id];
            if (!b) continue;
            const remaining = typeof b.remainingFraction === 'number' ? b.remainingFraction :
                              typeof b.remaining_fraction === 'number' ? b.remaining_fraction : null;
            if (remaining == null || !Number.isFinite(remaining)) continue;
            const q = Object.assign({percentRemaining: remaining * 100}, fields);
            const reset = date(b.resetTime || b.reset_time); if (reset != null) q.resetsAt = reset;
            quotas.push(q);
            stated[id] = true;
        }
    }
    // Gemini's pool, when the summary didn't state it: the model list does,
    // every Gemini model in it sharing one pool, and Argon its own.
    if (object(models) && object(models.models)) {
        if (!stated['gemini-5h']) {
            const gemini = modelQuota(models.models, /gemini/i, 'Gemini 5h', /argon/i);
            if (gemini) quotas.push(gemini);
        }
        const argon = modelQuota(models.models, /argon/i, 'Argon 5h');
        if (argon) quotas.push(argon);
    }
    if (quotas.length) {
        const result = {quotas};
        if (plan) result.plan = plan.toUpperCase();
        return result;
    }

    // The per-model answers: the running app's user status or model configs, or Google's models.
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
