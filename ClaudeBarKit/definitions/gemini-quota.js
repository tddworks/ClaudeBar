// Code Assist's per-model buckets: the lowest left of each model, a tier's
// aliases folded into one card, and no window — the response states none.
function read(response, context) {
    let data = response.json;
    // The quota step's answer; the project step only found the project.
    if (data && typeof data === 'object' && data.quota !== undefined && Object.keys(data).every(k => k === 'quota' || k === 'project')) data = data.quota;
    if (!data || !Array.isArray(data.buckets) || !data.buckets.length) return {error: {parseFailed: 'No quota buckets in response'}};
    const models = Object.create(null);
    for (const b of data.buckets) {
        if (typeof b.modelId !== 'string' || typeof b.remainingFraction !== 'number') continue;
        const old = models[b.modelId];
        if (!old || b.remainingFraction < old.fraction) models[b.modelId] = {model: b.modelId, fraction: b.remainingFraction, reset: b.resetTime || null};
    }
    const tier = id => { id = id.toLowerCase(); return id.includes('flash-lite') ? 'Flash Lite' : id.includes('flash') ? 'Flash' : id.includes('pro') ? 'Pro' : null; };
    const version = id => { const nums = id.toLowerCase().replace(/gemini-/g, '').split('-')[0].split('.').filter(n => n !== '' && isFinite(Number(n))).map(Number); return (nums[0] || 0) + (nums[1] || 0) / 100; };
    const preferred = (a, b) => { const ap = /preview/i.test(a), bp = /preview/i.test(b); if (ap !== bp) return !ap; const av = version(a), bv = version(b); return av !== bv ? av > bv : a < b; };
    const survivors = Object.create(null);
    for (const id of Object.keys(models)) {
        const row = models[id], label = tier(id), key = JSON.stringify([label ? 'tier:' + label : 'model:' + id, row.fraction, row.reset]);
        row.label = label || id;
        if (!survivors[key] || preferred(id, survivors[key].model)) survivors[key] = row;
    }
    const rows = Object.values(survivors).sort((a, b) => a.fraction - b.fraction || (a.model < b.model ? -1 : a.model > b.model ? 1 : 0));
    if (!rows.length) return {error: {parseFailed: 'No valid quotas found'}};
    return {quotas: rows.map(row => {
        const q = {type: 'model', name: row.label, percentRemaining: row.fraction * 100};
        if (typeof row.reset === 'string' && /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:?\d{2})$/.test(row.reset)) {
            const reset = Date.parse(row.reset) / 1000;
            if (isFinite(reset)) {
                q.resetsAt = reset;
                const seconds = reset - context.now;
                if (seconds > 0) {
                    const h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60);
                    q.resetText = h > 0 ? 'Resets in ' + h + 'h ' + m + 'm' : m > 0 ? 'Resets in ' + m + 'm' : 'Resets soon';
                }
            }
        }
        return q;
    })};
}
