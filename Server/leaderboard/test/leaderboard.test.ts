import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { type Env, handle } from "../src/index";
import { canonical, verify } from "../src/signing";
import vectors from "./vectors.json";

const NOW = Date.parse("2026-10-04T12:00:00Z");
const TODAY = "2026-10-04";
const base = "https://leaderboard.test";

const b64u = (bytes: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

interface Member {
  username: string;
  key: CryptoKeyPair;
  publicKey: string;
}

let nonceCounter = 0;
const nextNonce = () => {
  const bytes = new Uint8Array(16);
  new DataView(bytes.buffer).setUint32(0, ++nonceCounter);
  bytes[15] = Math.floor(Math.random() * 256);
  return b64u(bytes);
};

async function makeKey(): Promise<{ key: CryptoKeyPair; publicKey: string }> {
  const key = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  return { key, publicKey: b64u(await crypto.subtle.exportKey("raw", key.publicKey) as ArrayBuffer) };
}

/** Without the rate limiters, which have their own test. */
const unlimited: Env = { DB: env.DB };

beforeEach(async () => {
  await env.DB.batch(["daily_tokens", "members", "nonces"].map((table) => env.DB.prepare(`DELETE FROM ${table}`)));
});

const call = (method: string, path: string, body?: unknown, headers: Record<string, string> = {}, now = NOW,
              environment: Env = unlimited) =>
  handle(new Request(base + path, {
    method, headers: { "content-type": "application/json", ...headers },
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  }), environment, now);

async function join(username: string): Promise<Member> {
  const { key, publicKey } = await makeKey();
  const response = await call("POST", "/join", { username, publicKey });
  expect(response.status).toBe(201);
  return { username, key, publicKey };
}

interface Signed {
  as?: string;
  nonce?: string;
  timestamp?: number;
  now?: number;
}

async function signed(member: Member, method: string, path: string, body?: unknown, options: Signed = {}) {
  const text = body === undefined ? "" : JSON.stringify(body);
  const timestamp = String(options.timestamp ?? Math.floor((options.now ?? NOW) / 1000));
  const nonce = options.nonce ?? nextNonce();
  const message = await canonical(method, path, timestamp, nonce, new TextEncoder().encode(text));
  const signature = b64u(await crypto.subtle.sign({ name: "Ed25519" }, member.key.privateKey, new TextEncoder().encode(message)));
  return call(method, path, body === undefined ? undefined : text, {
    "x-member": options.as ?? member.username, "x-timestamp": timestamp, "x-nonce": nonce, "x-signature": signature,
  }, options.now ?? NOW);
}

const day = (provider: string, date: string, input: number, extra: Partial<Record<string, number>> = {}) =>
  ({ provider, day: date, input, output: 0, cacheWrite: 0, cacheRead: 0, unsplit: 0, ...extra });

const upload = (member: Member, days: unknown[], today = TODAY) => signed(member, "PUT", "/usage", { today, days });

async function standings(query = "period=7d") {
  const response = await call("GET", `/board?${query}`);
  return ((await response.json()) as { standings: { username: string; total: number; rank: number }[] }).standings;
}

describe("shared vectors", () => {
  it("builds the same signed text the app builds", async () => {
    for (const c of vectors.signing.cases) {
      expect(await canonical(c.method, c.pathAndQuery, String(c.timestamp), c.nonce, new TextEncoder().encode(c.body)))
        .toBe(c.canonical);
    }
  });

  it("accepts the signatures made for the shared key", async () => {
    for (const c of vectors.signing.cases) {
      expect(await verify(vectors.signing.publicKey, c.signature, c.canonical)).toBe(true);
    }
  });

  it("accepts a whole request signed with the shared key", async () => {
    await env.DB.prepare("INSERT INTO members (username, public_key, joined_at) VALUES ('tokenwhale', ?, 'now')")
      .bind(vectors.signing.publicKey).run();
    const c = vectors.signing.cases[1];
    const response = await call(c.method, c.pathAndQuery, undefined, {
      "x-member": "tokenwhale", "x-timestamp": String(c.timestamp), "x-nonce": c.nonce, "x-signature": c.signature,
    }, c.timestamp * 1000);
    expect(response.status).toBe(200);
  });

  it("allows exactly the usernames the app allows", async () => {
    for (const username of vectors.usernames.valid) {
      const { publicKey } = await makeKey();
      expect((await call("POST", "/join", { username, publicKey })).status, username).toBe(201);
    }
    for (const username of vectors.usernames.invalid) {
      const { publicKey } = await makeKey();
      expect((await call("POST", "/join", { username, publicKey })).status, username).toBe(400);
    }
  });
});

describe("joining", () => {
  it("refuses a name taken in any case", async () => {
    await join("tokenwhale");
    const { publicKey } = await makeKey();
    const response = await call("POST", "/join", { username: "TokenWhale", publicKey });
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: "usernameTaken" });
  });

  it("refuses names that would read as official", async () => {
    for (const username of ["admin", "ClaudeBar", "Anthropic", "tddworks"]) {
      const { publicKey } = await makeKey();
      expect((await call("POST", "/join", { username, publicKey })).status, username).toBe(409);
    }
  });

  it("slows down many joins from one address", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 7; i++) {
      const { publicKey } = await makeKey();
      statuses.push((await call("POST", "/join", { username: `spam${i}`, publicKey }, { "cf-connecting-ip": "203.0.113.9" },
                                NOW, env as unknown as Env)).status);
    }
    expect(statuses.slice(0, 5)).toEqual([201, 201, 201, 201, 201]);
    expect(statuses).toContain(429);
  });

  it("refuses a public key that isn't 32 bytes", async () => {
    expect((await call("POST", "/join", { username: "shortkey", publicKey: "abc" })).status).toBe(400);
  });

  it("refuses a body that isn't a JSON object", async () => {
    expect((await call("POST", "/join", "[1,2]")).status).toBe(400);
  });

  it("refuses an oversized body", async () => {
    expect((await call("POST", "/join", { username: "big", pad: "x".repeat(70_000) })).status).toBe(413);
  });
});

