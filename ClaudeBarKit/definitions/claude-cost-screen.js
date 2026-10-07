// Claude Code's `/cost` screen → API cost, for an API-billed account whose
// `/usage` has no plan quotas. Runs in JavaScriptCore with no I/O.
//
// Ported from the Swift probe this replaced; its tests pinned these patterns.

function read(response, context) {
  var screen = response.text;
  var lower = screen.toLowerCase();

  var error = usageError(lower);
  if (error) return { error: error };

  var total = /total\s+cost:\s*\$?([\d,]+\.?\d*)/i.exec(screen);
  if (!total) return { error: { parseFailed: "Could not find total cost" } };

  var duration = /total\s+duration\s*\(api\):\s*(.+?)(?:\n|$)/i.exec(screen);
  return {
    quotas: [],
    plan: "claudeApi",
    cost: {
      kind: "apiCost",
      used: total[1].trim().replace(/,/g, ""),
      apiDurationSeconds: duration ? seconds(duration[1].trim()) : 0
    }
  };
}

// "1h 2m 3.5s" → seconds; units missing from the text count as zero.
function seconds(text) {
  var total = 0;
  var hours = /(\d+(?:\.\d+)?)\s*h/i.exec(text);
  if (hours) total += parseFloat(hours[1]) * 3600;
  var minutes = /(\d+(?:\.\d+)?)\s*m(?!s)/i.exec(text);
  if (minutes) total += parseFloat(minutes[1]) * 60;
  var secs = /(\d+(?:\.\d+)?)\s*s/i.exec(text);
  if (secs) total += parseFloat(secs[1]);
  return total;
}

function usageError(lower) {
  if ((lower.indexOf("do you trust the files in this folder?") !== -1 ||
       lower.indexOf("is this a project you created or one you trust") !== -1) &&
      lower.indexOf("current session") === -1) {
    return "folderTrustRequired";
  }
  if (lower.indexOf("token_expired") !== -1 || lower.indexOf("token has expired") !== -1) return "authenticationRequired";
  if (lower.indexOf("authentication_error") !== -1) return "authenticationRequired";
  if (lower.indexOf("not logged in") !== -1 || lower.indexOf("please log in") !== -1) return "authenticationRequired";
  if (lower.indexOf("update required") !== -1 || lower.indexOf("please update") !== -1) return "updateRequired";
  if (lower.indexOf("/usage is only available for subscription plans") !== -1) return "subscriptionRequired";
  var rateLimited = (lower.indexOf("rate limited") !== -1 ||
                     lower.indexOf("rate limit exceeded") !== -1 ||
                     lower.indexOf("too many requests") !== -1) &&
                    lower.indexOf("rate limits are") === -1;
  if (rateLimited) return { executionFailed: "Rate limited - too many requests" };
  return null;
}
