# Muse Code: design

Contributor research for `meta-muse`. User setup is in [README.md](README.md).

## Source

Muse has no usage API. ClaudeBar runs only `muse usage --json` through the existing `command` fetch, using the Meta login Muse keeps on this Mac. There is no HTTP source, API key, credential lookup or API fallback. ClaudeBar does not read or copy Muse's credentials.

The default macOS installation is `~/.local/bin/muse`. The existing `BinaryLocator` searches `~/.local/bin`, so the definition keeps the portable name `muse` without a hardcoded user path or a login-shell workaround. The missing-binary test checks that an absent executable reports `cliNotFound("muse")`.

Confirmed with Muse Code 1.4.20 (`1.4.20-R8619.1`). `muse usage --help` calls this operation "Show your subscription allowance (no model turn)". It accepts `--json` and prints one JSON object. A successful capture:

```json
{
  "schemaVersion": 1,
  "allowance": {
    "tier": "Muse Code High Usage",
    "window": { "usedPercent": 1, "resetsAtMs": 1794651434000 },
    "weekly": { "usedPercent": 7, "resetsAtMs": 1794787200000 },
    "asOfMs": 1794636810548,
    "source": "mint"
  },
  "reason": null,
  "hint": null
}
```

The text form names the same three values: Tier, Window and Weekly. No account identifier or per-model quota appears in this response. Treat this as one subscription allowance shared by Muse's models.

## Mapping decisions

- Keep the stable id `meta-muse`, display name `Muse Code`, CLI `muse`, and lineup order 310. Enable it by default, as with the other installed-CLI providers. No dashboard URL was verified, so none is declared.
- Convert `usedPercent` into `100 - usedPercent`. Accept finite JSON numbers from 0 through 100; reject strings, flags and out-of-range values instead of presenting them as valid quota.
- Map `window` to Session and `weekly` to Weekly. Convert `resetsAtMs` into epoch seconds by dividing by 1000. A missing or null reset means an unknown reset; reject a supplied nonnumeric or negative timestamp.
- State the weekly length as seven days. The capture gives neither the session's start nor its length. Leave its `windowSeconds` absent so pace calculations do not assume five hours. The generic Session menu-bar short label remains `5h`; confirming Muse's session length is still needed before treating that label as a measured duration.
- Preserve a nonblank `allowance.tier` as a custom plan badge, including its spelling. Do not add a vendor case to `AccountTier`. Leave the badge absent if Muse supplies no tier.
- `asOfMs` and `source` describe Muse's allowance capture. ClaudeBar keeps its own refresh time and does not infer token usage or cost from either field.

### Why a mapping script

The existing JSON mapper has no schema guard or response-dependent error rule. It also has no epoch-millisecond reset case. Adding only that reset case would still allow an unsupported schema or a null allowance to pass without explaining Muse's `reason` and `hint`. The provider therefore uses the existing, sandboxed `Mapping.script` case for this envelope, as Oh My Pi does. This adds no engine case or Swift vendor type.

The script requires numeric `schemaVersion: 1` and an object allowance with at least one readable quota window. A missing quota window is unknown and omitted; a supplied malformed window fails the response. Unknown schemas and malformed payloads fail the mapping step. A null allowance with a reason or hint reports those fields as an error, rather than a zero-usage quota. Known sign-in reason words report Session expired; other reasons report an execution failure. No full JSON body is copied into an error.

Only the successful capture above came from a live account. Failure envelopes in the tests are synthetic contract checks; this work does not sign the person out or claim to have captured real authentication or rate-limit responses. A nonzero command exit fails at fetching and reports its code without copying command output into the error.

## Accounts and appearance

The definition offers only the default login on this Mac. Without a documented Muse mechanism for isolating a login, ClaudeBar does not offer Add Account or accept a pasted key. The generic account-read rules leave this machine's command out of any added login.

`profile.look` carries the blue palette, SF Symbol fallback and `MetaMuseIcon` asset name. The icon uses the official Meta symbol sourced from Meta's brand site (https://www.meta.com/brand/resources/meta/company-brand/), rendered as a blue gradient loop on a white rounded square per the icon guide. Muse Code runs through the official Muse CLI (https://dev.meta.ai/products/muse-code). Meta holds all trademark rights in the Meta and Muse marks; this use is nominative to identify the provider and requires Meta permission, which has not been sought. Maintainers may reject or replace the mark.

## Verification

`MetaMuseDefinitionTests` reads the bundled definition and mapping through the real Provider with a stubbed CLI. It checks the successful capture, numeric boundaries, reset conversion, tier text, absent windows, invalid payloads, reason/hint errors, missing CLI, command failure and isolation from added accounts. Detection tests pin the new lineup position. The website tests read the definitions to check its provider tile and count.