describe("signatures", () => {
  it("refuses a request signed by someone else's key", async () => {
    const victim = await join("victim");
    const attacker = await join("attacker");
    const response = await signed(attacker, "DELETE", "/me", undefined, { as: victim.username });
    expect(response.status).toBe(401);
    expect((await signed(victim, "GET", "/me")).status).toBe(200);
  });

  it("refuses a body changed after signing", async () => {
    const member = await join("tamper");
    const text = JSON.stringify({ today: TODAY, days: [day("claude", TODAY, 10)] });
    const timestamp = String(Math.floor(NOW / 1000));
    const nonce = nextNonce();
    const message = await canonical("PUT", "/usage", timestamp, nonce, new TextEncoder().encode(text));
    const signature = b64u(await crypto.subtle.sign({ name: "Ed25519" }, member.key.privateKey, new TextEncoder().encode(message)));
    const response = await call("PUT", "/usage", text.replace("10", "99999"), {
      "x-member": member.username, "x-timestamp": timestamp, "x-nonce": nonce, "x-signature": signature,
    });
    expect(response.status).toBe(401);
  });

  it("refuses a request used twice", async () => {
    const member = await join("replay");
    const nonce = nextNonce();
    expect((await signed(member, "GET", "/me", undefined, { nonce })).status).toBe(200);
    const again = await signed(member, "GET", "/me", undefined, { nonce });
    expect(again.status).toBe(401);
    expect(await again.json()).toMatchObject({ error: "replay" });
  });

  it("refuses a request more than five minutes old", async () => {
    const member = await join("stale");
    const response = await signed(member, "GET", "/me", undefined, { timestamp: Math.floor(NOW / 1000) - 301 });
    expect(await response.json()).toMatchObject({ error: "clock" });
  });

  it("doesn't let a bad signature use up a nonce", async () => {
    const member = await join("burn");
    const nonce = nextNonce();
    await call("GET", "/me", undefined, {
      "x-member": member.username, "x-timestamp": String(Math.floor(NOW / 1000)), "x-nonce": nonce, "x-signature": "AAAA",
    });
    expect((await signed(member, "GET", "/me", undefined, { nonce })).status).toBe(200);
  });

  it("refuses an unsigned request to a member route", async () => {
    expect((await call("GET", "/me")).status).toBe(401);
  });
});

describe("uploading", () => {
  it("replaces a day uploaded again, never adds", async () => {
    const member = await join("again");
    await upload(member, [day("claude", TODAY, 100)]);
    await upload(member, [day("claude", TODAY, 150)]);
    expect((await standings()).find((s) => s.username === "again")?.total).toBe(150);
  });

  it("refuses future days, days older than 31, unknown provider shapes and implausible totals", async () => {
    const member = await join("strict");
    expect((await upload(member, [day("claude", "2026-10-05", 1)])).status).toBe(400);
    expect((await upload(member, [day("claude", "2026-09-03", 1)])).status).toBe(400);
    expect((await upload(member, [day("<script>", TODAY, 1)])).status).toBe(400);
    expect((await upload(member, [day("claude", TODAY, 10_000_000_001)])).status).toBe(400);
    expect((await upload(member, [day("claude", TODAY, -1)])).status).toBe(400);
  });

  it("refuses a Mac whose date is more than a day off", async () => {
    const member = await join("clocky");
    expect((await upload(member, [day("claude", "2026-10-01", 1)], "2026-10-01")).status).toBe(400);
  });

  it("refuses too many rows in one upload", async () => {
    const member = await join("bulk");
    const days = Array.from({ length: 401 }, (_, i) => day(`p${i}`, TODAY, 1));
    expect((await upload(member, days)).status).toBe(400);
  });
});

