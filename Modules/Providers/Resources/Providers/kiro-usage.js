// Kiro's plain /usage output, with dates in the Mac's own time zone.
function read(response, context) {
    const text = response.text.replace(/\u001B\[[0-9;]*[a-zA-Z]/g, "");
    const now = new Date(context.now * 1000);
    const quotas = [];
    const bonus = text.match(/Bonus credits:\s*([\d.]+)\/([\d.]+)/);
    if (bonus && Number(bonus[2]) > 0) {
        // A grant that expires, not a window that refills: no window length.
        const expiry = text.match(/expires in (\d+) days/);
        const days = expiry ? Number(expiry[1]) : null;
        quotas.push({type: "time", name: "Bonus credits",
            percentRemaining: Math.max(0, (Number(bonus[2]) - Number(bonus[1])) / Number(bonus[2]) * 100),
            resetsAt: days === null ? null : context.now + days * 86400,
            resetText: days === null ? null : "Expires in " + days + " days"});
    }
    const credits = text.match(/Credits \(([\d.]+) of ([\d.]+)/);
    if (credits && Number(credits[2]) > 0) {
        const reset = text.match(/resets on (\d{2})\/(\d{2})/);
        let date = null, windowSeconds = null;
        if (reset) {
            date = new Date(now.getFullYear(), Number(reset[1]) - 1, Number(reset[2]));
            if (date < now) date = new Date(now.getFullYear() + 1, Number(reset[1]) - 1, Number(reset[2]));
            // The month that ends on the reset date — its real length.
            const start = new Date(date.getFullYear(), date.getMonth() - 1, date.getDate());
            windowSeconds = (date.getTime() - start.getTime()) / 1000;
        }
        quotas.push({type: "time", name: "Monthly",
            percentRemaining: Math.max(0, (Number(credits[2]) - Number(credits[1])) / Number(credits[2]) * 100),
            resetsAt: date ? date.getTime() / 1000 : null,
            resetText: reset ? "Resets on " + reset[1] + "/" + reset[2] : null, windowSeconds: windowSeconds});
    }
    return quotas.length ? {quotas: quotas} : {error: {parseFailed: "No quota data found in Kiro CLI output"}};
}
