// ClaudeBar Leaderboard API. Design and laws: docs/features/leaderboard/design.md.
// Logs nothing about a request: no IPs, bodies, signatures or keys.

import { board, standingOf } from "./board";
import {
  isBelievableToday, isDay, isPeriod, isProvider, isReserved, isUsername,
  MAX_BODY_BYTES, MAX_ROWS, parseDay, type DayRow, type Period,
} from "./rules";
import { canonical, isFresh, isNonce, isPublicKey, verify } from "./signing";

export interface Env {
  DB: D1Database;
  JOIN_LIMITER?: RateLimit;
  RENAME_LIMITER?: RateLimit;
}

interface Member {
  id: number;
  username: string;
  public_key: string;
  visible: number;
  today: string | null;
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...headers } });

const failure = (status: number, error: string, message: string) => json({ error, message }, status);

class Refusal extends Error {
  constructor(readonly response: Response) {
    super(response.statusText);
  }
}

async function readBody(request: Request): Promise<ArrayBuffer> {
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > MAX_BODY_BYTES) throw new Refusal(failure(413, "tooLarge", "That request is too large."));
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_BODY_BYTES) throw new Refusal(failure(413, "tooLarge", "That request is too large."));
  return body;
}

function parseJSON(body: ArrayBuffer): Record<string, unknown> {
  try {
    const value = JSON.parse(new TextDecoder().decode(body));
    if (typeof value === "object" && value !== null && !Array.isArray(value)) return value;
  } catch {}
  throw new Refusal(failure(400, "badRequest", "The body must be a JSON object."));
}

async function limited(limiter: RateLimit | undefined, request: Request): Promise<boolean> {
  if (!limiter) return false;
  const key = request.headers.get("cf-connecting-ip") ?? "unknown";
  return !(await limiter.limit({ key })).success;
}

const findMember = (db: D1Database, username: string) =>
  db.prepare("SELECT id, username, public_key, visible, today FROM members WHERE lower(username) = lower(?)")
    .bind(username).first<Member>();

/**
 * The member who signed `request`, or a refusal. The member is looked up by
 * `X-Member` and the signature checked against **their** key; the nonce is
 * stored only after the signature verified, so nobody can burn another's.
 */
async function signedMember(request: Request, env: Env, body: ArrayBuffer, now: number): Promise<Member> {
  const unauthorized = () => new Refusal(failure(401, "unauthorized", "The signature was not accepted."));
  const username = request.headers.get("x-member") ?? "";
  const timestamp = request.headers.get("x-timestamp") ?? "";
  const nonce = request.headers.get("x-nonce") ?? "";
  const signature = request.headers.get("x-signature") ?? "";
  if (!isUsername(username) || !isNonce(nonce)) throw unauthorized();
  if (!isFresh(timestamp, now)) throw new Refusal(failure(401, "clock", "This Mac's clock is more than five minutes off."));
  const member = await findMember(env.DB, username);
  if (!member) throw unauthorized();
  const url = new URL(request.url);
  const message = await canonical(request.method, url.pathname + url.search, timestamp, nonce, body);
  if (!(await verify(member.public_key, signature, message))) throw unauthorized();
  const stored = await env.DB.prepare("INSERT OR IGNORE INTO nonces (nonce, seen_at) VALUES (?, ?)")
    .bind(nonce, Math.floor(now / 1000)).run();
  if (stored.meta.changes !== 1) throw new Refusal(failure(401, "replay", "That request was already used."));
  return member;
}

function view(url: URL): { period: Period; provider: string | null } {
  const period = url.searchParams.get("period") ?? "7d";
  const provider = url.searchParams.get("provider");
  if (!isPeriod(period)) throw new Refusal(failure(400, "badRequest", "period must be today, 7d or 30d."));
  if (provider !== null && !isProvider(provider)) throw new Refusal(failure(400, "badRequest", "Unknown provider."));
  return { period, provider };
}

async function join(request: Request, env: Env, now: number): Promise<Response> {
  if (await limited(env.JOIN_LIMITER, request)) return failure(429, "slowDown", "Too many joins from here. Try again in a minute.");
  const body = parseJSON(await readBody(request));
  if (!isUsername(body.username)) return failure(400, "invalidUsername", "Use 3–20 letters, numbers, - or _.");
  if (isReserved(body.username)) return failure(409, "usernameTaken", "That username is taken.");
  if (!isPublicKey(body.publicKey)) return failure(400, "badRequest", "publicKey must be 32 bytes, base64url.");
  const inserted = await env.DB.prepare(
    "INSERT OR IGNORE INTO members (username, public_key, visible, joined_at) VALUES (?, ?, 1, ?)",
  ).bind(body.username, body.publicKey, new Date(now).toISOString()).run();
  if (inserted.meta.changes !== 1) return failure(409, "usernameTaken", "That username is taken.");
  return json({ username: body.username }, 201);
}

