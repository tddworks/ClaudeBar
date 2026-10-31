// `omp usage --json`: every account omp tracks, each limit a quota grouped
// under its provider (and account, when one provider has several). A capped
// dollar limit is money left of its cap; spend with no cap, a balance with no
// limit, saved resets, an account with nothing measured and one omp signed
// out are notes under their group.
function read(response, context) {
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
                   'github-copilot': 'Copilot', 'kimi-code': 'Kimi', 'minimax-code': 'MiniMax', 'minimax-code-cn': 'MiniMax CN', 'opencode-go': 'OpenCode Go',
                   'alibaba-token-plan': 'Qwen Cloud', 'xai-oauth': 'Grok', 'commandcode': 'Command Code', 'cline-pass': 'ClinePass'};
    // What to check first when omp reports no usage for an account. Qwen
    // Cloud's Token Plan has a quota only through the console's cookie, an
    // optional step of `omp login` that its key alone skips, and the cookie
    // ends with the console session; a fetch that failed for another reason
    // lands here too, so this names the likely cause, not the certain one.
    const noUsage = {'alibaba-token-plan': "No usage · check omp's console cookie"};
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
    // A count to two decimals, grouped by thousands: 1,234.5.
    const count = v => { const n = num(v); const [whole, frac] = Math.abs(n).toFixed(2).replace(/\.?0+$/, '').split('.');
                         return (n < 0 ? '-' : '') + whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (frac ? '.' + frac : ''); };
    const nowMs = object(context) && num(context.now) != null ? num(context.now) * 1000 : Date.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    // An ISO time to epoch ms; the engine's Date reads at most milliseconds.
    const instant = t => { if (!str(t)) return null; const m = /^(.*?\.\d{3})\d*(Z|[+-]\d\d:\d\d)$/.exec(t);
                           const ms = Date.parse(m ? m[1] + m[2] : t); return Number.isFinite(ms) ? ms : null; };
    // Why omp signed an account out, in a few words: the provider's own
    // `error_description` when the cause carries one, else its first clause.
    const plainCause = c => {
        if (!str(c)) return null;
        const described = /\\?"error_description\\?"\s*:\s*\\?"([^"\\]+)/.exec(c);
        if (described) return described[1].trim();
        const clause = c.replace(/^oauth refresh failed:\s*/i, '').replace(/^[A-Za-z]*Error:\s*/, '').split(/[;\n]|\.\s/)[0].trim().replace(/\.$/, '');
        return clause.length > 80 ? clause.slice(0, 79) + '…' : (clause || null);
    };

    const limitOf = l => {
        const scope = object(l.scope) ? l.scope : {}, window = object(l.window) ? l.window : {}, amount = object(l.amount) ? l.amount : {};
        const monetary = typeof amount.unit === 'string' && amount.unit.toLowerCase() === 'usd';
        const windowToken = str(scope.windowId) || str(window.id) || str(window.label) || 'limit';
        const token = monetary ? (t => t.charAt(0).toUpperCase() + t.slice(1))(str(scope.windowId) || str(window.id) || 'spend') : windowToken;
        // `percent` and `unknown` name no unit: Devin's credit buckets and Kimi's rows are `unknown`.
        const unit = str(amount.unit) && !['percent', 'unknown'].includes(amount.unit.toLowerCase()) ? amount.unit : null;
        let percent = null;
        if (num(amount.remainingFraction) != null) percent = num(amount.remainingFraction) * 100;
        else if (num(amount.usedFraction) != null) percent = (1 - num(amount.usedFraction)) * 100;
        else if (num(amount.used) != null && num(amount.limit) > 0) percent = (num(amount.limit) - num(amount.used)) / num(amount.limit) * 100;
        else if (num(amount.remaining) != null && num(amount.limit) > 0) percent = num(amount.remaining) / num(amount.limit) * 100;
        // What is left with no limit to measure it against: a credit balance.
        const balance = percent == null && num(amount.remaining) != null && !(monetary && amount.used != null)
            ? (monetary ? money(amount.remaining) : count(amount.remaining) + (unit ? ' ' + unit.toLowerCase() : '')) + ' left' : null;
        // Spent of a cap, or what the cap leaves when omp reports only that.
        const spent = amount.used != null ? amount.used
            : (num(amount.remaining) != null && num(amount.limit) > 0 ? decimalAdd(amount.limit, decimalMultiply(amount.remaining, '-1')) : null);
        return {
            scope, window, amount, monetary, windowToken, token, percent, balance,
            name: str(l.label) ? l.label.trim() : null,
            groupKey: (scope.tier || '') + '|' + windowToken,
            capped: monetary && num(amount.limit) > 0 && spent != null ? {used: decimalCents(spent), cap: decimalCents(amount.limit)} : null,
            uncapped: monetary && amount.limit == null && amount.used != null ? decimalCents(amount.used) : null,
            meter: !monetary && unit ? capitalized(unit) : null,
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
        // One pool omp reports once per model family (Antigravity's Claude and
        // GPT) carries one `sharedGroup`: it is one quota, shown from the first
        // member with an amount to show.
        const quota = l => l.percent != null && (!l.monetary || l.capped != null);
        const shows = l => l.uncapped != null || quota(l);
        const pools = new Set();
        // Kimi reports its weekly quota twice: the `7d` row omp builds from
        // Kimi's summary, and Kimi's aggregate `limit_7d`, the same quota with
        // the same reset (omp drops the 5-hour aggregate, `limit_5h`, itself).
        // An aggregate `limit_<window>` beside a row that shows a quota for
        // that window is shown once, as that row; beside one with nothing to
        // show, the aggregate is that window's quota.
        const mapped = report.limits.filter(object).map(limitOf);
        const windows = new Set(mapped.filter(quota).map(l => l.windowToken));
        const limits = mapped.filter(l => {
            const aggregate = /^limit_(\d+[a-z]+)$/.exec(l.windowToken);
            if (aggregate && windows.has(aggregate[1])) return false;
            const pool = str(l.scope.sharedGroup);
            if (!pool || !shows(l)) return true;
            if (pools.has(pool)) return false;
            pools.add(pool);
            return true;
        });
        const perWindow = {};
        for (const l of limits) perWindow[l.groupKey] = (perWindow[l.groupKey] || 0) + 1;
        // Limits a (tier, window, meter) can't tell apart are named by omp's
        // own label when the labels differ (Antigravity's "Gemini" beside
        // "Claude & GPT (shared)"). Spend keeps its own names.
        const namesPerMeter = {};
        const meterKey = l => l.groupKey + '|' + (l.meter || '');
        for (const l of limits) if (!l.monetary && l.name) (namesPerMeter[meterKey(l)] = namesPerMeter[meterKey(l)] || new Set()).add(l.name);
        const before = quotas.length + notes.length;
        for (const l of limits) {
            if (l.uncapped != null) {
                const label = unique([providerName, l.token, 'Usage'].concat(discriminator ? ['· ' + discriminator] : []).join(' '), seenRows);
                notes.push({group, label, text: l.token + ' usage ' + money(l.uncapped) + ' spent · no cap'});
                continue;
            }
            if (l.balance != null) {
                notes.push({group, label: unique([providerName, l.name || l.token].concat(discriminator ? ['· ' + discriminator] : []).join(' '), seenRows), text: l.balance});
                continue;
            }
            if (l.monetary && !l.capped) continue;
            if (l.percent == null) continue;
            const meter = perWindow[l.groupKey] > 1 ? l.meter : null;
            const parts = [providerName];
            if (str(l.scope.tier)) parts.push(capitalized(l.scope.tier));
            if (meter) parts.push(meter);
            if (!l.monetary && l.name && namesPerMeter[meterKey(l)].size > 1) parts.push(l.name);
            parts.push(l.token);
            if (discriminator) parts.push('· ' + discriminator);
            const q = {type: 'time', name: unique(parts.join(' '), seenLabels), group};
            if (l.capped) q.left = {money: decimalAdd(l.capped.cap, '-' + l.capped.used), of: l.capped.cap, currency: 'USD'};
            else q.percentRemaining = l.percent;
            if (l.resetsAt != null) q.resetsAt = l.resetsAt;
            if (l.windowSeconds != null) q.windowSeconds = l.windowSeconds;
            quotas.push(q);
        }
        // Saved resets (Codex's and Claude's): how many, how many can be
        // spent now when that differs, and the soonest one to expire.
        const resets = object(report.resetCredits) ? report.resetCredits : {};
        const banked = Math.trunc(num(resets.availableCount) || 0);
        if (banked > 0) {
            const parts = [banked + ' saved reset' + (banked === 1 ? '' : 's')];
            const usable = num(resets.redeemableCount);
            if (usable != null && Math.trunc(usable) !== banked) parts.push(Math.trunc(usable) + ' usable now');
            const next = (Array.isArray(resets.credits) ? resets.credits : []).filter(object).map(c => instant(c.expiresAt))
                .filter(ms => ms != null && ms > nowMs).sort((a, b) => a - b)[0];
            if (next != null) { const day = new Date(next); parts.push('next expires ' + months[day.getMonth()] + ' ' + day.getDate()); }
            notes.push({group, label: unique(providerName + ' Saved resets' + (discriminator ? ' · ' + discriminator : ''), seenRows), text: parts.join(' · ')});
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
                    text: noUsage[a.provider] || 'No usage reported'});
    }
    // An account omp signed out (a Claude grant ends about 30 days after
    // login) is no report and no account without usage: without its own row
    // it would vanish. omp lists only those it signed out itself, not ones
    // replaced or deleted, and none that is signed in again.
    const signedOut = new Set();
    for (const d of Array.isArray(payload.disabledCredentials) ? payload.disabledCredentials : []) {
        if (!object(d) || typeof d.provider !== 'string') continue;
        const who = [d.email, d.accountId].find(str);
        const org = str(d.orgName) || str(d.orgId);
        if (who) {
            const key = [d.provider, email(who) || who, str(d.orgId) || org || ''].join('|');
            if (signedOut.has(key)) continue;
            signedOut.add(key);
        }
        const label = (who || 'OAuth account') + (org && org !== who ? ' · ' + org : '');
        const cause = plainCause(d.cause);
        notes.push({label: unique(displayName(d.provider) + ' · ' + label, seenRows), group: unique(displayName(d.provider) + ' · ' + shortIdentity(who || 'OAuth account'), seenGroups),
                    text: 'Signed out · ' + (cause ? cause + ' · ' : '') + 'run omp login'});
    }
    if (!quotas.length && !notes.length) return {error: 'noData'};

    const emails = new Set(payload.reports.map(r => (object(r.metadata) ? r.metadata : {}).email)
        .concat((payload.accountsWithoutUsage || []).map(a => object(a) ? a.email : null)).filter(str));
    const result = {quotas, notes};
    if (emails.size === 1) result.account = {email: [...emails][0]};
    return result;
}
