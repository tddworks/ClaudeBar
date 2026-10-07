// The AI quota a JetBrains IDE saves in AIAssistantQuotaManager2.xml: JSON
// inside the HTML-encoded `value` of its `quotaInfo` and `nextRefill`
// options. Numbers come as text. The refill period is an ISO 8601 duration.
function read(response) {
    var info = option(response.text || '', 'quotaInfo');
    if (!info) return { error: { parseFailed: "Couldn't find the AI quota in the IDE's file" } };
    // An IDE with no AI quota saves `Unknown`; one that failed to get it, `Error`.
    if (info.type === 'Unknown') return { error: { sessionExpired: 'Sign in to JetBrains AI in your IDE, then use AI Assistant once.' } };
    if (info.type === 'Error') return { error: { executionFailed: "Your JetBrains IDE couldn't get the AI quota. Open AI Assistant in it to try again." } };
    var used = number(info.current), maximum = number(info.maximum);
    if (used === null || maximum === null) return { error: { parseFailed: "Couldn't read the IDE's AI quota" } };

    var quota = {
        type: 'time', name: 'AI credits',
        percentRemaining: maximum > 0 ? Math.max(0, Math.min(100, (maximum - used) / maximum * 100)) : 0
    };
    var refill = option(response.text, 'nextRefill');
    if (refill) {
        var next = typeof refill.next === 'string' ? Date.parse(refill.next) : NaN;
        if (!isNaN(next)) quota.resetsAt = next / 1000;
        var tariff = refill.tariff || refill;
        var seconds = duration(tariff.duration);
        if (seconds !== null) quota.windowSeconds = seconds;
    }
    return { quotas: [quota] };
}

// The JSON in `<option name="NAME" value="…" />`, or null.
function option(xml, name) {
    var match = new RegExp('<option[^>]*name="' + name + '"[^>]*value="([^"]*)"').exec(xml);
    if (!match) return null;
    var text = match[1]
        .replace(/&#(\d+);/g, function (_, code) { return String.fromCharCode(Number(code)); })
        .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&');
    try { var value = JSON.parse(text); return value && typeof value === 'object' ? value : null; } catch (e) { return null; }
}

function number(value) {
    if (typeof value === 'number' && isFinite(value)) return value;
    if (typeof value === 'string' && value.trim() !== '' && isFinite(Number(value))) return Number(value);
    return null;
}

// `PT720H`, `P30D`, `PT30M` → seconds.
function duration(text) {
    var match = typeof text === 'string' ? /^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(text) : null;
    if (!match) return null;
    var seconds = (Number(match[1] || 0) * 86400) + (Number(match[2] || 0) * 3600) + (Number(match[3] || 0) * 60) + Number(match[4] || 0);
    return seconds > 0 ? seconds : null;
}
