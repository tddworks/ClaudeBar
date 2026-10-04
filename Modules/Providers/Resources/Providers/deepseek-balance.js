// A balance has no cap or quota window. Keep decimal strings intact for Swift.
function read(response) {
    var body = response.json;
    if (!body || typeof body !== "object" || Array.isArray(body)) {
        return { error: { parseFailed: "Invalid balance response" } };
    }
    if (body.balance_infos === undefined || body.balance_infos === null ||
        (Array.isArray(body.balance_infos) && body.balance_infos.length === 0)) {
        return { error: "noData" };
    }
    if (body.is_available !== undefined && body.is_available !== null && typeof body.is_available !== "boolean") {
        return { error: { parseFailed: "Invalid is_available" } };
    }
    if (!Array.isArray(body.balance_infos)) {
        return { error: { parseFailed: "Invalid balance_infos" } };
    }
    // DeepSeek lists the billing currency first. Never prefer a later USD entry.
    var balance = body.balance_infos[0];
    if (!balance || typeof balance.currency !== "string" || !balance.currency.trim() ||
        !amount(balance.total_balance)) {
        return { error: { parseFailed: "Invalid primary balance" } };
    }
    if (body.is_available === false) {
        return { error: { executionFailed: "DeepSeek reports that this balance is unavailable for API calls." } };
    }
    var symbol = { USD: "$", CNY: "¥", EUR: "€", GBP: "£" }[balance.currency] || balance.currency + " ";
    var details = [];
    if (amount(balance.topped_up_balance)) {
        details.push("Paid: " + symbol + Number(balance.topped_up_balance).toFixed(2));
    }
    if (amount(balance.granted_balance)) {
        details.push("Granted: " + symbol + Number(balance.granted_balance).toFixed(2));
    }
    return { quotas: [{
        type: "model", name: "Balance",
        left: { money: balance.total_balance, currency: balance.currency },
        resetText: details.length ? details.join(" · ") : null
    }] };
}

function amount(value) {
    return typeof value === "string" && isFinite(Number(value)) && /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/.test(value);
}