async function upload(member: Member, env: Env, body: ArrayBuffer, now: number): Promise<Response> {
  const payload = parseJSON(body);
  const today = payload.today;
  if (!isDay(today) || !isBelievableToday(today, now)) return failure(400, "clock", "This Mac's date doesn't look right.");
  if (!Array.isArray(payload.days) || payload.days.length > MAX_ROWS) {
    return failure(400, "badRequest", `days must be a list of at most ${MAX_ROWS}.`);
  }
  const rows: DayRow[] = [];
  for (const day of payload.days) {
    const row = parseDay(day, today);
    if (typeof row === "string") return failure(400, "badDay", row);
    rows.push(row);
  }
  const upsert = env.DB.prepare(
    `INSERT INTO daily_tokens (member_id, provider, day, input, output, cache_write, cache_read, unsplit)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (member_id, provider, day) DO UPDATE SET
       input = excluded.input, output = excluded.output, cache_write = excluded.cache_write,
       cache_read = excluded.cache_read, unsplit = excluded.unsplit`,
  );
  await env.DB.batch([
    ...rows.map((r) => upsert.bind(member.id, r.provider, r.day, r.input, r.output, r.cacheWrite, r.cacheRead, r.unsplit)),
    env.DB.prepare("UPDATE members SET today = ? WHERE id = ?").bind(today, member.id),
  ]);
  return json({ stored: rows.length });
}

async function me(member: Member, env: Env, url: URL, now: number): Promise<Response> {
  const { period, provider } = view(url);
  const days = await env.DB.prepare(
    `SELECT provider, day, input, output, cache_write AS cacheWrite, cache_read AS cacheRead, unsplit
       FROM daily_tokens WHERE member_id = ? ORDER BY day, provider`,
  ).bind(member.id).all();
  const body = {
    username: member.username,
    visible: member.visible === 1,
    standing: await standingOf(env.DB, member.id, period, provider, now),
    days: days.results,
  };
  const headers: Record<string, string> = { "cache-control": "no-store" };
  if (url.pathname === "/me/export") {
    headers["content-disposition"] = `attachment; filename="claudebar-leaderboard-${member.username}.json"`;
  }
  return json(body, 200, headers);
}

async function update(member: Member, request: Request, env: Env, body: ArrayBuffer): Promise<Response> {
  const payload = parseJSON(body);
  if (payload.visible !== undefined) {
    if (typeof payload.visible !== "boolean") return failure(400, "badRequest", "visible must be true or false.");
    await env.DB.prepare("UPDATE members SET visible = ? WHERE id = ?").bind(payload.visible ? 1 : 0, member.id).run();
  }
  if (payload.username !== undefined) {
    if (await limited(env.RENAME_LIMITER, request)) return failure(429, "slowDown", "Too many renames. Try again in a minute.");
    if (!isUsername(payload.username)) return failure(400, "invalidUsername", "Use 3–20 letters, numbers, - or _.");
    if (isReserved(payload.username)) return failure(409, "usernameTaken", "That username is taken.");
    const renamed = await env.DB.prepare(
      `UPDATE members SET username = ?1 WHERE id = ?2
         AND NOT EXISTS (SELECT 1 FROM members WHERE lower(username) = lower(?1) AND id != ?2)`,
    ).bind(payload.username, member.id).run();
    if (renamed.meta.changes !== 1) return failure(409, "usernameTaken", "That username is taken.");
  }
  return json({ ok: true });
}

async function leave(member: Member, env: Env): Promise<Response> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM daily_tokens WHERE member_id = ?").bind(member.id),
    env.DB.prepare("DELETE FROM members WHERE id = ?").bind(member.id),
  ]);
  return json({ deleted: true });
}

const BOARD_CORS = { "access-control-allow-origin": "*", "access-control-allow-methods": "GET" };

async function publicBoard(env: Env, url: URL, now: number): Promise<Response> {
  const { period, provider } = view(url);
  return json({ period, provider, standings: await board(env.DB, period, provider, now) }, 200, {
    ...BOARD_CORS, "cache-control": "public, max-age=300",
  });
}

export async function handle(request: Request, env: Env, now: number): Promise<Response> {
  const url = new URL(request.url);
  const route = `${request.method} ${url.pathname}`;
  try {
    switch (route) {
      case "OPTIONS /board": return new Response(null, { status: 204, headers: BOARD_CORS });
      case "GET /board": return await publicBoard(env, url, now);
      case "POST /join": return await join(request, env, now);
      case "PUT /usage":
      case "GET /me":
      case "GET /me/export":
      case "PATCH /me":
      case "DELETE /me": {
        const body = await readBody(request);
        const member = await signedMember(request, env, body, now);
        if (route === "PUT /usage") return await upload(member, env, body, now);
        if (route === "PATCH /me") return await update(member, request, env, body);
        if (route === "DELETE /me") return await leave(member, env);
        return await me(member, env, url, now);
      }
      default: return failure(404, "notFound", "No such route.");
    }
  } catch (error) {
    if (error instanceof Refusal) return error.response;
    return failure(500, "internal", "Something went wrong on the leaderboard.");
  }
}

export default {
  fetch: (request: Request, env: Env) => handle(request, env, Date.now()),
  // Hourly: forget nonces older than ten minutes; they can't be replayed anyway.
  scheduled: async (_controller: ScheduledController, env: Env) => {
    await env.DB.prepare("DELETE FROM nonces WHERE seen_at < ?").bind(Math.floor(Date.now() / 1000) - 600).run();
  },
} satisfies ExportedHandler<Env>;
