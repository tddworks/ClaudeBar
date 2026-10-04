// MiniMax Token Plan response, including legacy remaining-count responses.
function read(response, context) {
    const body = response.json;
    if (!body || !body.base_resp || !Number.isInteger(body.base_resp.status_code))
        return {error: {parseFailed: "Invalid MiniMax response"}};
    if (body.base_resp.status_code !== 0)
        return {error: {executionFailed: "MiniMax API error: " + (body.base_resp.status_msg || "Unknown error")}};
    if (body.model_remains == null) return {error:"noData"};
    if (!Array.isArray(body.model_remains)) return {error: {parseFailed: "Invalid MiniMax model remains"}};
    const quotas = [];
    const clamp = n => Math.max(0, Math.min(100, n));
    const window = (start, end) => typeof start === "number" && typeof end === "number" && end > start ? (end-start)/1000 : null;
    for (const model of body.model_remains) {
        if (typeof model.model_name !== "string" || !Number.isInteger(model.current_interval_total_count) || !Number.isInteger(model.current_interval_usage_count))
            return {error: {parseFailed: "Invalid MiniMax model remains"}};
        const total = model.current_interval_total_count;
        const remaining = Math.max(0, Math.min(Math.max(0,total), model.current_interval_usage_count));
        const reported = typeof model.current_interval_remaining_percent === "number";
        if (reported || total > 0) {
            const percent = reported ? clamp(model.current_interval_remaining_percent) : remaining / total * 100;
            quotas.push({type:"model", name:model.model_name, percentRemaining:percent,
                resetsAt:typeof model.end_time === "number" ? model.end_time/1000 : null,
                windowSeconds:window(model.start_time,model.end_time),
                resetText:reported ? Math.round(100-percent)+"% used" : (total-remaining)+"/"+total+" requests"});
        }
        if (typeof model.current_weekly_remaining_percent === "number") {
            const percent = clamp(model.current_weekly_remaining_percent);
            quotas.push({type:"time", name:model.model_name+" Weekly", percentRemaining:percent,
                resetsAt:typeof model.weekly_end_time === "number" ? model.weekly_end_time/1000 : null,
                windowSeconds:window(model.weekly_start_time, model.weekly_end_time), resetText:Math.round(100-percent)+"% used"});
        }
    }
    return quotas.length ? {quotas:quotas} : {error:"noData"};
}
