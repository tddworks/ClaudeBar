// OpenRouter's credits endpoint reports the lifetime credit and the usage;
// the balance is their difference. Keep decimal strings intact for Swift.
function read(response) {
    var body = response.json;
    if (!body || typeof body !== "object" || Array.isArray(body)) {
        return { error: { parseFailed: "Invalid credits response" } };
    }
    if (body.data === undefined || body.data === null) {
        return { error: "noData" };
    }
    var credits = body.data;
    if (typeof credits !== "object" || Array.isArray(credits)) {
        return { error: { parseFailed: "Invalid credits data" } };
    }
    if (!amount(credits.total_credits) || !amount(credits.total_usage)) {
        return { error: { parseFailed: "Invalid credit amounts" } };
    }
    var remaining = decimalSubtract(credits.total_credits, credits.total_usage);
    return { quotas: [{
        type: "model", name: "Credits",
        left: { money: remaining, currency: "USD" },
        resetText: "Total: " + usd(credits.total_credits) + " · Used: " + usd(credits.total_usage)
    }] };
}

function amount(value) {
    if (typeof value === "number") return isFinite(value);
    return typeof value === "string" && isFinite(Number(value)) && /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/.test(value);
}

function decimalSubtract(a, b) {
    var x = decimalParts(a), y = decimalParts(b), scale = Math.max(x.scale, y.scale);
    return decimalText({ digits: x.digits * 10n ** BigInt(scale - x.scale) - y.digits * 10n ** BigInt(scale - y.scale), scale });
}

function usd(value) {
    return "$" + decimalCents(value);
}
