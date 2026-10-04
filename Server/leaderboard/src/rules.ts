// The server's rules about what may be stored. The username rule is pinned by
// test/vectors.json, which the app's suite reads too.

const USERNAME = /^[A-Za-z0-9_-]{3,20}$/;
const PROVIDER = /^[a-z0-9-]{1,32}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

/** Names nobody may take, ignoring case: they would read as official. */
const RESERVED = new Set([
  "admin", "administrator", "root", "system", "support", "help", "official", "moderator", "mod",
  "claudebar", "claude-bar", "tddworks", "anthropic", "claude", "openai", "codex", "chatgpt",
  "google", "gemini", "github", "copilot", "cloudflare", "leaderboard", "null", "undefined", "you", "me",
]);

/** The most tokens one provider's day may hold before it's implausible. */
export const MAX_DAY_TOKENS = 10_000_000_000;
/** At most this many rows per upload: 31 days of a dozen providers. */
export const MAX_ROWS = 400;
/** Days older than this are refused. */
export const MAX_AGE_DAYS = 31;
export const MAX_BODY_BYTES = 64 * 1024;

export const isUsername = (value: unknown): value is string => typeof value === "string" && USERNAME.test(value);
export const isReserved = (username: string) => RESERVED.has(username.toLowerCase());
export const isProvider = (value: unknown): value is string => typeof value === "string" && PROVIDER.test(value);

export function isDay(value: unknown): value is string {
  if (typeof value !== "string" || !DAY.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().startsWith(value);
}

export function addDays(day: string, delta: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
}

export const utcDay = (now: number) => new Date(now).toISOString().slice(0, 10);

/** A member's own today is believable within a day of UTC's. */
export const isBelievableToday = (today: string, now: number) =>
  today >= addDays(utcDay(now), -1) && today <= addDays(utcDay(now), 1);

export interface DayRow {
  provider: string;
  day: string;
  input: number;
  output: number;
  cacheWrite: number;
  cacheRead: number;
  unsplit: number;
}

const COUNTS = ["input", "output", "cacheWrite", "cacheRead", "unsplit"] as const;

/** The row, or why it's refused. `today` is the member's own date. */
export function parseDay(value: unknown, today: string): DayRow | string {
  if (typeof value !== "object" || value === null) return "a day must be an object";
  const row = value as Record<string, unknown>;
  if (!isProvider(row.provider)) return "provider must be 1–32 of a–z, 0–9 or -";
  if (!isDay(row.day)) return "day must be YYYY-MM-DD";
  if (row.day > today) return "a day can't be in the future";
  if (row.day <= addDays(today, -MAX_AGE_DAYS)) return `days older than ${MAX_AGE_DAYS} days are refused`;
  let total = 0;
  for (const key of COUNTS) {
    const count = row[key] ?? 0;
    if (typeof count !== "number" || !Number.isSafeInteger(count) || count < 0) return `${key} must be a whole number`;
    total += count;
  }
  if (total > MAX_DAY_TOKENS) return "a day can't hold that many tokens";
  return {
    provider: row.provider, day: row.day,
    input: (row.input as number) ?? 0, output: (row.output as number) ?? 0,
    cacheWrite: (row.cacheWrite as number) ?? 0, cacheRead: (row.cacheRead as number) ?? 0,
    unsplit: (row.unsplit as number) ?? 0,
  };
}

export const PERIODS = { today: 1, "7d": 7, "30d": 30 } as const;
export type Period = keyof typeof PERIODS;
export const isPeriod = (value: unknown): value is Period => typeof value === "string" && value in PERIODS;
