function read(response, context) {
    const quotas = [], seen = {};
    const lines = response.text.split(/\r?\n/);
    for (const line of lines) {
        const lower = line.toLowerCase();
        const kind = lower.includes('weekly') ? 'weekly' : lower.includes('monthly') ? 'monthly' : /5h|hour/.test(lower) ? 'session' : null;
        // The TUI redraws the panel; the first of each is the one.
        if (!kind || seen[kind]) continue;
        let percent, reset, match;
        if (lower.includes('% left')) {
            match = line.match(/(\d+)%\s+left/); if (!match) continue;
            percent = Number(match[1]);
            const m = lower.match(/\(resets\s+in\s+(.+?)\)/); if (m) reset = m[1].trim();
        } else if (lower.includes('% used')) {
            match = line.match(/(\d+)\s*%\s*used/); if (!match) continue;
            percent = Math.max(0, 100 - Number(match[1]));
            const m = lower.match(/resets\s+in\s+([0-9dhms ]+)/); if (m) reset = m[1].trim();
        } else continue;

        const q = {percentRemaining: percent};
        if (kind === 'weekly') { q.type = 'weekly'; q.windowSeconds = 604800; }
        else if (kind === 'session') { q.type = 'session'; q.windowSeconds = 18000; }
        else { q.type = 'time'; q.name = 'Monthly'; }
        if (reset) {
            q.resetText = 'Resets in ' + reset;
            let seconds = 0;
            [['d', 86400], ['h', 3600], ['m', 60], ['s', 1]].forEach(([unit, size]) => {
                const m = reset.match(new RegExp('(\\d+)\\s*' + unit)); if (m) seconds += Number(m[1]) * size;
            });
            if (seconds > 0) {
                q.resetsAt = context.now + seconds;
                if (kind === 'monthly') {
                    // The month that ends on the reset date — its real length.
                    const end = new Date(q.resetsAt * 1000);
                    const start = new Date(end.getFullYear(), end.getMonth() - 1, end.getDate(), end.getHours(), end.getMinutes(), end.getSeconds());
                    q.windowSeconds = (end.getTime() - start.getTime()) / 1000;
                }
            }
        }
        quotas.push(q);
        seen[kind] = true;
    }
    if (quotas.length) return {quotas};
    // The CLI answers /usage this way when it isn't signed in.
    if (/authorization failed|please (log ?in|login)|not logged in/i.test(response.text)) {
        return {error: {sessionExpired: 'Run `kimi` and sign in with /login.'}};
    }
    return {error: {parseFailed: 'No quota data found in Kimi CLI output'}};
}