describe("the board", () => {
  it("ranks by total tokens, ties by username, hidden members left out", async () => {
    const big = await join("big");
    const tieB = await join("tie-b");
    const tieA = await join("tie-a");
    const hidden = await join("hidden");
    await upload(big, [day("claude", TODAY, 500, { cacheRead: 500 })]);
    await upload(tieB, [day("codex", TODAY, 300)]);
    await upload(tieA, [day("claude", TODAY, 300)]);
    await upload(hidden, [day("claude", TODAY, 9_000)]);
    await signed(hidden, "PATCH", "/me", { visible: false });

    const board = await standings();

    expect(board.map((s) => [s.rank, s.username, s.total])).toEqual([[1, "big", 1000], [2, "tie-a", 300], [3, "tie-b", 300]]);
  });

  it("keeps a suspended member off the board even when they'd show themselves", async () => {
    const member = await join("spammer");
    await upload(member, [day("claude", TODAY, 500)]);
    await env.DB.prepare("UPDATE members SET suspended = 1 WHERE username = 'spammer'").run();
    await signed(member, "PATCH", "/me", { visible: true });

    expect(await standings()).toEqual([]);
  });

  it("filters by provider and period, each member's period ending on their own today", async () => {
    const member = await join("periodic");
    await upload(member, [day("claude", TODAY, 10), day("claude", "2026-10-01", 20), day("codex", TODAY, 5)]);

    expect((await standings("period=today"))[0].total).toBe(15);
    expect((await standings("period=7d&provider=claude"))[0].total).toBe(30);
  });

  it("refuses an unknown period or provider shape", async () => {
    expect((await call("GET", "/board?period=1y")).status).toBe(400);
    expect((await call("GET", "/board?provider=%3Cb%3E")).status).toBe(400);
  });

  it("is readable from any web page; member routes aren't", async () => {
    const member = await join("cors");
    expect((await call("GET", "/board")).headers.get("access-control-allow-origin")).toBe("*");
    expect((await signed(member, "GET", "/me")).headers.get("access-control-allow-origin")).toBeNull();
  });
});

describe("your own data", () => {
  it("shows a hidden member their own standing and every day they uploaded", async () => {
    const member = await join("private");
    await upload(member, [day("claude", TODAY, 40)]);
    await signed(member, "PATCH", "/me", { visible: false });

    const body = (await (await signed(member, "GET", "/me?period=7d")).json()) as {
      visible: boolean; standing: { rank: number; total: number }; days: unknown[];
    };

    expect(body.visible).toBe(false);
    expect(body.standing).toMatchObject({ rank: 1, total: 40 });
    expect(body.days).toHaveLength(1);
  });

  it("exports it as a file", async () => {
    const member = await join("exporter");
    const response = await signed(member, "GET", "/me/export");
    expect(response.headers.get("content-disposition")).toContain("claudebar-leaderboard-exporter.json");
  });

  it("renames, refusing a taken or reserved name", async () => {
    const member = await join("before");
    await join("taken");
    expect((await signed(member, "PATCH", "/me", { username: "TAKEN" })).status).toBe(409);
    expect((await signed(member, "PATCH", "/me", { username: "admin" })).status).toBe(409);
    expect((await signed(member, "PATCH", "/me", { username: "after" })).status).toBe(200);
    expect((await signed({ ...member, username: "after" }, "GET", "/me")).status).toBe(200);
  });

  it("leaving deletes the member and every row", async () => {
    const member = await join("leaver");
    await upload(member, [day("claude", TODAY, 10)]);

    expect((await signed(member, "DELETE", "/me")).status).toBe(200);

    const rows = await env.DB.prepare("SELECT COUNT(*) AS n FROM daily_tokens").first<{ n: number }>();
    expect(rows?.n).toBe(0);
    expect((await signed(member, "GET", "/me")).status).toBe(401);
    expect((await standings()).find((s) => s.username === "leaver")).toBeUndefined();
  });
});
