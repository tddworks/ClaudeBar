// Claude Code's `/usage` screen → usage.
//
// Runs in JavaScriptCore with no file, network or process access. The screen
// arrives already drawn by a terminal emulator (`"screen": "rendered"`), so
// labels sit on the rows the TUI painted them on. Reset times go through the
// host's `humanDate(text)`, which answers epoch seconds or null.
//
// Ported line for line from the Swift probe this replaced; the phrases,
// windows and regexes are the ones its tests pinned.

var SUBSCRIPTION_MISREAD =
  "The Claude CLI did not see this account's subscription — its usage screen reported API billing " +
  "instead of a plan. Run `claude login` again, or switch Claude to API mode in Settings.";

function read(response, context) {
  var screen = response.text;
  var lower = screen.toLowerCase();
  var lines = splitLines(screen);
  var account = context.account || {};
  var subscriptionBilled = typeof account.billingType === "string" && /_subscription$/.test(account.billingType);

  var error = usageError(lower);
  if (error) {
    if (error === "subscriptionRequired" && subscriptionBilled) {
      return { error: { executionFailed: SUBSCRIPTION_MISREAD } };
    }
    return { error: error };
  }

  var plan = planFrom(lower);
  var session = percent(lines, ["Current session"]);
  if (session === null) {
    if (lower.indexOf("loading usage data") !== -1) {
      return { error: { executionFailed: "Claude usage data did not finish loading — the usage endpoint may be rate limited. Try again in a moment." } };
    }
    if (lower.indexOf("api usage billing") !== -1 && lower.indexOf("total cost:") !== -1) {
      // An API-billed account: hand off to `/cost`, unless the account is
      // really a subscription the CLI misread (#271/#317).
      return { error: subscriptionBilled ? { executionFailed: SUBSCRIPTION_MISREAD } : "subscriptionRequired" };
    }
    return { error: { parseFailed: "Could not find session usage" } };
  }

  var sessionReset = resetText(lines, "Current session");
  var weeklyReset = resetText(lines, "Current week");
  var quotas = [quota("session", null, session, sessionReset)];

  var weekly = percent(lines, ["Current week (all models)"]);
  if (weekly !== null) quotas.push(quota("weekly", null, weekly, weeklyReset));

  var opus = percent(lines, ["Current week (Opus)"]);
  if (opus !== null) quotas.push(quota("model", "opus", opus, weeklyReset));

  var sonnet = percent(lines, ["Current week (Sonnet only)", "Current week (Sonnet)"]);
  if (sonnet !== null) quotas.push(quota("model", "sonnet", sonnet, weeklyReset));

  var fable = percent(lines, ["Current week (Fable"]);
  if (fable !== null) {
    var fableReset = resetText(lines, "Current week (Fable");
    quotas.push(quota("model", "fable", fable, fableReset !== null ? fableReset : weeklyReset));
  }

  var result = { quotas: quotas, plan: plan };
  var cost = extraUsage(screen, lower, lines);
  if (cost) result.cost = cost;
  if (account.email || account.organization) {
    result.account = { email: account.email || null, organization: account.organization || null };
  }
  return result;
}

// MARK: - Screen pieces

// Swift's `components(separatedBy: .newlines)`: every newline character splits.
function splitLines(text) {
  return text.split(/[\n\r\u000B\u000C\u0085\u2028\u2029]/);
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
  // Not `rateLimited`: the CLI's limit is not the API's, so the API fallback still runs.
  if (rateLimited) return { executionFailed: "Rate limited - too many requests" };
  return null;
}

// The header names the plan; a screen without one is a Max subscription.
function planFrom(lower) {
  if (lower.indexOf("· claude pro") !== -1 || lower.indexOf("·claude pro") !== -1) return "claudePro";
  return "claudeMax";
}

// The first "NN% used|left" within 12 lines of a label, as percent left.
function percent(lines, labels) {
  for (var l = 0; l < labels.length; l++) {
    var label = labels[l].toLowerCase();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().indexOf(label) === -1) continue;
      for (var j = i; j < Math.min(lines.length, i + 12); j++) {
        var match = /([0-9]{1,3})\s*%\s*(used|left)/i.exec(lines[j]);
        if (match) {
          var value = parseInt(match[1], 10);
          return match[2].toLowerCase() === "used" ? Math.max(0, 100 - value) : value;
        }
      }
    }
  }
  return null;
}

// The reset line within 14 lines of a label, without a redraw's repeats.
function resetText(lines, labelText) {
  var label = labelText.toLowerCase();
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].toLowerCase().indexOf(label) === -1) continue;
    for (var j = i; j < Math.min(lines.length, i + 14); j++) {
      var lower = lines[j].toLowerCase();
      if (lower.indexOf("reset") !== -1 ||
          (lower.indexOf("in") !== -1 && (lower.indexOf("h") !== -1 || lower.indexOf("m") !== -1))) {
        return deduplicate(lines[j].trim());
      }
    }
  }
  return null;
}

// A terminal redraw can paint "Resets …" twice on one row; keep the last.
function deduplicate(text) {
  var lower = text.toLowerCase();
  var positions = [];
  var from = 0;
  while (true) {
    var at = lower.indexOf("resets", from);
    if (at === -1) break;
    positions.push(at);
    from = at + 1;
  }
  if (positions.length > 1) return text.slice(positions[positions.length - 1]).trim();
  return text;
}

function cleanResetText(text) {
  if (text === null || text === undefined) return null;
  var trimmed = text.trim();
  if (trimmed === "") return null;
  return /^reset/i.test(trimmed) ? trimmed : "Resets " + trimmed;
}

// Claude's windows, as its plans state them: a 5-hour session, weekly limits.
var SESSION_SECONDS = 5 * 3600;
var WEEK_SECONDS = 7 * 24 * 3600;

function quota(type, name, percentLeft, reset) {
  var q = { type: type, percentRemaining: percentLeft };
  q.windowSeconds = type === "session" ? SESSION_SECONDS : WEEK_SECONDS;
  if (name) q.name = name;
  var cleaned = cleanResetText(reset);
  if (cleaned !== null) q.resetText = cleaned;
  if (reset !== null && reset !== undefined) {
    var at = humanDate(reset);
    if (at !== null) q.resetsAt = at;
  }
  return q;
}

// "$12.34 / $50.00 spent" within 10 lines of "Extra usage".
function extraUsage(screen, lower, lines) {
  if (lower.indexOf("extra usage") === -1) return null;
  if (lower.indexOf("extra usage not enabled") !== -1) return null;
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].toLowerCase().indexOf("extra usage") !== -1) { start = i; break; }
  }
  if (start === -1) return null;
  for (var j = start; j < Math.min(lines.length, start + 10); j++) {
    var match = /\$?([\d,]+\.?\d*)\s*\/\s*\$?([\d,]+\.?\d*)\s*spent/i.exec(lines[j]);
    if (!match) continue;
    var reset = resetText(lines, "Extra usage");
    var cost = {
      kind: "extraUsage",
      used: match[1].replace(/,/g, ""),
      limit: match[2].replace(/,/g, "")
    };
    var cleaned = cleanResetText(reset);
    if (cleaned !== null) cost.resetText = cleaned;
    if (reset !== null) {
      var at = humanDate(reset);
      if (at !== null) cost.resetsAt = at;
    }
    return cost;
  }
  return null;
}
