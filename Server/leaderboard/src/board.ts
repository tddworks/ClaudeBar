// Standings: members ranked by total tokens over a period, ties by username.
// Each member's period ends on their own today, the date their Mac reported at
// its last upload, or UTC's when that is no longer believable.

import { addDays, PERIODS, type Period, utcDay } from "./rules";

export interface Standing {
  rank: number;
  username: string;
  total: number;
  input: number;
  output: number;
  cache: number;
  byProvider: Record<string, number>;
}

interface Row {
  member_id: number;
  username: string;
  provider: string;
  input: number;
  output: number;
  cache: number;
  total: number;
}

/** Every member's tokens in the view, visible ones only unless `includeId` is one of them. */
async function rows(db: D1Database, period: Period, provider: string | null, now: number,
                    includeId: number | null): Promise<Row[]> {
  const utc = utcDay(now);
  const days = PERIODS[period];
  const end = `CASE WHEN m.today BETWEEN ?1 AND ?2 THEN m.today ELSE ?3 END`;
  const statement = db.prepare(
    `SELECT m.id AS member_id, m.username, t.provider,
            SUM(t.input) AS input, SUM(t.output) AS output, SUM(t.cache_write + t.cache_read) AS cache,
            SUM(t.input + t.output + t.cache_write + t.cache_read + t.unsplit) AS total
       FROM members m JOIN daily_tokens t ON t.member_id = m.id
      WHERE ((m.visible = 1 AND m.suspended = 0) OR m.id = ?4)
        AND t.day <= ${end} AND t.day > date(${end}, ?5)
        AND (?6 IS NULL OR t.provider = ?6)
      GROUP BY m.id, t.provider`,
  ).bind(addDays(utc, -1), addDays(utc, 1), utc, includeId ?? -1, `-${days} days`, provider);
  return (await statement.all<Row>()).results;
}

function rank(rows: Row[]): (Standing & { memberId: number })[] {
  const byMember = new Map<number, Standing & { memberId: number }>();
  for (const row of rows) {
    const entry = byMember.get(row.member_id) ??
      { memberId: row.member_id, rank: 0, username: row.username, total: 0, input: 0, output: 0, cache: 0, byProvider: {} };
    entry.total += row.total;
    entry.input += row.input;
    entry.output += row.output;
    entry.cache += row.cache;
    entry.byProvider[row.provider] = (entry.byProvider[row.provider] ?? 0) + row.total;
    byMember.set(row.member_id, entry);
  }
  const ranked = [...byMember.values()]
    .filter((entry) => entry.total > 0)
    .sort((a, b) => b.total - a.total || a.username.toLowerCase().localeCompare(b.username.toLowerCase()));
  ranked.forEach((entry, index) => (entry.rank = index + 1));
  return ranked;
}

const strip = ({ memberId: _, ...standing }: Standing & { memberId: number }): Standing => standing;

export const BOARD_LIMIT = 100;

export async function board(db: D1Database, period: Period, provider: string | null, now: number): Promise<Standing[]> {
  return rank(await rows(db, period, provider, now, null)).slice(0, BOARD_LIMIT).map(strip);
}

/** A member's own standing among the visible members, shown or not themselves. */
export async function standingOf(db: D1Database, memberId: number, period: Period, provider: string | null,
                                 now: number): Promise<Standing | null> {
  const mine = rank(await rows(db, period, provider, now, memberId)).find((entry) => entry.memberId === memberId);
  return mine ? strip(mine) : null;
}
