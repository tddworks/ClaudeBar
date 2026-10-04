# Leaderboard Worker

The API behind ClaudeBar's Leaderboard, live at **https://claudebar-api.tddworks.com**: a Cloudflare Worker with a D1 database. Design, laws and the security review: [docs/features/leaderboard/design.md](../../docs/features/leaderboard/design.md).

| File | Holds |
|---|---|
| `cloudflare.config.ts` | Deploy config for the `cf` CLI: the Worker, its D1 and rate-limit bindings, the hourly cron, the `claudebar-api.tddworks.com/*` route |
| `migrations/` | The D1 schema |
| `src/` | The Worker |
| `test/` | vitest in the Workers runtime against a local D1; `vectors.json` is shared with the Swift suite (`Tests/DomainTests/Leaderboard`), so change both sides together |

## Develop

```bash
npm ci
npm test              # the tests declare their own local bindings in vitest.config.ts
npm run typecheck
```

## Deploy (maintainers)

Uses the [`cf` CLI](https://developers.cloudflare.com/cf), logged in to the tddworks account. Nothing deploys from CI, and no Cloudflare token belongs in the repo.

```bash
npm run migrate:remote   # cf d1 migrations apply <database id> --dir migrations
npm run deploy           # cf deploy
```

Set up once, not needed again:

- the D1 database `claudebar-leaderboard` (its id is in `cloudflare.config.ts` and `package.json`);
- a proxied `AAAA 100::` DNS record for `claudebar-api` in the `tddworks.com` zone, which the route needs.

The address is baked into the app (`LeaderboardHTTPClient.defaultHost`) and the board page (`docs/leaderboard/index.html`: `API` and its CSP). Change all three together.

## Moderation

Keeping a member off the public board (they can't undo it through the API):

```bash
cf d1 query 47a18949-32a1-4f55-b537-b40c3462b5b0 --body '{"sql":"UPDATE members SET suspended = 1 WHERE lower(username) = lower(?)","params":["name"]}'
```
