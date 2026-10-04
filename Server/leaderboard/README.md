# Leaderboard Worker

The API behind ClaudeBar's Leaderboard: a Cloudflare Worker with a D1 database. Design, laws and the security review: [docs/features/leaderboard/design.md](../../docs/features/leaderboard/design.md).

## Develop

```bash
npm ci
npm test                 # vitest in the Workers runtime, against a local D1
npx tsc --noEmit
npm run migrate:local && npm run dev   # http://localhost:8787
```

`test/vectors.json` is shared with the Swift suite (`Tests/DomainTests/Leaderboard`): the username rule and the signing cases. Change both sides together.

## Deploy (maintainers)

Needs a Cloudflare account with Workers and D1. Nothing here runs from CI, and no Cloudflare token belongs in the repo.

1. `npx wrangler d1 create claudebar-leaderboard`, then put the printed `database_id` in `wrangler.jsonc`.
2. `npm run migrate:remote`
3. `npx wrangler deploy`
4. If the Worker's URL isn't `https://claudebar-leaderboard.tddworks.workers.dev`, update `LeaderboardHTTPClient.defaultHost` and the board page's `API` and CSP (`docs/leaderboard/index.html`).

Keeping a member off the public board (they can't undo it through the API): `npx wrangler d1 execute claudebar-leaderboard --remote --command "UPDATE members SET suspended = 1 WHERE lower(username) = lower('name')"`.
