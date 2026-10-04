// `omp usage --json`: every account omp tracks, each limit a quota grouped
// under its provider (and account, when one provider has several). A capped
// dollar limit is money left of its cap; spend with no cap, and an account
// with nothing measured, are a note under their group.
function read(response) {
    const text = response.text;
    const start = text.indexOf('{'), end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return {error: {parseFailed: 'No JSON object in omp usage output'}};
    let payload;
    // Numbers stay exact texts: dollars are money.
    try { payload = jsonDecimal(text.slice(start, end + 1)); } catch (e) { return {error: {parseFailed: 'Malformed omp usage JSON: ' + e.message}}; }
    const object = x => x && typeof x === 'object' && !Array.isArray(x);
    if (!object(payload) || !Array.isArray(payload.reports) || payload.reports.some(r => !object(r) || typeof r.provider !== 'string' || !Array.isArray(r.limits))) {
        return {error: {parseFailed: 'Malformed omp usage JSON: reports'}};
    }
    const num = v => v == null || v === '' ? null : (Number.isFinite(Number(v)) ? Number(v) : null);
    const str = v => typeof v === 'string' && v ? v : null;
    const capitalized = s => s.split(/(\s+)/).map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join('');
    const names = {'anthropic': 'Claude', 'openai-codex': 'Codex', 'zai': 'Z.ai', 'google-gemini-cli': 'Gemini', 'google-antigravity': 'Antigravity',
                   'github-copilot': 'Copilot', 'kimi-code': 'Kimi', 'minimax-code': 'MiniMax', 'minimax-code-cn': 'MiniMax CN', 'opencode-go': 'OpenCode Go'};
    const displayName = id => names[id] || id.split('-').map(p => p.charAt(0).toUpperCase() + p.slice(1)).join(' ');
    const unique = (base, seen) => {
        let label = base;
        if (seen.has(label)) { let n = 2; while (seen.has(label + ' (' + n + ')')) n++; label = label + ' (' + n + ')'; }
        seen.add(label);
        return label;
    };
    const shortIdentity = id => id.includes('@') ? id.split('@')[0].slice(0, 16) : id.slice(0, 16);
    const money = v => { const cents = decimalCents(v); const [whole, frac] = cents.replace('-', '').split('.');
                         return (cents.startsWith('-') ? '-' : '') + '$' + whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',') + '.' + frac; };

    const limitOf = l => {
        const scope = object(l.scope) ? l.scope : {}, window = object(l.window) ? l.window : {}, amount = object(l.amount) ? l.amount : {};
        const monetary = typeof amount.unit === 'string' && amount.unit.toLowerCase() === 'usd';
        const windowToken = str(scope.windowId) || str(window.id) || str(window.label) || 'limit';
        const token = monetary ? (t => t.charAt(0).toUpperCase() + t.slice(1))(str(scope.windowId) || str(window.id) || 'spend') : windowToken;
        let percent = null;
        if (num(amount.remainingFraction) != null) percent = num(amount.remainingFraction) * 100;
        else if (num(amount.usedFraction) != null) percent = (1 - num(amount.usedFraction)) * 100;
        else if (num(amount.used) != null && num(amount.limit) > 0) percent = (num(amount.limit) - num(amount.used)) / num(amount.limit) * 100;
        return {
            scope, window, amount, monetary, token, percent,
            groupKey: (scope.tier || '') + '|' + windowToken,
            capped: monetary && num(amount.limit) > 0 && amount.used != null ? {used: decimalCents(amount.used), cap: decimalCents(amount.limit)} : null,
            uncapped: monetary && amount.limit == null && amount.used != null ? decimalCents(amount.used) : null,
            meter: !monetary && str(amount.unit) && amount.unit.toLowerCase() !== 'percent' ? capitalized(amount.unit) : null,
            resetsAt: num(window.resetsAt) != null ? num(window.resetsAt) / 1000 : null,
            windowSeconds: num(window.durationMs) > 0 ? num(window.durationMs) / 1000 : null,
        };
    };
    const identityOf = r => {
        const m = object(r.metadata) ? r.metadata : {};
        for (const v of [m.email, m.accountId, m.projectId]) if (str(v)) return v;
        for (const l of r.limits) { const s = object(l.scope) ? l.scope : {}; const v = str(s.accountId) || str(s.projectId); if (v) return v; }
        return null;
    };
    const accountIdOf = r => {
        const m = object(r.metadata) ? r.metadata : {};
        if (str(m.accountId)) return m.accountId;
        for (const l of r.limits) if (object(l.scope) && str(l.scope.accountId)) return l.scope.accountId;
        return null;
    };
    const email = e => typeof e === 'string' && e.trim() ? e.trim().toLowerCase() : null;
    const hasOrg = o => typeof o === 'string' && o.length > 0;
    // The same login: one provider, no organization, the same email — else the same account id.
    const sameLogin = (a, b) => {
        if (a.provider !== b.provider || hasOrg(a.orgId)) return false;
        if (email(a.email) && email(b.email)) return email(a.email) === email(b.email);
        return !!(str(a.accountId) && str(b.accountId)) && a.accountId === b.accountId;
    };

    const perProvider = {};
    for (const r of payload.reports) perProvider[r.provider] = (perProvider[r.provider] || 0) + 1;
    const quotas = [], notes = [], seenLabels = new Set(), seenGroups = new Set(), seenRows = new Set();
    payload.reports.forEach((report, index) => {
        const identity = identityOf(report);
        const discriminator = perProvider[report.provider] > 1
            ? (identity ? (identity.includes('@') ? identity.split('@')[0].slice(0, 16) : identity.slice(0, 8)) : '#' + (index + 1)) : null;
        const providerName = displayName(report.provider);
        const group = discriminator ? providerName + ' · ' + discriminator : providerName;
        const limits = report.limits.filter(object).map(limitOf);
        const perWindow = {};
        for (const l of limits) perWindow[l.groupKey] = (perWindow[l.groupKey] || 0) + 1;
        const before = quotas.length + notes.length;
        for (const l of limits) {
            if (l.uncapped != null) {
                const label = unique([providerName, l.token, 'Usage'].concat(discriminator ? ['· ' + discriminator] : []).join(' '), seenRows);
                notes.push({group, label, text: l.token + ' usage ' + money(l.uncapped) + ' spent · no cap'});
                continue;
            }
            if (l.monetary && !l.capped) continue;
            if (l.percent == null) continue;
            const meter = perWindow[l.groupKey] > 1 ? l.meter : null;
            const parts = [providerName];
            if (str(l.scope.tier)) parts.push(capitalized(l.scope.tier));
            if (meter) parts.push(meter);
            parts.push(l.token);
            if (discriminator) parts.push('· ' + discriminator);
            const q = {type: 'time', name: unique(parts.join(' '), seenLabels), group};
            if (l.capped) q.left = {money: decimalAdd(l.capped.cap, '-' + l.capped.used), of: l.capped.cap, currency: 'USD'};
            else q.percentRemaining = l.percent;
            if (l.resetsAt != null) q.resetsAt = l.resetsAt;
            if (l.windowSeconds != null) q.windowSeconds = l.windowSeconds;
            quotas.push(q);
        }
        if (quotas.length + notes.length > before) seenGroups.add(group);
        else {
            const who = identity || discriminator || 'account ' + (index + 1);
            notes.push({label: unique(providerName + ' · ' + who, seenRows), group: unique(providerName + ' · ' + shortIdentity(who), seenGroups), text: 'No usage reported'});
        }
    });

    const reported = payload.reports.map(r => ({provider: r.provider, email: (object(r.metadata) ? r.metadata : {}).email, accountId: accountIdOf(r)}));
    const emitted = [];
    for (const a of Array.isArray(payload.accountsWithoutUsage) ? payload.accountsWithoutUsage : []) {
        if (!object(a) || typeof a.provider !== 'string') continue;
        if (reported.some(r => sameLogin(a, r))) continue;
        if (emitted.some(e => !hasOrg(e.orgId) && sameLogin(a, e))) continue;
        emitted.push(a);
        const label = a.type === 'api_key' ? 'API key' : ([a.email, a.accountId, a.projectId, a.enterpriseUrl].find(str) || 'OAuth account');
        notes.push({label: unique(displayName(a.provider) + ' · ' + label, seenRows), group: unique(displayName(a.provider) + ' · ' + shortIdentity(label), seenGroups),
                    text: 'No usage reported'});
    }
    if (!quotas.length && !notes.length) return {error: 'noData'};

    const emails = new Set(payload.reports.map(r => (object(r.metadata) ? r.metadata : {}).email)
        .concat((payload.accountsWithoutUsage || []).map(a => object(a) ? a.email : null)).filter(str));
    const result = {quotas, notes};
    if (emails.size === 1) result.account = {email: [...emails][0]};
    return result;
}
