// The site's own laws, checked on the files that ship: `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../public/${path}`, import.meta.url), "utf8");
const headers = read("_headers");
const policy = headers;
const pages = { landing: read("index.html"), board: read("leaderboard/index.html") };

test("every page has a strict policy: its own scripts, and only the API to talk to", () => {
  assert.match(policy, /^\/\*$/m);
  assert.match(policy, /default-src 'none'/);
  assert.match(policy, /script-src 'self' 'unsafe-inline';/);
  assert.match(policy, /connect-src 'self' https:\/\/claudebar-api\.tddworks\.com;/);
  assert.match(policy, /frame-ancestors 'none'/);
  assert.match(policy, /X-Content-Type-Options: nosniff/);
});

test("the board writes standings as text, never as HTML, and loads its globe from this origin", () => {
  assert.doesNotMatch(pages.board, /innerHTML/);
  assert.match(pages.board, /src="\/leaderboard\/globe\.js"/);
  assert.match(pages.board, /const API = "https:\/\/claudebar-api\.tddworks\.com";/);
});

test("the landing page shows sample members only, labelled as such", () => {
  const sample = pages.landing.slice(pages.landing.indexOf('id="leaderboard"'), pages.landing.indexOf("</section>", pages.landing.indexOf('id="leaderboard"')));
  assert.match(sample, /Sample data/);
  assert.match(sample, /not real members/);
  const names = [...sample.matchAll(/@([a-z0-9_-]+)/gi)].map((m) => m[1]);
  assert.ok(names.length > 0);
  for (const name of names) assert.ok(name === "you" || name.startsWith("sample-"), `@${name} isn't a sample name`);
});

test("Sparkle's feed stays on GitHub Pages", () => {
  assert.match(pages.landing, /https:\/\/tddworks\.github\.io\/ClaudeBar\/appcast\.xml/);
});

// The built-in providers, as the app finds them: every definition in the bundle, in lineup order.
const definitions = (() => {
  const folder = new URL("../../ClaudeBarKit/definitions/", import.meta.url);
  return readdirSync(folder)
    .filter((file) => file.endsWith(".json"))
    .map((file) => JSON.parse(readFileSync(new URL(file, folder), "utf8")))
    .filter((definition) => definition.profile)
    .sort((a, b) => (a.order ?? Infinity) - (b.order ?? Infinity) || a.profile.name.localeCompare(b.profile.name))
    .map((definition) => definition.profile.id);
})();

test("the landing page shows every built-in provider, in the app's order", () => {
  const grid = pages.landing.slice(pages.landing.indexOf('class="pv-grid'), pages.landing.indexOf("</div>\n\n", pages.landing.indexOf('class="pv-grid')));
  const shown = [...grid.matchAll(/class="pv" data-id="([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(shown, definitions);
});

test("every count on the landing page is the number of built-in providers", () => {
  const count = String(definitions.length);
  const counts = [
    pages.landing.match(/<meta name="description" content="[^"]*?(\d+) AI coding assistants/)?.[1],
    pages.landing.match(/<meta property="og:description" content="[^"]*?(\d+) AI coding assistants/)?.[1],
    pages.landing.match(/class="eyebrow[^>]*><b>(\d+) providers<\/b>/)?.[1],
    pages.landing.match(/<div class="stat"[^>]*><b>(\d+)<\/b><span>providers tracked/)?.[1],
    pages.landing.match(/<h2>(\d+) assistants, one place to look\.<\/h2>/)?.[1],
  ];
  assert.deepEqual(counts, Array(counts.length).fill(count));
});
