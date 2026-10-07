// The Vibe Coding Plan usage chat.mistral.ai knows, beside the local Vibe
// logs: one percent used and a reset date, inside an NDJSON answer — one JSON
// object per line, the numbers somewhere inside apiKey.getUsage's result.
function read(response) {
    const failure = message => ({error: {parseFailed: message}});
    const object = x => x && typeof x === 'object' && !Array.isArray(x);
    const lines = String(response.text || '').split('\n').map(line => line.trim()).filter(Boolean);
    if (!lines.length) return failure('Empty answer from chat.mistral.ai');
    let usage = null, message = null;
    const walk = value => {
        if (usage) return;
        if (Array.isArray(value)) { value.forEach(walk); return; }
        if (!object(value)) return;
        if (typeof value.usagePercentage === 'number') { usage = value; return; }
        if (message === null && typeof value.error === 'string') message = value.error;
        Object.values(value).forEach(walk);
    };
    for (const line of lines) {
        let parsed;
        try { parsed = JSON.parse(line); } catch (e) { return failure('Failed to decode Mistral answer: ' + e.message); }
        walk(parsed);
    }
    if (!usage) {
        if (message !== null) return {error: {executionFailed: 'Mistral API error: ' + message}};
        return {error: 'noData'};
    }
    const left = Math.max(0, 100 - usage.usagePercentage);
    const quota = {type: 'time', name: 'Vibe plan', percentRemaining: left};
    const reset = Date.parse(usage.resetAt || '');
    if (Number.isFinite(reset)) quota.resetsAt = reset / 1000;
    return {quotas: [quota]};
}
